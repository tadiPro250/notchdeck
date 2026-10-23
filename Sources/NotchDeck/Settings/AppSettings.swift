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

enum HotKeyChoice: String, CaseIterable, Identifiable {
    case optionSpace, controlOptionSpace, commandShiftSpace, controlOptionN, off
    var id: String { rawValue }

    var title: String {
        switch self {
        case .optionSpace: "⌥ Space"
        case .controlOptionSpace: "⌃⌥ Space"
        case .commandShiftSpace: "⇧⌘ Space"
        case .controlOptionN: "⌃⌥ N"
        case .off: "Off"
        }
    }

    /// Carbon key code and modifier mask.
    var carbon: (UInt32, UInt32)? {
        let space: UInt32 = 49, n: UInt32 = 45
        let cmd: UInt32 = 1 << 8, shift: UInt32 = 1 << 9, option: UInt32 = 1 << 11, control: UInt32 = 1 << 12
        switch self {
        case .optionSpace: return (space, option)
        case .controlOptionSpace: return (space, control | option)
        case .commandShiftSpace: return (space, cmd | shift)
        case .controlOptionN: return (n, control | option)
        case .off: return nil
        }
    }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case notched, main, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notched: "The built-in display"
        case .main: "The main display"
        case .all: "Every display"
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
    @Published var hotKey: HotKeyChoice { didSet { save(hotKey.rawValue, "hotKey") } }
    @Published var onboarded: Bool { didSet { save(onboarded, "onboarded") } }

    // Displays
    @Published var displayMode: DisplayMode { didSet { save(displayMode.rawValue, "displayMode") } }
    @Published var islandOnPlainDisplays: Bool { didSet { save(islandOnPlainDisplays, "islandOnPlainDisplays") } }
    @Published var lockScreenWidget: Bool { didSet { save(lockScreenWidget, "lockScreenWidget") } }

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
    @Published var showLyrics: Bool { didSet { save(showLyrics, "showLyrics") } }

    // HUD
    @Published var replaceSystemHUD: Bool { didSet { save(replaceSystemHUD, "replaceSystemHUD") } }
    @Published var hudStyle: HUDStyle { didSet { save(hudStyle.rawValue, "hudStyle") } }
    @Published var volumeSteps: VolumeSteps { didSet { save(volumeSteps.rawValue, "volumeSteps") } }

    // Live activities
    @Published var chargingActivity: Bool { didSet { save(chargingActivity, "chargingActivity") } }
    @Published var bluetoothActivity: Bool { didSet { save(bluetoothActivity, "bluetoothActivity") } }
    @Published var calendarActivity: Bool { didSet { save(calendarActivity, "calendarActivity") } }
    @Published var calendarCountdown: Bool { didSet { save(calendarCountdown, "calendarCountdown") } }
    @Published var reminderActivity: Bool { didSet { save(reminderActivity, "reminderActivity") } }
    @Published var downloadActivity: Bool { didSet { save(downloadActivity, "downloadActivity") } }
    @Published var focusActivity: Bool { didSet { save(focusActivity, "focusActivity") } }
    @Published var privacyIndicators: Bool { didSet { save(privacyIndicators, "privacyIndicators") } }
    @Published var accessoryBattery: Bool { didSet { save(accessoryBattery, "accessoryBattery") } }

    // Clock
    @Published var alarmSound: String { didSet { save(alarmSound, "alarmSound") } }
    @Published var snoozeMinutes: Int { didSet { save(snoozeMinutes, "snoozeMinutes") } }

    // Desk
    @Published var scriptCommand: String { didSet { save(scriptCommand, "scriptCommand") } }
    @Published var scriptInterval: Int { didSet { save(scriptInterval, "scriptInterval") } }

    // Updates
    @Published var updateRepository: String { didSet { save(updateRepository, "updateRepository") } }

    // Tray and clipboard
    @Published var copyDroppedFiles: Bool { didSet { save(copyDroppedFiles, "copyDroppedFiles") } }
    @Published var clipboardEnabled: Bool { didSet { save(clipboardEnabled, "clipboardEnabled") } }
    @Published var clipboardLimit: Int { didSet { save(clipboardLimit, "clipboardLimit") } }
    @Published var clipboardPersist: Bool { didSet { save(clipboardPersist, "clipboardPersist") } }
    @Published var downloadsToTray: Bool { didSet { save(downloadsToTray, "downloadsToTray") } }

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
        // Tabs added in a later version start switched on.
        let known = Set(d.stringArray(forKey: "knownTabs") ?? (d.stringArray(forKey: "enabledTabs") == nil ? [] :
            ["home", "tray", "calendar", "clipboard", "mirror", "controls"]))
        if let stored = d.stringArray(forKey: "enabledTabs") {
            let saved = stored.compactMap(NotchTab.init(rawValue:))
            let added = NotchTab.allCases.filter { !known.contains($0.rawValue) && !saved.contains($0) }
            enabledTabs = saved.contains(.home) ? saved + added : [.home] + saved + added
        } else {
            // Never customised: everything on.
            enabledTabs = NotchTab.allCases
        }
        d.set(NotchTab.allCases.map(\.rawValue), forKey: "knownTabs")
        hotKey = choice("hotKey", .optionSpace)
        onboarded = value("onboarded", false)

        displayMode = choice("displayMode", .notched)
        islandOnPlainDisplays = value("islandOnPlainDisplays", true)
        lockScreenWidget = value("lockScreenWidget", true)

        themeID = value("themeID", Theme.midnight.id)
        accentSource = choice("accentSource", .artwork)
        customAccent = Color(hex: value("customAccent", "#FF6FA8")) ?? .pink
        cornerRadius = value("cornerRadius", 28)
        shadow = value("shadow", true)
        glanceWidget = choice("glanceWidget", .clock)

        visualizer = choice("visualizer", .bars)
        showLiveActivity = value("showLiveActivity", true)
        showLyrics = value("showLyrics", true)

        replaceSystemHUD = value("replaceSystemHUD", true)
        hudStyle = choice("hudStyle", .wings)
        volumeSteps = choice("volumeSteps", .standard)

        chargingActivity = value("chargingActivity", true)
        bluetoothActivity = value("bluetoothActivity", true)
        calendarActivity = value("calendarActivity", true)
        calendarCountdown = value("calendarCountdown", true)
        reminderActivity = value("reminderActivity", true)
        downloadActivity = value("downloadActivity", true)
        focusActivity = value("focusActivity", true)
        privacyIndicators = value("privacyIndicators", true)
        accessoryBattery = value("accessoryBattery", true)

        alarmSound = value("alarmSound", "Hero")
        snoozeMinutes = value("snoozeMinutes", 9)

        scriptCommand = value("scriptCommand", "uptime")
        scriptInterval = value("scriptInterval", 30)

        updateRepository = value("updateRepository", "")

        copyDroppedFiles = value("copyDroppedFiles", false)
        clipboardEnabled = value("clipboardEnabled", true)
        clipboardLimit = value("clipboardLimit", 25)
        clipboardPersist = value("clipboardPersist", false)
        downloadsToTray = value("downloadsToTray", true)

        weatherCity = value("weatherCity", "")
        temperatureUnit = choice("temperatureUnit", .celsius)
    }

    /// Alert sounds installed with macOS, for the alarm picker.
    static var systemSounds: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return names.map { ($0 as NSString).deletingPathExtension }.sorted()
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
