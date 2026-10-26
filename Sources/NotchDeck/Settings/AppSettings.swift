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
    case optionSpace, controlOptionSpace, commandShiftSpace, controlOptionN, controlOptionC, controlOptionP, off
    var id: String { rawValue }

    var title: String {
        switch self {
        case .optionSpace: "⌥ Space"
        case .controlOptionSpace: "⌃⌥ Space"
        case .commandShiftSpace: "⇧⌘ Space"
        case .controlOptionN: "⌃⌥ N"
        case .controlOptionC: "⌃⌥ C"
        case .controlOptionP: "⌃⌥ P"
        case .off: "Off"
        }
    }

    /// Carbon key code and modifier mask.
    var carbon: (UInt32, UInt32)? {
        let space: UInt32 = 49, n: UInt32 = 45, c: UInt32 = 8, p: UInt32 = 35
        let cmd: UInt32 = 1 << 8, shift: UInt32 = 1 << 9, option: UInt32 = 1 << 11, control: UInt32 = 1 << 12
        switch self {
        case .optionSpace: return (space, option)
        case .controlOptionSpace: return (space, control | option)
        case .commandShiftSpace: return (space, cmd | shift)
        case .controlOptionN: return (n, control | option)
        case .controlOptionC: return (c, control | option)
        case .controlOptionP: return (p, control | option)
        case .off: return nil
        }
    }
}

enum FontStyle: String, CaseIterable, Identifiable {
    case standard, rounded, serif, mono
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "System"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .mono: "Mono"
        }
    }

    var design: Font.Design {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
    }
}

