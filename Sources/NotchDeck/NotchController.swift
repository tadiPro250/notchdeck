import AppKit
import Combine
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.premprateek.notchdeck", category: "notch")

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click land on a control even though the panel never becomes key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Everything the views read from, bundled so it can be handed down in one piece.
struct NotchServices {
    let settings: AppSettings
    let player: NowPlaying
    let lyrics: LyricsService
    let tray: FileTray
    let volume: VolumeControl
    let brightness: BrightnessControl
    let system: SystemStatus
    let actions: QuickActions
    let calendar: CalendarService
    let reminders: RemindersService
    let weather: WeatherService
    let clipboard: ClipboardHistory
    let stats: SystemStats
    let timer: FocusTimer
    let clock: ClockCenter
    let camera: CameraMirror
    let downloads: DownloadWatcher
    let focus: FocusWatcher
    let privacy: PrivacyMonitor
    let accessories: AccessoryBatteries
    let audio: AudioDevices
    let displays: ExternalDisplays
    let keyboard: KeyboardBacklight
    let notes: NotesStore
    let shortcuts: ShortcutsService
    let script: ScriptRunner
    let updates: UpdateChecker
    let cat: CatBrain
    let tasks: TaskStore
    let pomodoro: PomodoroTimer
    let colors: ColorDropper

    static func live(settings: AppSettings) -> NotchServices {
        let player = NowPlaying()
        let timer = FocusTimer()
        return NotchServices(
            settings: settings, player: player, lyrics: LyricsService(player: player, settings: settings),
            tray: FileTray(), volume: VolumeControl(), brightness: BrightnessControl(), system: SystemStatus(),
            actions: QuickActions(), calendar: CalendarService(), reminders: RemindersService(),
            weather: WeatherService(settings: settings), clipboard: ClipboardHistory(settings: settings),
            stats: SystemStats(), timer: timer, clock: ClockCenter(timer: timer, settings: settings),
            camera: CameraMirror(), downloads: DownloadWatcher(), focus: FocusWatcher(), privacy: PrivacyMonitor(),
            accessories: AccessoryBatteries(), audio: AudioDevices(), displays: ExternalDisplays(),
            keyboard: KeyboardBacklight(), notes: NotesStore(), shortcuts: ShortcutsService(),
            script: ScriptRunner(settings: settings), updates: UpdateChecker(), cat: CatBrain(settings: settings),
            tasks: TaskStore(settings: settings), pomodoro: PomodoroTimer(settings: settings),
            colors: ColorDropper(settings: settings))
    }
}

/// Owns the services, one notch per display, and the system-wide hooks (media keys, hot key,
/// Bluetooth, lock screen). Events are broadcast to every notch.
final class NotchHub {
    let settings = AppSettings.shared
    let services: NotchServices
    let mediaKeys = MediaKeyInterceptor()
    let bluetooth = BluetoothWatcher()
    let hotKey = GlobalHotKey()
    let colorHotKey = GlobalHotKey(id: 2)
    private(set) var controllers: [NotchController] = []
    private let lockScreen = LockScreenWidget()
    private var desktopCat: DesktopCat?

    var onOpenSettings: (() -> Void)?

    private var bag = Set<AnyCancellable>()
    private var countdownTimer: Timer?

