import AppKit
import SwiftUI

/// Where the notch is on one screen. On screens without a notch it is a virtual one: attached to
/// the top edge, or a floating "island" just below it.
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notchSize: CGSize
    let hasNotch: Bool
    var isIsland = false
    var displayID: CGDirectDisplayID = 0

    /// Gap between the top of the screen and a floating island.
    var islandGap: CGFloat { isIsland ? 6 : 0 }

    static func current() -> NotchGeometry {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? screens.first else {
            return NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                 notchSize: CGSize(width: 190, height: 32), hasNotch: false)
        }
        return of(screen, island: false)
    }

    static func of(_ screen: NSScreen, island: Bool) -> NotchGeometry {
        let frame = screen.frame
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return NotchGeometry(screenFrame: frame,
                                 notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
                                 hasNotch: true, displayID: id)
        }
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        let height = island ? 28 : (menuBar > 0 ? min(menuBar, 32) : 24)
        return NotchGeometry(screenFrame: frame, notchSize: CGSize(width: island ? 150 : 190, height: height),
                             hasNotch: false, isIsland: island, displayID: id)
    }
}

enum NotchTab: String, CaseIterable, Identifiable {
    case home, widgets, tray, calendar, clock, desk, clipboard, mirror, controls, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .widgets: "Widgets"
        case .tray: "Tray"
        case .calendar: "Calendar"
        case .clock: "Clock"
        case .desk: "Desk"
        case .clipboard: "Clipboard"
        case .mirror: "Mirror"
        case .controls: "Controls"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .widgets: "square.grid.2x2.fill"
        case .tray: "tray.full.fill"
        case .calendar: "calendar"
        case .clock: "alarm.fill"
        case .desk: "square.and.pencil"
        case .clipboard: "doc.on.clipboard.fill"
        case .mirror: "camera.fill"
        case .controls: "slider.horizontal.3"
        case .system: "cpu.fill"
        }
    }
}

struct HUDState: Equatable {
    enum Kind: Equatable {
        case volume(muted: Bool)
        case brightness
        case externalBrightness
        case keyboard
    }

    var kind: Kind
    var level: Double

    var symbol: String {
        switch kind {
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .externalBrightness:
            return "display"
        case .keyboard:
            return level < 0.01 ? "keyboard" : "keyboard.fill"
        case .volume(let muted):
            if muted || level == 0 { return "speaker.slash.fill" }
            if level < 0.33 { return "speaker.wave.1.fill" }
            if level < 0.66 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }
}

/// A short-lived announcement that drops down from the notch: charging, AirPods, a meeting…
struct ActivityState: Equatable {
    var symbol: String
    var title: String
    var detail: String?
    var tint: Color
    /// 0…1 for a ring around the icon (battery level), nil for none.
    var progress: Double?
    var id = UUID()
}

/// Small coloured dots for things using your privacy right now.
struct PrivacyState: Equatable {
    var camera = false
    var microphone = false
    var screen = false
    var micMuted = false

    var any: Bool { camera || microphone || screen || micMuted }
}

enum Presentation: Equatable {
    case collapsed
    case privacy
    case live
    case download
    case countdown
    case stopwatch
    case timer
    case activity(ActivityState)
    case hud(HUDState)
    case ringing(Ringing)
    case expanded
}

final class NotchModel: ObservableObject {
    /// The open panel without the quick-launch row; the row adds `dockHeight`.
    static let expandedContentSize = CGSize(width: 740, height: 262)
    static let dockHeight: CGFloat = 42

    @Published var geometry: NotchGeometry
    @Published private(set) var isExpanded = false
    @Published var tab: NotchTab = .home
    @Published private(set) var hud: HUDState?
    @Published private(set) var activity: ActivityState?
    @Published var isPlaying = false
    @Published var timerActive = false
    @Published var stopwatchActive = false
    @Published var ringing: Ringing?
    @Published var countdown: CalendarEvent?
    @Published var downloading = false
    @Published var privacy = PrivacyState()
    @Published var dropTargeted = false
    /// The pointer is over the closed notch: it swells a little, inviting a hover.
    @Published var hovering = false

    let settings: AppSettings

    /// Set by the controller so views can ask the panel to close (e.g. before a screenshot).
    var onRequestCollapse: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// Views with text fields ask for keyboard focus through this.
    var onRequestKeyboard: (() -> Void)?
    /// Opens the notch again on a tab, after an open panel closes.
    var onReopen: ((NotchTab) -> Void)?

    private var hudHide: DispatchWorkItem?
    private var activityHide: DispatchWorkItem?

