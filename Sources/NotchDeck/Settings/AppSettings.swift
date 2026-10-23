import AppKit
import SwiftUI

enum OpenTrigger: String, CaseIterable, Identifiable {
    case hover, click
    var id: String { rawValue }
    var title: String { self == .hover ? "Hover" : "Click" }
}

enum AccentSource: String, CaseIterable, Identifiable {
    case artwork, theme, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .artwork: "From album art"
        case .theme: "From theme"
        case .custom: "Custom colour"
        }
    }
}

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case bars, wave, dots, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bars: "Bars"
        case .wave: "Wave"
        case .dots: "Dots"
        case .off: "Off"
        }
    }
}

enum HUDStyle: String, CaseIterable, Identifiable {
    case wings, bar
    var id: String { rawValue }
    var title: String { self == .wings ? "Wings" : "Progress bar" }
}

enum VolumeSteps: Int, CaseIterable, Identifiable {
    case coarse = 10, standard = 16, fine = 32, finest = 64
    var id: Int { rawValue }
    var title: String { "\(rawValue) steps" }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var symbol: String { self == .celsius ? "°C" : "°F" }
}

enum GlanceWidget: String, CaseIterable, Identifiable {
    case clock, weather, calendar, stats
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clock: "Clock"
        case .weather: "Weather"
        case .calendar: "Next event"
        case .stats: "System stats"
        }
    }
}

/// Every user preference, persisted in UserDefaults. Views observe this directly.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    // General
    @Published var openTrigger: OpenTrigger { didSet { save(openTrigger.rawValue, "openTrigger") } }
    @Published var hoverDelay: Double { didSet { save(hoverDelay, "hoverDelay") } }
    @Published var haptics: Bool { didSet { save(haptics, "haptics") } }
    @Published var swipeBetweenTabs: Bool { didSet { save(swipeBetweenTabs, "swipeBetweenTabs") } }
    @Published var enabledTabs: [NotchTab] { didSet { save(enabledTabs.map(\.rawValue), "enabledTabs") } }

    // Appearance
    @Published var themeID: String { didSet { save(themeID, "themeID") } }
    @Published var accentSource: AccentSource { didSet { save(accentSource.rawValue, "accentSource") } }
    @Published var customAccent: Color { didSet { save(customAccent.hexString, "customAccent") } }
    @Published var cornerRadius: Double { didSet { save(cornerRadius, "cornerRadius") } }
    @Published var shadow: Bool { didSet { save(shadow, "shadow") } }
    @Published var glanceWidget: GlanceWidget { didSet { save(glanceWidget.rawValue, "glanceWidget") } }

    // Media
    @Published var visualizer: VisualizerStyle { didSet { save(visualizer.rawValue, "visualizer") } }
    @Published var showLiveActivity: Bool { didSet { save(showLiveActivity, "showLiveActivity") } }

    // HUD
    @Published var replaceSystemHUD: Bool { didSet { save(replaceSystemHUD, "replaceSystemHUD") } }
    @Published var hudStyle: HUDStyle { didSet { save(hudStyle.rawValue, "hudStyle") } }
    @Published var volumeSteps: VolumeSteps { didSet { save(volumeSteps.rawValue, "volumeSteps") } }

    // Live activities
    @Published var chargingActivity: Bool { didSet { save(chargingActivity, "chargingActivity") } }
    @Published var bluetoothActivity: Bool { didSet { save(bluetoothActivity, "bluetoothActivity") } }
    @Published var calendarActivity: Bool { didSet { save(calendarActivity, "calendarActivity") } }

    // Tray and clipboard
    @Published var copyDroppedFiles: Bool { didSet { save(copyDroppedFiles, "copyDroppedFiles") } }
    @Published var clipboardEnabled: Bool { didSet { save(clipboardEnabled, "clipboardEnabled") } }
    @Published var clipboardLimit: Int { didSet { save(clipboardLimit, "clipboardLimit") } }

    // Weather
    @Published var weatherCity: String { didSet { save(weatherCity, "weatherCity") } }
    @Published var temperatureUnit: TemperatureUnit { didSet { save(temperatureUnit.rawValue, "temperatureUnit") } }

    /// `defaults` other than `.standard` gives a throwaway store (used by `--render-previews`).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        func value<T>(_ key: String, _ fallback: T) -> T { d.object(forKey: key) as? T ?? fallback }
        func choice<T: RawRepresentable>(_ key: String, _ fallback: T) -> T {
            (d.object(forKey: key) as? T.RawValue).flatMap(T.init(rawValue:)) ?? fallback
        }

        openTrigger = choice("openTrigger", .hover)
        hoverDelay = value("hoverDelay", 0.12)
        haptics = value("haptics", true)
        swipeBetweenTabs = value("swipeBetweenTabs", true)
        let tabs = (d.stringArray(forKey: "enabledTabs") ?? []).compactMap(NotchTab.init(rawValue:))
        enabledTabs = tabs.isEmpty ? NotchTab.allCases : tabs

        themeID = value("themeID", Theme.midnight.id)
        accentSource = choice("accentSource", .artwork)
        customAccent = Color(hex: value("customAccent", "#FF6FA8")) ?? .pink
        cornerRadius = value("cornerRadius", 28)
        shadow = value("shadow", true)
        glanceWidget = choice("glanceWidget", .clock)

        visualizer = choice("visualizer", .bars)
        showLiveActivity = value("showLiveActivity", true)

        replaceSystemHUD = value("replaceSystemHUD", true)
        hudStyle = choice("hudStyle", .wings)
        volumeSteps = choice("volumeSteps", .standard)

        chargingActivity = value("chargingActivity", true)
        bluetoothActivity = value("bluetoothActivity", true)
        calendarActivity = value("calendarActivity", true)

        copyDroppedFiles = value("copyDroppedFiles", false)
        clipboardEnabled = value("clipboardEnabled", true)
        clipboardLimit = value("clipboardLimit", 25)

        weatherCity = value("weatherCity", "")
        temperatureUnit = choice("temperatureUnit", .celsius)
    }

    var theme: Theme { Theme.all.first { $0.id == themeID } ?? .midnight }

    var visibleTabs: [NotchTab] { NotchTab.allCases.filter(enabledTabs.contains) }

    func isEnabled(_ tab: NotchTab) -> Bool { enabledTabs.contains(tab) }

    func setEnabled(_ tab: NotchTab, _ on: Bool) {
        if on, !enabledTabs.contains(tab) { enabledTabs.append(tab) }
        // Home always stays, so the panel never opens empty.
        if !on, tab != .home { enabledTabs.removeAll { $0 == tab } }
    }

    /// The accent for this moment: album colour while music plays (if chosen), else theme or custom.
    func accent(artwork: Color?) -> Color {
        switch accentSource {
        case .artwork: artwork ?? theme.accent
        case .theme: theme.accent
        case .custom: customAccent
        }
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}

extension Color {
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255),
                      Int(c.blueComponent * 255))
    }
}
