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
    let tray: FileTray
    let volume: VolumeControl
    let brightness: BrightnessControl
    let system: SystemStatus
    let actions: QuickActions
    let calendar: CalendarService
    let weather: WeatherService
    let clipboard: ClipboardHistory
    let stats: SystemStats
    let timer: FocusTimer
    let camera: CameraMirror

    static func live(settings: AppSettings) -> NotchServices {
        NotchServices(settings: settings, player: NowPlaying(), tray: FileTray(), volume: VolumeControl(),
                      brightness: BrightnessControl(), system: SystemStatus(), actions: QuickActions(),
                      calendar: CalendarService(), weather: WeatherService(settings: settings),
                      clipboard: ClipboardHistory(settings: settings), stats: SystemStats(),
                      timer: FocusTimer(), camera: CameraMirror())
    }
}

/// Owns the panel that sits over the notch, and decides when it opens and closes.
final class NotchController {
    static let windowSize = CGSize(width: 800, height: 300)

    let settings = AppSettings.shared
    let model: NotchModel
    let services: NotchServices
    let mediaKeys = MediaKeyInterceptor()
    let bluetooth = BluetoothWatcher()

    var onOpenSettings: (() -> Void)?

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

    init() {
        model = NotchModel(geometry: .current(), settings: settings)
        services = .live(settings: settings)
        panel = NotchPanel(contentRect: .zero,
                           styleMask: [.borderless, .nonactivatingPanel],
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
                                                                    settings: settings, player: services.player))
        hosting.sizingOptions = []
        panel.contentView = hosting
        place()
        panel.orderFrontRegardless()

        model.onRequestCollapse = { [weak self] in self?.collapse() }
        model.onOpenSettings = { [weak self] in
            self?.collapse()
            self?.onOpenSettings?()
        }