    init() {
        services = .live(settings: settings)
        rebuildControllers()
        wire()
        lockScreen.attach(services: services)
        desktopCat = DesktopCat(brain: services.cat, settings: settings)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.services.brightness.refreshDisplay()
            self?.rebuildControllers()
        }
    }

    // MARK: Displays

    func rebuildControllers() {
        let screens: [NSScreen]
        switch settings.displayMode {
        case .notched:
            screens = [NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main].compactMap { $0 }
        case .main:
            screens = [NSScreen.screens.first].compactMap { $0 }
        case .all:
            screens = NSScreen.screens
        }
        controllers.forEach { $0.close() }
        controllers = screens.map { screen in
            let island = screen.safeAreaInsets.top == 0 && settings.islandOnPlainDisplays
            let controller = NotchController(geometry: .of(screen, island: island), services: services)
            controller.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
            return controller
        }
    }

    /// The notch on the screen under the mouse, else the first.
    var focusedController: NotchController? {
        let mouse = NSEvent.mouseLocation
        return controllers.first { $0.model.geometry.screenFrame.contains(mouse) } ?? controllers.first
    }

    func expand(tab: NotchTab? = nil, sticky: Bool = false, keyboard: Bool = false) {
        focusedController?.expand(tab: tab, sticky: sticky, keyboard: keyboard)
    }

    /// Folds any open notch away (it sits above the loupe) and shows the colour loupe.
    func pickColor() {
        controllers.filter { $0.model.isExpanded }.forEach { $0.collapse() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.services.colors.pick() }
    }

    func previewLockScreen(seconds: Double) {
        lockScreen.show(onDesktop: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.lockScreen.hide() }
    }

    func flashHUD(_ state: HUDState) { controllers.forEach { $0.model.flashHUD(state) } }

    func showActivity(_ state: ActivityState, for seconds: Double = 3) {
        controllers.forEach { $0.model.showActivity(state, for: seconds) }
    }

    // MARK: Wiring

    private func wire() {
        let s = services

        s.volume.onExternalChange = { [weak self] level, muted in
            self?.flashHUD(HUDState(kind: .volume(muted: muted), level: muted ? 0 : level))
        }
        // Brightness changes the user didn't ask for (auto-brightness, plugging in the charger) are
        // not shown: the brightness HUD appears only for the brightness keys, in handleMediaKey.

        s.system.onPowerEvent = { [weak self] pluggedIn, level in
            guard let self, self.settings.chargingActivity else { return }
            self.showActivity(ActivityState(symbol: pluggedIn ? "bolt.fill" : "battery.100",
                                            title: pluggedIn ? "Charging" : "On Battery", detail: "\(level)%",
                                            tint: pluggedIn ? .green : .white, progress: Double(level) / 100))
        }
        s.system.onLowBattery = { [weak self] level in
            guard let self, self.settings.chargingActivity else { return }
            self.showActivity(ActivityState(symbol: "battery.25", title: "Low Battery", detail: "\(level)% remaining",
                                            tint: .red, progress: Double(level) / 100), for: 4)
        }

        bluetooth.onChange = { [weak self] name, symbol, connected in
            guard let self, self.settings.bluetoothActivity else { return }
            self.showActivity(ActivityState(symbol: symbol, title: name, detail: connected ? "Connected" : "Disconnected",
                                            tint: connected ? .blue : .gray, progress: nil))
            // A moment later, once macOS knows the levels, follow up with the battery.
            guard connected, self.settings.accessoryBattery else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                s.accessories.refresh { found in
                    guard let match = found.first(where: { $0.name == name }), let lowest = match.lowest else { return }
                    self.showActivity(ActivityState(symbol: match.symbol, title: name, detail: match.summary,
                                                    tint: lowest <= 20 ? .red : .green,
                                                    progress: Double(lowest) / 100), for: 4)
                }
            }
        }
        settings.$bluetoothActivity.removeDuplicates()
            .sink { [weak self] on in on ? self?.bluetooth.start() : self?.bluetooth.stop() }
            .store(in: &bag)

        s.calendar.onUpcoming = { [weak self] event in
            guard let self, self.settings.calendarActivity else { return }
            let minutes = max(Int((event.start.timeIntervalSinceNow / 60).rounded()), 1)
            self.showActivity(ActivityState(symbol: "calendar", title: event.title, detail: "Starts in \(minutes) min",
                                            tint: event.color, progress: nil), for: 6)
        }
        s.reminders.onDue = { [weak self] item in
            guard let self, self.settings.reminderActivity else { return }
            NSSound(named: "Glass")?.play()
            self.showActivity(ActivityState(symbol: "checklist", title: item.title,
                                            detail: item.listName.isEmpty ? "Reminder" : "Reminder · \(item.listName)",
                                            tint: item.color, progress: nil), for: 8)
        }
        s.focus.onChange = { [weak self] name in
            guard let self, self.settings.focusActivity else { return }
            self.showActivity(ActivityState(symbol: FocusWatcher.symbol(for: name), title: name ?? "Focus",
                                            detail: name == nil ? "Off" : "On",
                                            tint: name == nil ? .gray : .indigo, progress: nil))
        }
        s.downloads.onFinished = { [weak self] url in
            guard let self else { return }
            if self.settings.downloadsToTray { s.tray.add([url]) }
            guard self.settings.downloadActivity else { return }
            self.showActivity(ActivityState(symbol: "arrow.down.circle.fill", title: url.lastPathComponent,
                                            detail: self.settings.downloadsToTray ? "Downloaded · added to the tray" : "Downloaded",
                                            tint: .blue, progress: 1), for: 4)
        }

        s.cat.onAlert = { [weak self] alert in
            guard let self, self.settings.catEnabled else { return }
            self.showActivity(ActivityState(symbol: alert.symbol, title: alert.title, detail: alert.detail,
                                            tint: alert.tint, progress: nil), for: 5)
        }

        s.tasks.isFocusing = { s.pomodoro.isRunning && s.pomodoro.phase == .work }
        s.pomodoro.onPhaseChange = { [weak self] ended, next in
            guard let self else { return }
            NSSound(named: NSSound.Name(self.settings.pomodoroSound))?.play()
            let minutes = Int(s.pomodoro.length(of: next) / 60)
            let title = ended == .work ? (next == .longBreak ? "Long break" : "Break time") : "Back to work"
            let detail = ended == .work
                ? "Round \(s.pomodoro.round) done · \(minutes) min break"
                : "Round \(s.pomodoro.round) of \(s.pomodoro.rounds) · \(minutes) min"
            self.showActivity(ActivityState(symbol: next.symbol, title: title,
                                            detail: self.settings.pomodoroAutoStart ? detail : detail + " · press Start",
                                            tint: next.isBreak ? .green : Color(red: 1, green: 0.42, blue: 0.38),
                                            progress: nil), for: 5)
        }
        s.colors.onPicked = { [weak self] hex, saved in
            guard let self else { return }
            let parts = [self.settings.colorCopyOnPick ? "Copied" : nil, saved ? "Saved to Colours" : nil,
                         ColorDropper.formats(hex).rgb].compactMap { $0 }
            self.showActivity(ActivityState(symbol: "eyedropper", title: hex, detail: parts.joined(separator: " · "),
                                            tint: Color(hex: hex) ?? .white, progress: nil, swatch: hex), for: 4)
        }
        colorHotKey.action = { [weak self] in self?.pickColor() }
        settings.$colorHotKey.removeDuplicates()
            .sink { [weak self] choice in self?.colorHotKey.register(choice) }
            .store(in: &bag)

        mediaKeys.handler = { [weak self] key, fine in self?.handleMediaKey(key, fineStep: fine) ?? false }
        settings.$replaceSystemHUD.removeDuplicates()
            .sink { [weak self] on in on ? self?.mediaKeys.start(prompt: true) : self?.mediaKeys.stop() }
            .store(in: &bag)

        hotKey.action = { [weak self] in
            guard let self else { return }
            if let open = self.controllers.first(where: { $0.model.isExpanded }) {
                open.collapse()
            } else {
                self.expand(keyboard: true)
            }
        }
        settings.$hotKey.removeDuplicates()
            .sink { [weak self] choice in self?.hotKey.register(choice) }
            .store(in: &bag)

        settings.$displayMode.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildControllers() } }
            .store(in: &bag)
        settings.$islandOnPlainDisplays.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildControllers() } }
            .store(in: &bag)
        settings.$clipboardPersist.dropFirst().removeDuplicates()
            .sink { _ in DispatchQueue.main.async { s.clipboard.settingsChanged() } }
            .store(in: &bag)

        // A meeting within ten minutes counts down in the closed notch.
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.updateCountdown() }
        s.calendar.$events.sink { [weak self] _ in DispatchQueue.main.async { self?.updateCountdown() } }.store(in: &bag)
    }

    private func updateCountdown() {
        let now = Date()
        let next = services.calendar.events.first { event in
            !event.isAllDay && event.start > now && event.start.timeIntervalSince(now) <= 10 * 60
        }
        controllers.forEach { if $0.model.countdown != next { $0.model.countdown = next } }
    }

    // MARK: Media keys

    /// Does what the key would have done, then shows the notch HUD instead of the system one.
    private func handleMediaKey(_ key: MediaKeyInterceptor.Key, fineStep: Bool) -> Bool {
        let steps = Double(settings.volumeSteps.rawValue) * (fineStep ? 4 : 1)
        let step = 1 / steps
        func stepped(_ value: Double, by delta: Double) -> Double {
            min(max(((value / step).rounded() + delta) * step, 0), 1)
        }
        let volume = services.volume
        let brightness = services.brightness
        switch key {
        case .volumeUp, .volumeDown, .mute:
            guard volume.canSetVolume else { return false }
            switch key {
            case .volumeUp: volume.set(stepped(volume.isMuted ? 0 : volume.level, by: 1))
            case .volumeDown: volume.set(stepped(volume.level, by: -1))
            default: volume.setMuted(!volume.isMuted)
            }
            if key != .mute { playVolumeFeedback() }
            flashHUD(HUDState(kind: .volume(muted: volume.isMuted), level: volume.isMuted ? 0 : volume.level))
        case .brightnessUp, .brightnessDown:
            let delta: Double = key == .brightnessUp ? 1 : -1
            if brightness.isAvailable {
                brightness.set(stepped(brightness.level, by: delta))
                flashHUD(HUDState(kind: .brightness, level: brightness.level))
            } else if let first = services.displays.displays.first {
                // Lid closed: the keys drive the external monitor over DDC.
                services.displays.step(by: delta * step)
                flashHUD(HUDState(kind: .externalBrightness, level: min(max(first.brightness + delta * step, 0), 1)))
            } else {
                return false
            }
        case .keyboardUp, .keyboardDown, .keyboardToggle:
            let keyboard = services.keyboard
            guard keyboard.isAvailable else { return false }
            switch key {
            case .keyboardUp: keyboard.set(stepped(keyboard.level, by: 1))
            case .keyboardDown: keyboard.set(stepped(keyboard.level, by: -1))
            default: keyboard.toggle()
            }
            flashHUD(HUDState(kind: .keyboard, level: keyboard.level))
        }
        return true
    }

    private lazy var feedbackSound = NSSound(
        contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff",
        byReference: true)

    /// The "pop" macOS plays on a volume change, when "Play feedback when volume is changed" is on.
    private func playVolumeFeedback() {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let enabled = CFPreferencesCopyAppValue("com.apple.sound.beep.feedback" as CFString,
                                                kCFPreferencesAnyApplication) as? Int ?? 0
        guard enabled == 1, !services.volume.isMuted, let sound = feedbackSound else { return }
        sound.stop()
        sound.play()
    }
}