/// How deliberate a hover has to be before the notch opens.
enum HoverSensitivity: String, CaseIterable, Identifiable {
    case quick, balanced, deliberate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .quick: "Quick"
        case .balanced: "Balanced"
        case .deliberate: "Deliberate"
        }
    }

    var detail: String {
        switch self {
        case .quick: "Opens almost as soon as the pointer arrives, even while it's still moving."
        case .balanced: "Opens a moment after the pointer slows down on the notch; passing over it doesn't."
        case .deliberate: "Opens only when the pointer stays put on the notch for about half a second."
        }
    }

    /// The hover delay it sets.
    var delay: Double {
        switch self {
        case .quick: 0.12
        case .balanced: 0.25
        case .deliberate: 0.45
        }
    }

    /// The fastest the pointer may still be moving, in points a second, when the delay is up.
    /// Crossing the notch on the way somewhere is several hundred.
    var maxSpeed: CGFloat {
        switch self {
        case .quick: 260
        case .balanced: 120
        case .deliberate: 45
        }
    }

    /// Drift, in points over `stillWindow` seconds, that counts as a resting hand whatever the
    /// speed works out at.
    var stillTolerance: CGFloat {
        switch self {
        case .quick: 10
        case .balanced, .deliberate: 6
        }
    }

    var stillWindow: TimeInterval {
        switch self {
        case .quick: 0.12
        case .balanced: 0.15
        case .deliberate: 0.25
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
    @Published var hoverSensitivity: HoverSensitivity {
        didSet {
            save(hoverSensitivity.rawValue, "hoverSensitivity")
            hoverDelay = hoverSensitivity.delay
        }
    }
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
    @Published var glass: Bool { didSet { save(glass, "glass") } }
    /// How see-through the glass is, 0 (solid) to 1 (clear).
    @Published var glassClarity: Double { didSet { save(glassClarity, "glassClarity") } }
    @Published var bouncyAnimation: Bool { didSet { save(bouncyAnimation, "bouncyAnimation") } }

    // Background
    @Published var backgroundMode: BackgroundMode { didSet { save(backgroundMode.rawValue, "backgroundMode") } }
    @Published var backgroundPhotos: [String] { didSet { save(backgroundPhotos, "backgroundPhotos") } }
    @Published var slideshowInterval: Double { didSet { save(slideshowInterval, "slideshowInterval") } }
    @Published var backgroundDim: Double { didSet { save(backgroundDim, "backgroundDim") } }
    @Published var backgroundBlur: Double { didSet { save(backgroundBlur, "backgroundBlur") } }
    @Published var photoReadability: Bool { didSet { save(photoReadability, "photoReadability") } }

    // Widgets and quick launch
    @Published var widgets: [WidgetItem] { didSet { saveJSON(widgets, "widgets") } }
    @Published var quickItems: [QuickItem] { didSet { saveJSON(quickItems, "quickItems") } }
    @Published var showQuickLaunch: Bool { didSet { save(showQuickLaunch, "showQuickLaunch") } }

    // Cat
    @Published var catEnabled: Bool { didSet { save(catEnabled, "catEnabled") } }
    @Published var catName: String { didSet { save(catName, "catName") } }
    @Published var catColor: CatColor { didSet { save(catColor.rawValue, "catColor") } }
    @Published var catSize: Double { didSet { save(catSize, "catSize") } }
    @Published var catPlacement: CatPlacement { didSet { save(catPlacement.rawValue, "catPlacement") } }
    @Published var catPlayfulness: Playfulness { didSet { save(catPlayfulness.rawValue, "catPlayfulness") } }
    @Published var catFeeding: PetFeeding { didSet { save(catFeeding.rawValue, "catFeeding") } }
    /// The hour the dog goes to bed and the hour it gets up; it sleeps right through in between.
    @Published var catBedtime: Int { didSet { save(catBedtime, "catBedtime") } }
    @Published var catWakeTime: Int { didSet { save(catWakeTime, "catWakeTime") } }

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

    // Tasks
    @Published var taskNudges: Bool { didSet { save(taskNudges, "taskNudges") } }
    @Published var taskNudgeMinutes: Int { didSet { save(taskNudgeMinutes, "taskNudgeMinutes") } }
    @Published var tasksInNotch: Bool { didSet { save(tasksInNotch, "tasksInNotch") } }

    // Pomodoro
    @Published var pomodoroWork: Int { didSet { save(pomodoroWork, "pomodoroWork") } }
    @Published var pomodoroShortBreak: Int { didSet { save(pomodoroShortBreak, "pomodoroShortBreak") } }
    @Published var pomodoroLongBreak: Int { didSet { save(pomodoroLongBreak, "pomodoroLongBreak") } }
    @Published var pomodoroRounds: Int { didSet { save(pomodoroRounds, "pomodoroRounds") } }
    @Published var pomodoroAutoStart: Bool { didSet { save(pomodoroAutoStart, "pomodoroAutoStart") } }
    @Published var pomodoroSound: String { didSet { save(pomodoroSound, "pomodoroSound") } }

    // Colour picker
    @Published var colorHotKey: HotKeyChoice { didSet { save(colorHotKey.rawValue, "colorHotKey") } }
    @Published var colorCopyOnPick: Bool { didSet { save(colorCopyOnPick, "colorCopyOnPick") } }
    @Published var colorAutoSave: Bool { didSet { save(colorAutoSave, "colorAutoSave") } }

    // Customise
    @Published var panelWidth: Double { didSet { save(panelWidth, "panelWidth") } }
    @Published var panelExtraHeight: Double { didSet { save(panelExtraHeight, "panelExtraHeight") } }
    @Published var fontStyle: FontStyle { didSet { save(fontStyle.rawValue, "fontStyle") } }
    @Published var headerBattery: Bool { didSet { save(headerBattery, "headerBattery") } }
    @Published var headerClock: Bool { didSet { save(headerClock, "headerClock") } }
    @Published var hoverSwell: Bool { didSet { save(hoverSwell, "hoverSwell") } }
    /// Multiplies every open/close spring's duration: below 1 is snappier, above is lazier.
    @Published var animationSpeed: Double { didSet { save(animationSpeed, "animationSpeed") } }
    /// A tab's raw value, or "last" for wherever you left it.
    @Published var openingTab: String { didSet { save(openingTab, "openingTab") } }

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
        // 0.12 s was the old default; with the steadiness check, a quarter second feels right.
        let storedDelay: Double = value("hoverDelay", 0.25)
        hoverDelay = storedDelay == 0.12 && d.object(forKey: "hoverSensitivity") == nil ? 0.25 : storedDelay
        hoverSensitivity = choice("hoverSensitivity", .balanced)
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
        glass = value("glass", true)
        glassClarity = value("glassClarity", 0.35)
        bouncyAnimation = value("bouncyAnimation", true)

        backgroundMode = choice("backgroundMode", .theme)
        backgroundPhotos = d.stringArray(forKey: "backgroundPhotos") ?? []
        slideshowInterval = value("slideshowInterval", 12)
        backgroundDim = value("backgroundDim", 0.45)
        backgroundBlur = value("backgroundBlur", 0)
        photoReadability = value("photoReadability", true)

        func decoded<T: Decodable>(_ key: String, _ fallback: T) -> T {
            d.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) } ?? fallback
        }
        widgets = decoded("widgets", [WidgetItem(kind: .analogClock), WidgetItem(kind: .weather),
                                      WidgetItem(kind: .battery), WidgetItem(kind: .cat)])
        quickItems = decoded("quickItems", QuickItem.defaults)
        showQuickLaunch = value("showQuickLaunch", true)

        catEnabled = value("catEnabled", true)
        catName = value("catName", "Mochi")
        catColor = choice("catColor", .ginger)
        catSize = value("catSize", 1)
        catPlacement = choice("catPlacement", .screen)
        // "catPlayful" was an on/off switch before the frequency choice; off stays off.
        catPlayfulness = choice("catPlayfulness", value("catPlayful", true) ? .rarely : .off)
        catFeeding = choice("catFeeding", .hover)
        catBedtime = value("catBedtime", 23)
        catWakeTime = value("catWakeTime", 7)

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

        taskNudges = value("taskNudges", true)
        taskNudgeMinutes = value("taskNudgeMinutes", 15)
        tasksInNotch = value("tasksInNotch", true)

        pomodoroWork = value("pomodoroWork", 25)
        pomodoroShortBreak = value("pomodoroShortBreak", 5)
        pomodoroLongBreak = value("pomodoroLongBreak", 15)
        pomodoroRounds = value("pomodoroRounds", 4)
        pomodoroAutoStart = value("pomodoroAutoStart", true)
        pomodoroSound = value("pomodoroSound", "Glass")

        colorHotKey = choice("colorHotKey", .controlOptionC)
        colorCopyOnPick = value("colorCopyOnPick", true)
        colorAutoSave = value("colorAutoSave", true)

        panelWidth = value("panelWidth", Double(NotchModel.expandedContentSize.width))
        panelExtraHeight = value("panelExtraHeight", 0)
        fontStyle = choice("fontStyle", .standard)
        headerBattery = value("headerBattery", true)
        headerClock = value("headerClock", true)
        hoverSwell = value("hoverSwell", true)
        animationSpeed = value("animationSpeed", 1)
        openingTab = value("openingTab", "last")

        scriptCommand = value("scriptCommand", "uptime")
        scriptInterval = value("scriptInterval", 30)

        // Downloaded copies check the public repository for new releases out of the box.
        updateRepository = value("updateRepository", "tadiPro250/notchdeck")

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

    /// The tabs in the order you arranged them (Settings → Customise).
    var visibleTabs: [NotchTab] {
        var seen = Set<NotchTab>()
        return enabledTabs.filter { seen.insert($0).inserted }
    }

    func moveTab(_ tab: NotchTab, by offset: Int) {
        guard let index = enabledTabs.firstIndex(of: tab) else { return }
        let target = min(max(index + offset, 0), enabledTabs.count - 1)
        guard target != index else { return }
        var tabs = enabledTabs
        tabs.remove(at: index)
        tabs.insert(tab, at: target)
        enabledTabs = tabs
    }

    /// Everything on the Customise pane back to how it shipped.
    func resetCustomisation() {
        panelWidth = Double(NotchModel.expandedContentSize.width)
        panelExtraHeight = 0
        fontStyle = .standard
        headerBattery = true
        headerClock = true
        hoverSwell = true
        hoverSensitivity = .balanced
        animationSpeed = 1
        bouncyAnimation = true
        openingTab = "last"
        cornerRadius = 28
        enabledTabs = NotchTab.allCases
    }

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

    /// Every photo a widget or the background still uses, so unused copies can be deleted.
    var referencedImages: Set<String> { Set(backgroundPhotos + widgets.flatMap(\.images)) }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func saveJSON<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
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