        wireServices()
        installMonitors()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.model.geometry = .current()
            self.services.brightness.refreshDisplay()
            self.place()
        }
    }

    private func wireServices() {
        let s = services

        s.player.$track
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            .sink { [weak self] playing in self?.model.isPlaying = playing }
            .store(in: &bag)

        s.timer.$endDate.combineLatest(s.timer.$pausedRemaining)
            .map { $0 != nil || $1 != nil }
            .removeDuplicates()
            .sink { [weak self] active in self?.model.timerActive = active }
            .store(in: &bag)

        // The model's shape depends on settings (HUD style, corner radius…): redraw when they move.
        settings.objectWillChange
            .sink { [weak self] in self?.model.objectWillChange.send() }
            .store(in: &bag)

        s.volume.onExternalChange = { [weak self] level, muted in
            self?.model.flashHUD(HUDState(kind: .volume(muted: muted), level: muted ? 0 : level))
        }
        s.brightness.onExternalChange = { [weak self] level in
            self?.model.flashHUD(HUDState(kind: .brightness, level: level))
        }

        s.system.onPowerEvent = { [weak self] pluggedIn, level in
            guard let self, self.settings.chargingActivity else { return }
            self.model.showActivity(ActivityState(
                symbol: pluggedIn ? "bolt.fill" : "battery.100",
                title: pluggedIn ? "Charging" : "On Battery",
                detail: "\(level)%",
                tint: pluggedIn ? .green : .white,
                progress: Double(level) / 100))
        }
        s.system.onLowBattery = { [weak self] level in
            guard let self, self.settings.chargingActivity else { return }
            self.model.showActivity(ActivityState(symbol: "battery.25", title: "Low Battery",
                                                  detail: "\(level)% remaining", tint: .red,
                                                  progress: Double(level) / 100), for: 4)
        }

        bluetooth.onChange = { [weak self] name, symbol, connected in
            guard let self, self.settings.bluetoothActivity else { return }
            self.model.showActivity(ActivityState(symbol: symbol, title: name,
                                                  detail: connected ? "Connected" : "Disconnected",
                                                  tint: connected ? .blue : .gray, progress: nil))
        }
        settings.$bluetoothActivity
            .removeDuplicates()
            .sink { [weak self] on in on ? self?.bluetooth.start() : self?.bluetooth.stop() }
            .store(in: &bag)

        s.calendar.onUpcoming = { [weak self] event in
            guard let self, self.settings.calendarActivity else { return }
            let minutes = max(Int((event.start.timeIntervalSinceNow / 60).rounded()), 1)
            self.model.showActivity(ActivityState(symbol: "calendar", title: event.title,
                                                  detail: "Starts in \(minutes) min", tint: event.color,
                                                  progress: nil), for: 6)
        }

        s.timer.onFinish = { [weak self] in
            self?.model.showActivity(ActivityState(symbol: "timer", title: "Timer done",
                                                   detail: "Time for a break", tint: .orange, progress: nil), for: 5)
        }

        mediaKeys.handler = { [weak self] key, fine in self?.handleMediaKey(key, fineStep: fine) ?? false }
        settings.$replaceSystemHUD
            .removeDuplicates()
            .sink { [weak self] on in on ? self?.mediaKeys.start(prompt: true) : self?.mediaKeys.stop() }
            .store(in: &bag)
    }

    // MARK: Volume and brightness keys

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
            model.flashHUD(HUDState(kind: .volume(muted: volume.isMuted), level: volume.isMuted ? 0 : volume.level))
        case .brightnessUp, .brightnessDown:
            guard brightness.isAvailable else { return false }
            brightness.set(stepped(brightness.level, by: key == .brightnessUp ? 1 : -1))
            model.flashHUD(HUDState(kind: .brightness, level: brightness.level))
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

    // MARK: Opening and closing

    func expand(tab: NotchTab? = nil, sticky: Bool = false) {
        cancelPending()
        if let tab { model.tab = tab }
        if sticky { stickyUntil = Date().addingTimeInterval(4) }
        let wasExpanded = model.isExpanded
        panel.ignoresMouseEvents = false
        model.setExpanded(true)
        services.actions.refresh()
        services.player.refresh()
        services.calendar.reload()
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
        panel.ignoresMouseEvents = true
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

    // MARK: Mouse tracking

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
            self?.pressBeganInside = true
            return event
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            self?.handleSwipe(event) == true ? nil : event
        }) {
            monitors.append(m)
        }
    }

    /// Two-finger horizontal swipe on the open panel moves between tabs.
    private func handleSwipe(_ event: NSEvent) -> Bool {
        guard model.isExpanded, settings.swipeBetweenTabs, event.hasPreciseScrollingDeltas else { return false }
        // The tray and clipboard scroll sideways themselves.
        if (model.tab == .tray && !services.tray.items.isEmpty) || (model.tab == .clipboard && !services.clipboard.items.isEmpty) {
            return false
        }
        if event.phase == .began { swipeAccumulator = 0; swipeLocked = false }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
        if !swipeLocked {
            swipeAccumulator += event.scrollingDeltaX
            if abs(swipeAccumulator) > 50 {
                model.selectAdjacentTab(swipeAccumulator < 0 ? 1 : -1)
                swipeLocked = true
                if settings.haptics {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
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
        if model.isExpanded, !model.screenRect.insetBy(dx: -10, dy: -10).contains(point) {
            collapse()
        } else if !model.isExpanded, settings.openTrigger == .click,
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

    private func mouseMoved() {
        let point = NSEvent.mouseLocation
        if model.isExpanded {
            if model.screenRect.insetBy(dx: -10, dy: -10).contains(point) {
                stickyUntil = .distantPast
                collapseWork?.cancel()
                collapseWork = nil
            } else if Date() >= stickyUntil, collapseWork == nil {
                scheduleCollapse()
            }
            return
        }
        // In click mode only a drag opens the notch by itself.
        guard settings.openTrigger == .hover || externalDrag else { return }
        if hotZone().contains(point) {
            guard expandWork == nil else { return }
            let forDrop = externalDrag
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.expandWork = nil
                if self.hotZone().contains(NSEvent.mouseLocation) {
                    self.expand(tab: forDrop ? .tray : nil)
                }
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
            // Don't fold away while a file is being dragged out of the tray.
            if self.pressBeganInside, NSEvent.pressedMouseButtons & 1 != 0 {
                self.scheduleCollapse()
                return
            }
            if !self.model.screenRect.insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation) {
                self.collapse()
            }
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