/// One notch: its panel on one screen, and when it opens and closes.
final class NotchController {
    let model: NotchModel
    let services: NotchServices
    var settings: AppSettings { services.settings }

    var onOpenSettings: (() -> Void)?

    static let windowSize = CGSize(width: 980, height: 460)

    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()
    private var collapseWork: DispatchWorkItem?
    private var dragPoll: Timer?
    private var dragChangeCount = 0
    private var externalDrag = false
    private var pressBeganInside = false
    private var stickyUntil = Date.distantPast
    private var expandedWatch: Timer?
    private var swipeAccumulator: CGFloat = 0
    private var swipeLocked = false
    private var dwellTimer: Timer?
    private var dwellStart = Date()
    private var dwellSamples: [(time: Date, point: CGPoint)] = []
    /// Set when the notch closes with the pointer still on it: it has to leave before hover
    /// can open the notch again, so it never flickers open and shut.
    private var awaitingExit = false
    /// True once you've used the open panel (clicked, scrolled, typed, or lingered in it).
    /// Until then leaving it closes it at once, so an accidental hover costs nothing.
    private var engaged = false
    private var openedAt = Date.distantPast
    /// True while a menu (a picker's pop-up, a context menu) is open: the pointer is on the menu,
    /// outside the panel, and the panel must not fold away under it.
    private var menuTracking = false
    private var menuObservers: [NSObjectProtocol] = []

