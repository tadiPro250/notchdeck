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
            script: ScriptRunner(settings: settings), updates: UpdateChecker(), cat: CatBrain(settings: settings))
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

        s.cat.onHungry = { [weak self] name in
            guard let self, self.settings.catEnabled else { return }
            self.showActivity(ActivityState(symbol: "cat.fill", title: "\(name) is hungry",
                                            detail: "Hover the cat and press Feed", tint: .orange, progress: nil), for: 5)
        }

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

    static let windowSize = CGSize(width: 880, height: 400)

    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var dragPoll: Timer?
    private var dragChangeCount = 0
    private var externalDrag = false
    private var pressBeganInside = false
    private var stickyUntil = Date.distantPast
    private var expandedWatch: Timer?
    private var swipeAccumulator: CGFloat = 0
    private var swipeLocked = false

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

        model.onRequestCollapse = { [weak self] in self?.collapse() }
        model.onOpenSettings = { [weak self] in
            self?.collapse()
            self?.onOpenSettings?()
        }
        model.onRequestKeyboard = { [weak self] in self?.panel.makeKey() }
        model.onReopen = { [weak self] tab in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.expand(tab: tab, sticky: true) }
        }

        wireState()
        installMonitors()
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
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
                self.panel.ignoresMouseEvents = ringing == nil && !self.model.isExpanded
            }
            .store(in: &bag)
        // The model's shape depends on settings (HUD style, corner radius…): redraw when they move.
        settings.objectWillChange.sink { [weak self] in self?.model.objectWillChange.send() }.store(in: &bag)
    }

    // MARK: Opening and closing

    func expand(tab: NotchTab? = nil, sticky: Bool = false, keyboard: Bool = false) {
        guard model.ringing == nil else { return }
        cancelPending()
        if let tab { model.tab = tab }
        if sticky || keyboard { stickyUntil = Date().addingTimeInterval(keyboard ? 3600 : 4) }
        let wasExpanded = model.isExpanded
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
        expandedWatch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.mouseMoved() }
    }

    func collapse() {
        cancelPending()
        stickyUntil = .distantPast
        model.dropTargeted = false
        model.setExpanded(false)
        panel.ignoresMouseEvents = model.ringing == nil
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
        expandWork?.cancel()
        expandWork = nil
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
            if event.window === self?.panel { self?.pressBeganInside = true }
            return event
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard event.window === self?.panel else { return event }
            return self?.handleSwipe(event) == true ? nil : event
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.window === self.panel else { return event }
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

    private func hotZone() -> CGRect {
        externalDrag ? model.screenRect.insetBy(dx: -60, dy: -40) : model.screenRect.insetBy(dx: -2, dy: -2)
    }

    /// The open panel plus a grace margin, wider at the bottom, so overshooting doesn't close it.
    private var collapseZone: CGRect {
        let rect = model.screenRect.insetBy(dx: -18, dy: 0)
        return CGRect(x: rect.minX, y: rect.minY - 30, width: rect.width, height: rect.height + 30)
    }

    private func mouseMoved() {
        let point = NSEvent.mouseLocation
        if model.ringing != nil { return }
        if model.isExpanded {
            if collapseZone.contains(point) || isEditingText {
                // A keyboard-opened panel stays put; a menu-opened one switches to hover rules.
                if stickyUntil < Date().addingTimeInterval(60) { stickyUntil = .distantPast }
                collapseWork?.cancel()
                collapseWork = nil
            } else if Date() >= stickyUntil, collapseWork == nil {
                scheduleCollapse()
            }
            return
        }
        let over = model.screenRect.insetBy(dx: -2, dy: -2).contains(point)
        if over != model.hovering { model.hovering = over }
        // In click mode only a drag opens the notch by itself.
        guard settings.openTrigger == .hover || externalDrag else { return }
        if hotZone().contains(point) {
            guard expandWork == nil else { return }
            let forDrop = externalDrag
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.expandWork = nil
                if self.hotZone().contains(NSEvent.mouseLocation) { self.expand(tab: forDrop ? .tray : nil) }
            }
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (forDrop ? 0 : settings.hoverDelay), execute: work)
        } else {
            expandWork?.cancel()
            expandWork = nil
        }
    }

    private func scheduleCollapse() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWork = nil
            // Don't fold away while a file is being dragged out of the tray, or while typing.
            if (self.pressBeganInside && NSEvent.pressedMouseButtons & 1 != 0) || self.isEditingText {
                self.scheduleCollapse()
                return
            }
            if !self.collapseZone.contains(NSEvent.mouseLocation) { self.collapse() }
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}

/// The turntable and lyrics on the lock screen.
final class LockScreenWidget {
    private var window: NSPanel?
    private var presenter: LockScreenPresenter?
    private var observers: [NSObjectProtocol] = []
    private var services: NotchServices?

    func attach(services: NotchServices) {
        self.services = services
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil,
                                            queue: .main) { [weak self] _ in self?.show() })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil,
                                            queue: .main) { [weak self] _ in self?.hide() })
    }

    /// `onDesktop` shows it over the desktop instead, for a few seconds (the `--preview-lockscreen` flag).
    func show(onDesktop: Bool = false) {
        guard let services, services.settings.lockScreenWidget || onDesktop, let screen = NSScreen.main else { return }
        if window == nil {
            let size = LockScreenView.size
            let panel = NSPanel(contentRect: CGRect(origin: .zero, size: CGSize(width: size.width + 80, height: size.height + 80)),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
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
        services.player.refresh()
        // Between the lock screen's clock and the password field.
        let frame = screen.frame
        window.setFrameOrigin(CGPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2 - 40))
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            window.animator().alphaValue = 1
        }
        guard !onDesktop else { return }
        if presenter == nil { presenter = LockScreenPresenter() }
        presenter?.delegate(window)
    }

    func hide() {
        window?.orderOut(nil)
    }
}