    init(geometry: NotchGeometry, settings: AppSettings = .shared) {
        self.geometry = geometry
        self.settings = settings
    }

    var isIsland: Bool { geometry.isIsland }

    var presentation: Presentation {
        if let ringing { return .ringing(ringing) }
        if isExpanded { return .expanded }
        if let hud { return .hud(hud) }
        if let activity { return .activity(activity) }
        if timerActive { return .timer }
        if stopwatchActive { return .stopwatch }
        if countdown != nil, settings.calendarCountdown { return .countdown }
        if downloading, settings.downloadActivity { return .download }
        if isPlaying, settings.showLiveActivity { return .live }
        if privacy.any, settings.privacyIndicators { return .privacy }
        return .collapsed
    }

    /// The flared corners that blend into the menu bar; an island has none.
    var topRadius: CGFloat { isIsland ? 0 : (isExpanded ? 14 : 6) }

    var bottomRadius: CGFloat {
        let radius: CGFloat
        switch presentation {
        case .expanded: radius = CGFloat(settings.cornerRadius)
        case .activity, .ringing: radius = 22
        case .hud where settings.hudStyle == .bar: radius = 16
        default: radius = isIsland ? geometry.notchSize.height / 2 : 10
        }
        return radius
    }

    /// Size of the black shape, including the flared "ears" at the top corners.
    var shapeSize: CGSize {
        let notch = geometry.notchSize
        let body: CGSize
        switch presentation {
        case .expanded:
            body = expandedSize
        case .ringing:
            body = CGSize(width: max(notch.width + 230, 410), height: notch.height + 68)
        case .hud:
            body = settings.hudStyle == .bar
                ? CGSize(width: notch.width + 90, height: notch.height + 28)
                : CGSize(width: notch.width + 200, height: notch.height)
        case .activity:
            body = CGSize(width: max(notch.width + 150, 330), height: notch.height + 50)
        case .timer, .download:
            body = CGSize(width: notch.width + 2 * 62, height: notch.height)
        case .stopwatch:
            body = CGSize(width: notch.width + 2 * 74, height: notch.height)
        case .countdown:
            body = CGSize(width: notch.width + 2 * 118, height: notch.height)
        case .live:
            body = CGSize(width: notch.width + 2 * (notch.height + 4), height: notch.height)
        case .privacy:
            body = CGSize(width: notch.width + 2 * 18, height: notch.height)
        case .collapsed:
            body = notch
        }
        // Hovering swells the closed notch a touch before it opens.
        if hovering, !isExpanded, ringing == nil, hud == nil, activity == nil {
            return CGSize(width: body.width + 2 * topRadius + 16, height: body.height + 5)
        }
        return CGSize(width: body.width + 2 * topRadius, height: body.height)
    }

    /// The visible shape in screen coordinates (AppKit, bottom-left origin).
    var screenRect: CGRect {
        let size = shapeSize
        return CGRect(x: geometry.screenFrame.midX - size.width / 2,
                      y: geometry.screenFrame.maxY - geometry.islandGap - size.height,
                      width: size.width, height: size.height)
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        hovering = false
        if expanded {
            hud = nil
            activity = nil
        }
        if !settings.isEnabled(tab) { tab = .home }
    }

    func flashHUD(_ state: HUDState) {
        guard !isExpanded else { return }
        hud = state
        hudHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hud = nil }
        hudHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func showActivity(_ state: ActivityState, for seconds: Double = 3) {
        guard !isExpanded else { return }
        activity = state
        activityHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.activity = nil }
        activityHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func selectAdjacentTab(_ offset: Int) {
        let tabs = settings.visibleTabs
        guard let index = tabs.firstIndex(of: tab), !tabs.isEmpty else { return }
        tab = tabs[(index + offset + tabs.count) % tabs.count]
    }

    /// Folds the notch away while an open panel is up (the panel sits under the notch's level),
    /// then reopens it on `tab` once the user has chosen.
    func pick(_ present: (@escaping ([URL]) -> Void) -> Void, reopen tab: NotchTab, then handle: @escaping ([URL]) -> Void) {
        requestCollapse()
        present { [weak self] urls in
            handle(urls)
            self?.onReopen?(tab)
        }
    }

    var expandedSize: CGSize {
        let size = Self.expandedContentSize
        return settings.showQuickLaunch ? CGSize(width: size.width, height: size.height + Self.dockHeight) : size
    }

    func requestCollapse() { onRequestCollapse?() }
    func openSettings() { onOpenSettings?() }
    func requestKeyboard() { onRequestKeyboard?() }
}