    /// Shared by every display's panel.
    private static let fullScreenSpace = FloatingSpace(level: .aboveFullScreen)

    init(geometry: NotchGeometry, services: NotchServices) {
        self.services = services
        model = NotchModel(geometry: geometry, settings: services.settings)
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let hosting = FirstMouseHostingView(rootView: NotchRootView(model: model, services: services,
                                                                    settings: services.settings, player: services.player))
        hosting.sizingOptions = []
        panel.contentView = hosting
        place()
        panel.orderFrontRegardless()
        // Over full-screen apps too: `.fullScreenAuxiliary` alone stopped being honoured for an
        // agent's panel, so the panel lives in a space that floats above every full-screen space
        // but under the screen lock.
        Self.fullScreenSpace.delegate(panel)

        model.onRequestCollapse = { [weak self] in self?.collapse() }
        model.onOpenSettings = { [weak self] in
            self?.collapse()
            self?.onOpenSettings?()
        }
        model.onRequestKeyboard = { [weak self] in self?.panel.makeKey() }
        model.onPickColor = { [weak self] in
            guard let self else { return }
            self.collapse()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.services.colors.pick { [weak self] in
                    self?.model.deskSection = .colors
                    self?.expand(tab: .desk, sticky: true)
                }
            }
        }
        model.onReopen = { [weak self] tab in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.expand(tab: tab, sticky: true) }
        }

        wireState()
        installMonitors()
        let center = NotificationCenter.default
        menuObservers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil,
                                                queue: .main) { [weak self] _ in
            guard let self, self.model.isExpanded else { return }
            self.menuTracking = true
            self.engaged = true
            self.cancelPending()
        })
        menuObservers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil,
                                                queue: .main) { [weak self] _ in
            // A moment's grace for the pointer to come back from where the menu was.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.menuTracking = false }
        })
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers = []
        expandedWatch?.invalidate()
        dragPoll?.invalidate()
        panel.orderOut(nil)
    }

    private func wireState() {
        let s = services
        s.player.$track.map { $0?.isPlaying ?? false }.removeDuplicates()
            .sink { [weak self] in self?.model.isPlaying = $0 }.store(in: &bag)
        s.timer.$endDate.combineLatest(s.timer.$pausedRemaining).map { $0 != nil || $1 != nil }.removeDuplicates()
            .sink { [weak self] in self?.model.timerActive = $0 }.store(in: &bag)
        s.clock.$stopwatchStart.combineLatest(s.clock.$stopwatchAccumulated).map { $0 != nil || $1 > 0 }.removeDuplicates()
            .sink { [weak self] in self?.model.stopwatchActive = $0 }.store(in: &bag)
        s.pomodoro.$endDate.combineLatest(s.pomodoro.$pausedRemaining).map { $0 != nil || $1 != nil }.removeDuplicates()
            .sink { [weak self] in self?.model.pomodoroActive = $0 }.store(in: &bag)
        s.tasks.$overdue.removeDuplicates()
            .sink { [weak self] in self?.model.overdueTask = $0 }.store(in: &bag)
        s.tasks.$nudge.removeDuplicates()
            .sink { [weak self] nudge in
                guard let self else { return }
                self.model.nudge = nudge
                // The card has buttons, so it takes clicks while it is up.
                self.panel.ignoresMouseEvents = self.model.ringing == nil && nudge == nil && !self.model.isExpanded
            }
            .store(in: &bag)
        s.downloads.$active.map { !$0.isEmpty }.removeDuplicates()
            .sink { [weak self] in self?.model.downloading = $0 }.store(in: &bag)
        s.privacy.$cameraInUse.combineLatest(s.privacy.$microphoneInUse, s.privacy.$screenRecording, s.audio.$micMuted)
            .map { PrivacyState(camera: $0, microphone: $1, screen: $2, micMuted: $3) }
            .removeDuplicates()
            .sink { [weak self] in self?.model.privacy = $0 }.store(in: &bag)
        s.clock.$ringing.removeDuplicates()
            .sink { [weak self] ringing in
                guard let self else { return }
                if ringing != nil, self.model.isExpanded { self.collapse() }
                self.model.ringing = ringing
                // The ringing card has buttons, so it takes clicks while it is up.
                self.panel.ignoresMouseEvents = ringing == nil && self.model.nudge == nil && !self.model.isExpanded
            }
            .store(in: &bag)
        // The model's shape depends on settings (HUD style, corner radius…): redraw when they move.
        settings.objectWillChange.sink { [weak self] in self?.model.objectWillChange.send() }.store(in: &bag)
    }

    // MARK: Opening and closing

    func expand(tab: NotchTab? = nil, sticky: Bool = false, keyboard: Bool = false) {
        guard model.ringing == nil else { return }
        cancelPending()
        if let tab {
            model.tab = tab
        } else if !model.isExpanded, let opening = NotchTab(rawValue: settings.openingTab), settings.isEnabled(opening) {
            model.tab = opening
        }
        if sticky || keyboard { stickyUntil = Date().addingTimeInterval(keyboard ? 3600 : 4) }
        let wasExpanded = model.isExpanded
        if !wasExpanded {
            openedAt = Date()
            engaged = sticky || keyboard || tab != nil
        }
        panel.ignoresMouseEvents = false
        model.setExpanded(true)
        if keyboard { panel.makeKey() }
        services.actions.refresh()
        services.player.refresh()
        services.calendar.reload()
        services.reminders.reload()
        services.keyboard.refresh()
        if !wasExpanded, settings.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        log.info("expanded on \(self.model.tab.rawValue, privacy: .public)")
        // Belt and braces: if mouse events go missing, still fold away once the pointer has left.
        expandedWatch?.invalidate()
        // Checks the pointer often enough that leaving the panel closes it straight away, even
        // when global mouse events are slow to arrive.
        let watch = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.mouseMoved() }
        RunLoop.main.add(watch, forMode: .common)
        expandedWatch = watch
        stopDwell()
    }

    func collapse() {
        cancelPending()
        stopDwell()
        stickyUntil = .distantPast
        engaged = false
        awaitingExit = triggerZone().contains(NSEvent.mouseLocation)
        model.dropTargeted = false
        model.setExpanded(false)
        panel.ignoresMouseEvents = model.ringing == nil && model.nudge == nil
        if panel.isKeyWindow {
            // Hand the keyboard back to whatever app was in front.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        expandedWatch?.invalidate()
        expandedWatch = nil
        log.info("collapsed")
    }

    private func cancelPending() {
        collapseWork?.cancel()
        collapseWork = nil
    }

    private func place() {
        let screen = model.geometry.screenFrame
        let size = Self.windowSize
        panel.setFrame(CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    /// True while the user is typing in one of the panel's text fields.
    private var isEditingText: Bool {
        panel.isKeyWindow && panel.firstResponder is NSTextView
    }

    // MARK: Mouse and keyboard

    private func installMonitors() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in self?.mouseMoved() }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.mouseMoved()
            return event
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in self?.globalMouseDown() }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            if event.window === self?.panel {
                self?.pressBeganInside = true
                self?.engaged = true
            }
            return event
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard event.window === self?.panel else { return event }
            self?.engaged = true
            return self?.handleSwipe(event) == true ? nil : event
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            self.engaged = true
            return self.handleKey(event) ? nil : event
        }) {
            monitors.append(m)
        }
    }

    /// Esc closes; ← → switch tabs; ⌘1…9 jump to a tab (not while typing).
    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            collapse()
            return true
        }
        guard !isEditingText else { return false }
        switch event.keyCode {
        case 123: model.selectAdjacentTab(-1); return true
        case 124: model.selectAdjacentTab(1); return true
        default:
            if event.modifierFlags.contains(.command), let digit = Int(event.charactersIgnoringModifiers ?? ""),
               (1...9).contains(digit), digit <= settings.visibleTabs.count {
                model.tab = settings.visibleTabs[digit - 1]
                return true
            }
            return false
        }
    }

    /// Two-finger horizontal swipe on the open panel moves between tabs.
    private func handleSwipe(_ event: NSEvent) -> Bool {
        guard model.isExpanded, settings.swipeBetweenTabs, event.hasPreciseScrollingDeltas else { return false }
        // These tabs scroll sideways themselves.
        if (model.tab == .tray && !services.tray.items.isEmpty) || (model.tab == .clipboard && !services.clipboard.items.isEmpty)
            || model.tab == .desk {
            return false
        }
        if event.phase == .began { swipeAccumulator = 0; swipeLocked = false }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
        if !swipeLocked {
            swipeAccumulator += event.scrollingDeltaX
            if abs(swipeAccumulator) > 50 {
                model.selectAdjacentTab(swipeAccumulator < 0 ? 1 : -1)
                swipeLocked = true
                if settings.haptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            }
        }
        if event.phase == .ended || event.phase == .cancelled { swipeAccumulator = 0; swipeLocked = false }
        return true
    }

    private func globalMouseDown() {
        pressBeganInside = false
        externalDrag = false
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        startDragPolling()
        let point = NSEvent.mouseLocation
        if model.isExpanded, !collapseZone.contains(point) {
            collapse()
        } else if !model.isExpanded, settings.openTrigger == .click, model.ringing == nil,
                  model.screenRect.insetBy(dx: -4, dy: -4).contains(point) {
            expand()
        }
    }

    /// Global mouse events go quiet during another app's drag session, so while the button is held
    /// we watch the drag pasteboard: when it changes, someone is dragging content and the notch
    /// should open as a drop target.
    private func startDragPolling() {
        dragPoll?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if NSEvent.pressedMouseButtons & 1 == 0 {
                timer.invalidate()
                self.dragPoll = nil
                self.externalDrag = false
                return
            }
            if !self.externalDrag, NSPasteboard(name: .drag).changeCount != self.dragChangeCount {
                self.externalDrag = true
            }
            if self.externalDrag { self.mouseMoved() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragPoll = timer
    }

    /// What opens the notch on hover: the notch itself and a few points either side, not the
    /// album-art wings. Once the pointer is on it the zone grows a little (hysteresis), so a hand
    /// resting on the edge doesn't flicker in and out and restart the wait. While a file is
    /// dragged, a generous area around it.
    private func triggerZone() -> CGRect {
        let geometry = model.geometry
        let frame = geometry.screenFrame
        if externalDrag { return model.screenRect.insetBy(dx: -60, dy: -40) }
        let grow: CGFloat = model.hovering || dwellTimer != nil ? 8 : 0
        let width = geometry.notchSize.width + 2 * (Self.sideMargin + grow)
        let height = geometry.notchSize.height + geometry.islandGap + 2 + grow * 0.75
        return CGRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height + 1)
    }

    private static let sideMargin: CGFloat = 8

    /// The open panel plus a small grace margin once you're using it, so overshooting an edge
    /// doesn't close it. Before that, just the panel itself.
    private var collapseZone: CGRect {
        guard engaged else { return model.screenRect.insetBy(dx: -8, dy: 0).insetBy(dx: 0, dy: -6) }
        let rect = model.screenRect.insetBy(dx: -14, dy: 0)
        return CGRect(x: rect.minX, y: rect.minY - 24, width: rect.width, height: rect.height + 24)
    }

    /// The pointer pressed against the top of the screen above the open panel: it's still "in"
    /// the notch (the edge stops it going any higher), so that never closes it.
    private func atTopEdge(_ point: CGPoint) -> Bool {
        let rect = model.screenRect
        return point.y >= model.geometry.screenFrame.maxY - 2 && point.x >= rect.minX - 14 && point.x <= rect.maxX + 14
    }

    private func mouseMoved() {
        let point = NSEvent.mouseLocation
        if model.ringing != nil || model.nudge != nil { return }
        if model.isExpanded {
            // Lingering in the panel counts as using it.
            if !engaged, model.screenRect.contains(point), Date().timeIntervalSince(openedAt) > 0.7 { engaged = true }
            if collapseZone.contains(point) || atTopEdge(point) || isEditingText || menuTracking {
                // A keyboard-opened panel stays put; a menu-opened one switches to hover rules.
                if stickyUntil < Date().addingTimeInterval(60) { stickyUntil = .distantPast }
                collapseWork?.cancel()
                collapseWork = nil
            } else if Date() >= stickyUntil, collapseWork == nil {
                scheduleCollapse()
            }
            return
        }
        let inZone = triggerZone().contains(point)
        if inZone != model.hovering { model.hovering = inZone }
        // After it closes, the pointer must leave before hovering can open it again.
        if awaitingExit {
            if !inZone { awaitingExit = false }
            return
        }
        // In click mode only a drag opens the notch by itself.
        guard settings.openTrigger == .hover || externalDrag else { return }
        if inZone {
            if externalDrag {
                expand(tab: .tray)
            } else {
                startDwell()
            }
        } else {
            stopDwell()
        }
    }

    // MARK: Hover intent

    /// Samples the pointer 30 times a second while it's over the notch. It opens once the pointer
    /// has been there for the delay and has barely moved lately: a pointer that's crossing, or
    /// sliding along the top edge, never counts, however slowly it goes.
    private func startDwell() {
        guard dwellTimer == nil else { return }
        dwellStart = Date()
        dwellSamples = [(Date(), NSEvent.mouseLocation)]
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.dwellTick() }
        RunLoop.main.add(timer, forMode: .common)
        dwellTimer = timer
    }

    private func stopDwell() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        dwellSamples = []
    }

    private func dwellTick() {
        let now = Date()
        let point = NSEvent.mouseLocation
        guard !model.isExpanded, triggerZone().contains(point), model.ringing == nil, model.nudge == nil else {
            stopDwell()
            return
        }
        dwellSamples.append((now, point))
        dwellSamples.removeAll { now.timeIntervalSince($0.time) > 0.3 }
        guard HoverIntent.isResting(samples: dwellSamples, since: dwellStart, now: now,
                                    delay: settings.hoverDelay, sensitivity: settings.hoverSensitivity,
                                    topEdge: model.geometry.screenFrame.maxY) else { return }
        stopDwell()
        expand()
    }

    private func scheduleCollapse() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWork = nil
            // Don't fold away while a file is being dragged out of the tray, or while typing.
            if (self.pressBeganInside && NSEvent.pressedMouseButtons & 1 != 0) || self.isEditingText || self.menuTracking {
                self.scheduleCollapse()
                return
            }
            let point = NSEvent.mouseLocation
            if !self.collapseZone.contains(point), !self.atTopEdge(point) { self.collapse() }
        }
        collapseWork = work
        // Soon after an accidental hover, but not so soon that overshooting an edge on the way
        // in shuts it; more grace once you've used it.
        DispatchQueue.main.asyncAfter(deadline: .now() + (engaged ? 0.3 : 0.15), execute: work)
    }
}

