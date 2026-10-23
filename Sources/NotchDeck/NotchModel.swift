import AppKit
import SwiftUI

/// Where the notch is on the screen that has one (or a virtual notch on Macs without one).
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notchSize: CGSize
    let hasNotch: Bool

    static func current() -> NotchGeometry {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? screens.first else {
            return NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                 notchSize: CGSize(width: 190, height: 32), hasNotch: false)
        }
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return NotchGeometry(screenFrame: frame,
                                 notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
                                 hasNotch: true)
        }
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        let height = menuBar > 0 ? min(menuBar, 32) : 24
        return NotchGeometry(screenFrame: frame, notchSize: CGSize(width: 190, height: height), hasNotch: false)
    }
}

enum NotchTab: String, CaseIterable, Identifiable {
    case home, tray, calendar, clipboard, mirror, controls

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .tray: "Tray"
        case .calendar: "Calendar"
        case .clipboard: "Clipboard"
        case .mirror: "Mirror"
        case .controls: "Controls"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .tray: "tray.full.fill"
        case .calendar: "calendar"
        case .clipboard: "doc.on.clipboard.fill"
        case .mirror: "camera.fill"
        case .controls: "slider.horizontal.3"
        }
    }
}

struct HUDState: Equatable {
    enum Kind: Equatable {
        case volume(muted: Bool)
        case brightness
    }

    var kind: Kind
    var level: Double

    var symbol: String {
        switch kind {
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
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

enum Presentation: Equatable {
    case collapsed
    case live
    case timer
    case activity(ActivityState)
    case hud(HUDState)
    case expanded

    var kind: Int {
        switch self {
        case .collapsed: 0
        case .live: 1
        case .timer: 2
        case .activity: 3
        case .hud: 4
        case .expanded: 5
        }
    }
}

final class NotchModel: ObservableObject {
    static let expandedContentSize = CGSize(width: 680, height: 232)

    @Published var geometry: NotchGeometry
    @Published private(set) var isExpanded = false
    @Published var tab: NotchTab = .home
    @Published private(set) var hud: HUDState?
    @Published private(set) var activity: ActivityState?
    @Published var isPlaying = false
    @Published var timerActive = false
    @Published var dropTargeted = false

    let settings: AppSettings

    /// Set by the controller so views can ask the panel to close (e.g. before a screenshot).
    var onRequestCollapse: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var hudHide: DispatchWorkItem?
    private var activityHide: DispatchWorkItem?

    init(geometry: NotchGeometry, settings: AppSettings = .shared) {
        self.geometry = geometry
        self.settings = settings
    }

    var presentation: Presentation {
        if isExpanded { return .expanded }
        if let hud { return .hud(hud) }
        if let activity { return .activity(activity) }
        if timerActive { return .timer }
        if isPlaying, settings.showLiveActivity { return .live }
        return .collapsed
    }

    var topRadius: CGFloat { isExpanded ? 14 : 6 }

    var bottomRadius: CGFloat {
        switch presentation {
        case .expanded: CGFloat(settings.cornerRadius)
        case .activity: 22
        case .hud where settings.hudStyle == .bar: 16
        default: 10
        }
    }

    /// Size of the black shape, including the flared "ears" at the top corners.
    var shapeSize: CGSize {
        let notch = geometry.notchSize
        let body: CGSize
        switch presentation {
        case .expanded:
            body = Self.expandedContentSize
        case .hud:
            body = settings.hudStyle == .bar
                ? CGSize(width: notch.width + 90, height: notch.height + 28)
                : CGSize(width: notch.width + 200, height: notch.height)
        case .activity:
            body = CGSize(width: max(notch.width + 150, 330), height: notch.height + 50)
        case .timer:
            body = CGSize(width: notch.width + 2 * 62, height: notch.height)
        case .live:
            body = CGSize(width: notch.width + 2 * (notch.height + 4), height: notch.height)
        case .collapsed:
            body = notch
        }
        return CGSize(width: body.width + 2 * topRadius, height: body.height)
    }

    /// The visible shape in screen coordinates (AppKit, bottom-left origin).
    var screenRect: CGRect {
        let size = shapeSize
        return CGRect(x: geometry.screenFrame.midX - size.width / 2,
                      y: geometry.screenFrame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
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
        let next = (index + offset + tabs.count) % tabs.count
        tab = tabs[next]
    }

    func requestCollapse() { onRequestCollapse?() }
    func openSettings() { onOpenSettings?() }
}
