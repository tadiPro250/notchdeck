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

/// Owns the panel that sits over the notch, and decides when it opens and closes.
final class NotchController {
    static let windowSize = CGSize(width: 780, height: 270)

    let model: NotchModel
    let player = NowPlaying()
    let tray = FileTray()
    let volume = VolumeControl()
    let brightness = BrightnessControl()
    let system = SystemStatus()
    let actions = QuickActions()
    let mediaKeys = MediaKeyInterceptor()

    static let replaceHUDKey = "replaceSystemHUD"
    var replacesSystemHUD: Bool {
        get { UserDefaults.standard.object(forKey: Self.replaceHUDKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.replaceHUDKey)
            newValue ? mediaKeys.start(prompt: true) : mediaKeys.stop()
        }
    }

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

    init() {
        model = NotchModel(geometry: .current())
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

        let root = NotchRootView(model: model, player: player, tray: tray, volume: volume,
                                 brightness: brightness, system: system, actions: actions)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        place()
        panel.orderFrontRegardless()

        model.onRequestCollapse = { [weak self] in self?.collapse() }

        player.$track
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            .sink { [weak self] playing in self?.model.isPlaying = playing }
            .store(in: &bag)

        volume.onExternalChange = { [weak self] level, muted in
            self?.model.flashHUD(HUDState(kind: .volume(muted: muted), level: muted ? 0 : level))
        }
        brightness.onExternalChange = { [weak self] level in
            self?.model.flashHUD(HUDState(kind: .brightness, level: level))
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.model.geometry = .current()
            self.brightness.refreshDisplay()
            self.place()
        }

        installMonitors()

        mediaKeys.handler = { [weak self] key, fine in self?.handleMediaKey(key, fineStep: fine) ?? false }
        if replacesSystemHUD { mediaKeys.start(prompt: true) }
    }

    // MARK: Volume and brightness keys

    /// Does what the key would have done, then shows the notch HUD instead of the system one.
    private func handleMediaKey(_ key: MediaKeyInterceptor.Key, fineStep: Bool) -> Bool {
        let step = fineStep ? 1.0 / 64 : 1.0 / 16
        func stepped(_ value: Double, by delta: Double) -> Double {
            min(max(((value / step).rounded() + delta) * step, 0), 1)
        }
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
        guard enabled == 1, !volume.isMuted, let sound = feedbackSound else { return }
        sound.stop()
        sound.play()
    }

    // MARK: Opening and closing

    func expand(tab: NotchTab? = nil, sticky: Bool = false) {
        cancelPending()
        if let tab { model.tab = tab }
        if sticky { stickyUntil = Date().addingTimeInterval(4) }
        panel.ignoresMouseEvents = false
        model.setExpanded(true)
        actions.refresh()
        player.refresh()
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
    }

    private func globalMouseDown() {
        pressBeganInside = false
        externalDrag = false
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        startDragPolling()
        if model.isExpanded, !model.screenRect.insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation) {
            collapse()
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
        } else {
            let hot = externalDrag
                ? model.screenRect.insetBy(dx: -60, dy: -40)
                : model.screenRect.insetBy(dx: -2, dy: -2)
            if hot.contains(point) {
                guard expandWork == nil else { return }
                let forDrop = externalDrag
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.expandWork = nil
                    let stillHot = self.externalDrag
                        ? self.model.screenRect.insetBy(dx: -60, dy: -40)
                        : self.model.screenRect.insetBy(dx: -2, dy: -2)
                    if stillHot.contains(NSEvent.mouseLocation) {
                        self.expand(tab: forDrop ? .tray : nil)
                    }
                }
                expandWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + (forDrop ? 0 : 0.12), execute: work)
            } else {
                expandWork?.cancel()
                expandWork = nil
            }
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
