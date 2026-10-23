import AppKit
import IOKit.ps
import IOKit.pwr_mgt

final class SystemStatus: ObservableObject {
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var onPower = false

    /// Fired when the power source flips (plugged in or unplugged) or the battery runs low.
    var onPowerEvent: ((_ pluggedIn: Bool, _ level: Int) -> Void)?
    var onLowBattery: ((_ level: Int) -> Void)?

    private var timer: Timer?
    private var hasReading = false

    init(live: Bool = true) {
        refresh()
        guard live else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        // Instant updates when the charger is connected or the level changes.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<SystemStatus>.fromOpaque(context).takeUnretainedValue().refresh()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func showPreview(level: Int, charging: Bool) {
        batteryLevel = level
        isCharging = charging
        onPower = charging
    }

    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let level = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0
            let power = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let previousLevel = batteryLevel
            let previousPower = onPower

            batteryLevel = level
            isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            onPower = power

            if hasReading {
                if power != previousPower { onPowerEvent?(power, level) }
                if !power, let previousLevel, [20, 10, 5].contains(where: { previousLevel > $0 && level <= $0 }) {
                    onLowBattery?(level)
                }
            }
            hasReading = true
            return
        }
        batteryLevel = nil
    }
}

/// One-tap toggles and actions for the Controls tab.
final class QuickActions: ObservableObject {
    @Published private(set) var keepAwake = false
    @Published private(set) var darkMode = false
    @Published private(set) var desktopHidden = false

    private var assertion: IOPMAssertionID = 0
    private let queue = DispatchQueue(label: "notchdeck.actions")
    private var themeObserver: NSObjectProtocol?

    init() {
        refresh()
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String
        darkMode = style == "Dark"

        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        let createDesktop = CFPreferencesCopyAppValue("CreateDesktop" as CFString, "com.apple.finder" as CFString)
        desktopHidden = (createDesktop as? Bool) == false || (createDesktop as? String)?.lowercased() == "false"
    }

    func toggleKeepAwake() {
        if keepAwake {
            IOPMAssertionRelease(assertion)
            assertion = 0
            keepAwake = false
        } else {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "NotchDeck: Keep Awake" as CFString, &assertion)
            keepAwake = result == kIOReturnSuccess
        }
    }

    func toggleDarkMode() {
        darkMode.toggle()
        queue.async { [weak self] in
            AppleScript.run("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refresh() }
        }
    }

    func toggleDesktopIcons() {
        let hide = !desktopHidden
        desktopHidden = hide
        queue.async {
            Self.shell("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hide ? "false" : "true"])
            Self.shell("/usr/bin/killall", ["Finder"])
        }
    }

    func screenshot() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func sleepDisplay() {
        queue.async { Self.shell("/usr/bin/pmset", ["displaysleepnow"]) }
    }

    func lockScreen() {
        typealias Lock = @convention(c) () -> Int32
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            _ = unsafeBitCast(symbol, to: Lock.self)()
        } else {
            sleepDisplay()
        }
    }

    @discardableResult
    private static func shell(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
