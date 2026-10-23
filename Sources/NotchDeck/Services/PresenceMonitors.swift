import AppKit
import CoreAudio
import CoreMediaIO
import IOKit

/// Which Focus is on. macOS keeps this in ~/Library/DoNotDisturb, readable once NotchDeck has
/// Full Disk Access; without it `needsFullDiskAccess` is set and nothing is announced.
final class FocusWatcher: ObservableObject {
    @Published private(set) var activeFocus: String?
    @Published private(set) var needsFullDiskAccess = false

    var onChange: ((_ name: String?) -> Void)?

    private var timer: Timer?
    private var hasReading = false
    private let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")

    init(live: Bool = true) {
        guard live else { return }
        read()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.read() }
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    private func read() {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("Assertions.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            needsFullDiskAccess = true
            return
        }
        needsFullDiskAccess = false
        let records = ((json["data"] as? [[String: Any]])?.first?["storeAssertionRecords"] as? [[String: Any]]) ?? []
        var name: String?
        if let record = records.first {
            let modeID = (record["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String
            name = modeID.flatMap(modeName) ?? "Focus"
        }
        if hasReading, name != activeFocus { onChange?(name) }
        hasReading = true
        activeFocus = name
    }

    private func modeName(_ identifier: String) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("ModeConfigurations.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let configs = (json["data"] as? [[String: Any]])?.first?["modeConfigurations"] as? [String: Any],
              let config = configs[identifier] as? [String: Any],
              let mode = config["mode"] as? [String: Any] else {
            return identifier.contains("default") ? "Do Not Disturb" : nil
        }
        return mode["name"] as? String
    }

    static func symbol(for name: String?) -> String {
        let lower = (name ?? "").lowercased()
        if lower.contains("sleep") { return "bed.double.fill" }
        if lower.contains("work") { return "briefcase.fill" }
        if lower.contains("personal") { return "person.fill" }
        if lower.contains("driv") { return "car.fill" }
        if lower.contains("fitness") { return "figure.run" }
        if lower.contains("game") { return "gamecontroller.fill" }
        if lower.contains("read") { return "book.fill" }
        return "moon.fill"
    }
}

/// Is the camera, the microphone or a screen recording in use right now?
final class PrivacyMonitor: ObservableObject {
    @Published private(set) var cameraInUse = false
    @Published private(set) var microphoneInUse = false
    @Published private(set) var screenRecording = false

    private var timer: Timer?
    private typealias WatcherFn = @convention(c) () -> Bool
    private var screenWatcher: WatcherFn?

    var anyActive: Bool { cameraInUse || microphoneInUse || screenRecording }

    init(live: Bool = true) {
        guard live else { return }
        if let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) {
            let symbol = dlsym(handle, "SLSIsScreenWatcherPresent") ?? dlsym(handle, "CGSIsScreenWatcherPresent")
            screenWatcher = symbol.map { unsafeBitCast($0, to: WatcherFn.self) }
        }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
    }

    func showPreview(camera: Bool, microphone: Bool, screen: Bool) {
        cameraInUse = camera
        microphoneInUse = microphone
        screenRecording = screen
    }

    private func sample() {
        let camera = Self.cameraRunning()
        let microphone = Self.microphoneRunning()
        let screen = screenWatcher?() ?? false
        if camera != cameraInUse { cameraInUse = camera }
        if microphone != microphoneInUse { microphoneInUse = microphone }
        if screen != screenRecording { screenRecording = screen }
    }

    private static func cameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0,
              size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == 0
        else { return false }
        for device in devices {
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var value: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(device, &running, 0, nil, valueSize, &valueSize, &value) == 0, value != 0 {
                return true
            }
        }
        return false
    }

    private static func microphoneRunning() -> Bool {
        guard let device = AudioDevices.defaultDevice(input: true) else { return false }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }
}

/// Battery levels of AirPods, Magic Mouse/Keyboard/Trackpad and other Bluetooth accessories.
final class AccessoryBatteries: ObservableObject {
    struct Accessory: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let symbol: String
        /// Single level, or left/right/case for earbuds.
        let main: Int?
        let left: Int?
        let right: Int?
        let caseLevel: Int?

        var summary: String {
            if left != nil || right != nil {
                return [left.map { "L \($0)%" }, right.map { "R \($0)%" }, caseLevel.map { "Case \($0)%" }]
                    .compactMap { $0 }.joined(separator: " · ")
            }
            return main.map { "\($0)%" } ?? "—"
        }

        var lowest: Int? { [main, left, right].compactMap { $0 }.min() }
    }

    @Published private(set) var accessories: [Accessory] = []

    private let queue = DispatchQueue(label: "notchdeck.accessories")

    func showPreview(_ accessories: [Accessory]) {
        self.accessories = accessories
    }

    /// Reads levels in the background (system_profiler takes a second or two).
    func refresh(completion: (([Accessory]) -> Void)? = nil) {
        queue.async { [weak self] in
            var found = Self.hidAccessories()
            for accessory in Self.profilerAccessories() where !found.contains(where: { $0.name == accessory.name }) {
                found.append(accessory)
            }
            DispatchQueue.main.async {
                self?.accessories = found
                completion?(found)
            }
        }
    }

    /// Magic Mouse, Keyboard and Trackpad report `BatteryPercent` in the I/O Registry.
    private static func hidAccessories() -> [Accessory] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [Accessory] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let percent = property("BatteryPercent") as? Int, let name = property("Product") as? String else { continue }
            result.append(Accessory(name: name, symbol: symbol(for: name), main: percent, left: nil, right: nil, caseLevel: nil))
        }
        return result
    }

    /// AirPods and other audio devices: system_profiler knows left, right and case levels.
    private static func profilerAccessories() -> [Accessory] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = json["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var result: [Accessory] = []
        for section in sections {
            for list in [section["device_connected"], section["devices_connected"]].compactMap({ $0 as? [[String: Any]] }) {
                for entry in list {
                    for (name, value) in entry {
                        guard let info = value as? [String: Any] else { continue }
                        func level(_ key: String) -> Int? {
                            (info[key] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) }
                        }
                        let accessory = Accessory(name: name, symbol: symbol(for: name),
                                                  main: level("device_batteryLevelMain") ?? level("device_batteryLevel"),
                                                  left: level("device_batteryLevelLeft"),
                                                  right: level("device_batteryLevelRight"),
                                                  caseLevel: level("device_batteryLevelCase"))
                        if accessory.main != nil || accessory.left != nil || accessory.right != nil {
                            result.append(accessory)
                        }
                    }
                }
            }
        }
        return result
    }

    static func symbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("keyboard") { return "keyboard.fill" }
        if lower.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if lower.contains("mouse") { return "computermouse.fill" }
        if lower.contains("controller") { return "gamecontroller.fill" }
        return "headphones"
    }
}