/// Decides whether a pointer over the notch means it (open) or is just passing (don't). Like
/// the other notch apps it waits out the hover delay; then it opens once the pointer has slowed
/// down, rather than demanding it stop dead. A pointer pushed up against the top edge over the
/// notch and stopped there counts too; one sliding along the edge, crossing the menu bar, doesn't.
enum HoverIntent {
    static func isResting(samples: [(time: Date, point: CGPoint)], since start: Date, now: Date,
                          delay: Double, sensitivity: HoverSensitivity, topEdge: CGFloat? = nil) -> Bool {
        guard now.timeIntervalSince(start) >= max(delay, 0.08) else { return false }
        // Its speed over the last moment.
        let recent = samples.filter { now.timeIntervalSince($0.time) <= sensitivity.stillWindow }
        guard let first = recent.first, let last = recent.last else { return false }
        let span = max(last.time.timeIntervalSince(first.time), 1 / 30)
        let speed = hypot(last.point.x - first.point.x, last.point.y - first.point.y) / span
        // Small jitter (a resting hand) never counts as moving.
        let xs = recent.map(\.point.x), ys = recent.map(\.point.y)
        let drift = hypot((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
        if drift <= sensitivity.stillTolerance { return true }
        // Sliding along the very top edge is how the pointer travels across the menu bar, so
        // moving there has to be slower still to count.
        let pinned = topEdge.map { edge in recent.allSatisfy { $0.point.y >= edge - 1.5 } } ?? false
        return speed <= sensitivity.maxSpeed * (pinned ? 0.6 : 1)
    }

    /// `--test-hover`: plays pointer paths at 30 samples a second through the rule and prints
    /// what would happen, for each sensitivity.
    static func selfTest() {
        let notchWidth: CGFloat = 179 + 12
        func path(_ seconds: Double, _ at: (Double) -> CGPoint) -> [(Double, CGPoint)] {
            stride(from: 0.0, through: seconds, by: 1 / 30).map { ($0, at($0)) }
        }
        // Whether each path should open the notch. `y` is the distance down from the top of the
        // screen (0 is pressed against the edge).
        let scenarios: [(String, (HoverSensitivity) -> Bool, [(Double, CGPoint)])] = [
            ("rests on the notch", { _ in true }, path(1, { _ in CGPoint(x: 90, y: 10) })),
            ("hand tremor (±2 pt) while resting", { _ in true }, path(1, { t in CGPoint(x: 90 + 2 * sin(t * 40), y: 10 + 2 * cos(t * 33)) })),
            ("flicked up to the edge and stopped", { _ in true }, path(1, { t in CGPoint(x: 95, y: max(0, 30 - t * 400)) })),
            ("crosses the notch at 300 pt/s", { _ in false }, path(notchWidth / 300, { t in CGPoint(x: t * 300, y: 10) })),
            ("crosses the menu bar along the top edge at 120 pt/s", { $0 == .quick }, path(notchWidth / 120, { t in CGPoint(x: t * 120, y: 0) })),
            ("drifts on it at 60 pt/s", { $0 != .deliberate }, path(notchWidth / 60, { t in CGPoint(x: t * 60, y: 8) })),
            ("touches it for 0.1 s and leaves", { _ in false }, path(0.1, { _ in CGPoint(x: 90, y: 10) })),
            ("slows down and stops on it", { _ in true }, path(1, { t in CGPoint(x: t < 0.4 ? t * 200 : 80, y: 10) })),
            ("comes up from below and slows on it", { _ in true }, path(1, { t in CGPoint(x: 90, y: max(12, 60 - 300 * t + 150 * t * t)) })),
        ]
        for sensitivity in HoverSensitivity.allCases {
            print("\n\(sensitivity.title) (delay \(Int(sensitivity.delay * 1000)) ms):")
            for (name, expected, points) in scenarios {
                let start = Date()
                var samples: [(time: Date, point: CGPoint)] = []
                var opened: Double?
                for (t, point) in points {
                    let now = start.addingTimeInterval(t)
                    // Into screen coordinates: y up, the top edge at 1000.
                    samples.append((now, CGPoint(x: point.x, y: 1000 - point.y)))
                    samples.removeAll { now.timeIntervalSince($0.time) > 0.3 }
                    if isResting(samples: samples, since: start, now: now, delay: sensitivity.delay, sensitivity: sensitivity,
                                 topEdge: 1000) {
                        opened = t
                        break
                    }
                }
                let verdict = opened.map { "opens at \(Int($0 * 1000)) ms" } ?? "stays closed"
                print("  \((opened != nil) == expected(sensitivity) ? "ok  " : "FAIL") \(name): \(verdict)")
            }
        }
    }
}

/// The full-screen record player on the lock screen. It is up whenever the Mac is locked and a
/// song is playing or paused, and gets out of the way when nothing is, or when it's a video.
final class LockScreenWidget {
    private var window: NSPanel?
    private var presenter: FloatingSpace?
    private var observers: [NSObjectProtocol] = []
    private var services: NotchServices?
    private var bag = Set<AnyCancellable>()
    private var locked = false

    func attach(services: NotchServices) {
        self.services = services
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil,
                                            queue: .main) { [weak self] _ in
            self?.locked = true
            services.player.refresh()
            // The player answers a moment later; decide then.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.update() }
        })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil,
                                            queue: .main) { [weak self] _ in
            self?.locked = false
            self?.hide()
        })
        // While locked: a song starting brings it up, the player closing (or a video taking
        // over) takes it down.
        services.player.$track.map { $0?.isMusic == true }.removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &bag)
    }

    private func update() {
        guard locked, let services else { return }
        // The record player is for songs: a film or a video in a browser never brings it up.
        if services.settings.lockScreenWidget, services.player.track?.isMusic == true { show() } else { hide() }
    }

    /// `onDesktop` shows it over the desktop instead, for a few seconds (the preview menu item).
    func show(onDesktop: Bool = false) {
        guard let services, services.settings.lockScreenWidget || onDesktop, let screen = NSScreen.main else { return }
        if window == nil {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            // Opaque: nothing of the wallpaper or the system clock shows through.
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            let hosting = NSHostingView(rootView: LockScreenView(player: services.player, lyrics: services.lyrics,
                                                                system: services.system, weather: services.weather,
                                                                settings: services.settings)
                .frame(maxWidth: .infinity, maxHeight: .infinity))
            hosting.sizingOptions = []
            panel.contentView = hosting
            window = panel
        }
        guard let window else { return }
        // The whole display, edge to edge. It never takes the mouse or the keyboard, so typing the
        // password and pressing Return still unlocks the Mac underneath it.
        window.setFrame(screen.frame, display: true)
        let wasVisible = window.isVisible
        if !wasVisible { window.alphaValue = 0 }
        window.orderFrontRegardless()
        if !wasVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                window.animator().alphaValue = 1
            }
        }
        guard !onDesktop else { return }
        if presenter == nil { presenter = FloatingSpace(level: .aboveScreenLock) }
        presenter?.delegate(window)
    }

    func hide() {
        window?.orderOut(nil)
    }
}
