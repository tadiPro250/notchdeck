import AppKit
import AudioToolbox
import CoreAudio
import IOKit

/// Audio outputs and inputs: switch the default output, and mute the microphone.
final class AudioDevices: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: AudioObjectID
        let name: String
        let transport: UInt32

        var symbol: String {
            let lower = name.lowercased()
            if lower.contains("airpods max") { return "airpodsmax" }
            if lower.contains("airpods pro") { return "airpodspro" }
            if lower.contains("airpods") { return "airpods" }
            switch transport {
            case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
            case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
            case kAudioDeviceTransportTypeUSB: return "cable.connector"
            default: return "hifispeaker.fill"
            }
        }
    }

    @Published private(set) var outputs: [Device] = []
    @Published private(set) var currentOutput: AudioObjectID = 0
    @Published private(set) var micMuted = false
    @Published private(set) var micName = "Microphone"

    /// Input volume before a mute done by zeroing the volume (for mics without a mute control).
    private var savedInputVolume: Float32?
    private var listener: AudioObjectPropertyListenerBlock?

    init(live: Bool = true) {
        guard live else { return }
        reload()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.reload() }
        listener = block
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
    }

    func showPreview(outputs: [Device], current: AudioObjectID) {
        self.outputs = outputs
        currentOutput = current
    }

    var currentOutputDevice: Device? { outputs.first { $0.id == currentOutput } }

    func select(_ device: Device) {
        var id = device.id
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioObjectID>.size), &id)
        currentOutput = device.id
    }

    func toggleMicMute() {
        guard let input = Self.defaultDevice(input: true) else { return }
        let target = !micMuted
        var mute = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        if AudioObjectIsPropertySettable(input, &mute, &settable) == noErr, settable.boolValue {
            var value: UInt32 = target ? 1 : 0
            AudioObjectSetPropertyData(input, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        } else {
            // No mute control: drop the input volume to zero and restore it afterwards.
            var volume = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                    mScope: kAudioDevicePropertyScopeInput,
                                                    mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout<Float32>.size)
            if target {
                var current: Float32 = 0
                AudioObjectGetPropertyData(input, &volume, 0, nil, &size, &current)
                savedInputVolume = current
                var zero: Float32 = 0
                AudioObjectSetPropertyData(input, &volume, 0, nil, size, &zero)
            } else {
                var restored = savedInputVolume ?? 0.75
                AudioObjectSetPropertyData(input, &volume, 0, nil, size, &restored)
            }
        }
        micMuted = target
    }

    private func reload() {
        outputs = Self.allDevices().filter { Self.hasStreams($0, input: false) }.map {
            Device(id: $0, name: Self.name(of: $0), transport: Self.transport(of: $0))
        }
        currentOutput = Self.defaultDevice(input: false) ?? 0
        if let input = Self.defaultDevice(input: true) {
            micName = Self.name(of: input)
            var mute = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput,
                                                  mElement: kAudioObjectPropertyElementMain)
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(input, &mute, 0, nil, &size, &value) == noErr {
                micMuted = value != 0 || savedInputVolume != nil && micMuted
            }
        }
    }

    // MARK: CoreAudio helpers

    static func defaultDevice(input: Bool) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    private static func allDevices() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
        return ids
    }

    private static func hasStreams(_ device: AudioObjectID, input: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of device: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else { return "Audio device" }
        return name.takeRetainedValue() as String
    }

    private static func transport(of device: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value
    }
}

/// Brightness of external monitors over DDC/CI, using the I²C channel Apple silicon exposes
/// through the private IOAVService calls (the approach MonitorControl and m1ddc use).
final class ExternalDisplays: ObservableObject {
    struct Display: Identifiable, Equatable {
        let id: Int
        let name: String
        var brightness: Double
        fileprivate let service: CFTypeRef

        static func == (a: Display, b: Display) -> Bool { a.id == b.id && a.brightness == b.brightness && a.name == b.name }
    }

    @Published private(set) var displays: [Display] = []

    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias Write = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    private typealias Read = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    private var create: Create?
    private var write: Write?
    private var read: Read?
    private let queue = DispatchQueue(label: "notchdeck.ddc")
    private var pending: [Int: DispatchWorkItem] = [:]

    init(live: Bool = true) {
        guard live, let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return }
        create = dlsym(handle, "IOAVServiceCreateWithService").map { unsafeBitCast($0, to: Create.self) }
        write = dlsym(handle, "IOAVServiceWriteI2C").map { unsafeBitCast($0, to: Write.self) }
        read = dlsym(handle, "IOAVServiceReadI2C").map { unsafeBitCast($0, to: Read.self) }
        reload()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.reload() }
    }

    func reload() {
        guard let create else { return }
        queue.async { [weak self] in
            guard let self else { return }
            var found: [Display] = []
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator)
                    == KERN_SUCCESS else { return }
            defer { IOObjectRelease(iterator) }
            var index = 0
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String
                guard location == "External", let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue()
                else { continue }
                index += 1
                let level = self.readBrightness(service) ?? 0.5
                found.append(Display(id: index, name: index == 1 ? "External display" : "External display \(index)",
                                     brightness: level, service: service))
            }
            DispatchQueue.main.async { self.displays = found }
        }
    }

    func set(_ display: Display, brightness: Double) {
        guard let index = displays.firstIndex(where: { $0.id == display.id }) else { return }
        displays[index].brightness = brightness
        // DDC is slow; coalesce slider drags.
        pending[display.id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.writeVCP(display.service, code: 0x10, value: UInt16((brightness * 100).rounded()))
        }
        pending[display.id] = work
        queue.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    func step(by delta: Double) {
        for display in displays {
            set(display, brightness: min(max(display.brightness + delta, 0), 1))
        }
    }

    private func writeVCP(_ service: CFTypeRef, code: UInt8, value: UInt16) {
        guard let write else { return }
        var packet: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = packet[0..<5].reduce(0x6E ^ 0x51) { $0 ^ $1 }
        for _ in 0..<2 {
            _ = packet.withUnsafeMutableBytes { write(service, 0x37, 0x51, $0.baseAddress!, 6) }
            usleep(10_000)
        }
    }

    private func readBrightness(_ service: CFTypeRef) -> Double? {
        guard let write, let read else { return nil }
        var request: [UInt8] = [0x82, 0x01, 0x10, 0]
        request[3] = request[0..<3].reduce(0x6E ^ 0x51) { $0 ^ $1 }
        _ = request.withUnsafeMutableBytes { write(service, 0x37, 0x51, $0.baseAddress!, 4) }
        usleep(50_000)
        var reply = [UInt8](repeating: 0, count: 12)
        let result = reply.withUnsafeMutableBytes { read(service, 0x37, 0x51, $0.baseAddress!, 12) }
        guard result == kIOReturnSuccess else { return nil }
        let maximum = Double(UInt16(reply[6]) << 8 | UInt16(reply[7]))
        let current = Double(UInt16(reply[8]) << 8 | UInt16(reply[9]))
        return maximum > 0 ? current / maximum : nil
    }
}

/// Keyboard backlight through the private CoreBrightness `KeyboardBrightnessClient`.
final class KeyboardBacklight: ObservableObject {
    @Published private(set) var level: Double = 0
    @Published private(set) var isAvailable = false

    private var client: NSObject?
    private var keyboardID: UInt64 = 0
    private typealias GetFn = @convention(c) (NSObject, Selector, UInt64) -> Float
    private typealias SetFn = @convention(c) (NSObject, Selector, Float, UInt64) -> Bool
    private var getter: GetFn?
    private var setter: SetFn?
    private var savedLevel: Double = 0.5

    init(live: Bool = true) {
        guard live,
              dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return }
        let client = type.init()
        let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard client.responds(to: idsSelector),
              let ids = client.perform(idsSelector)?.takeRetainedValue() as? [NSNumber], let first = ids.first else { return }
        keyboardID = first.uint64Value
        let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")
        guard let getIMP = client.method(for: getSelector), let setIMP = client.method(for: setSelector) else { return }
        getter = unsafeBitCast(getIMP, to: GetFn.self)
        setter = unsafeBitCast(setIMP, to: SetFn.self)
        self.client = client
        isAvailable = true
        refresh()
    }

    func refresh() {
        guard let client, let getter else { return }
        level = Double(getter(client, NSSelectorFromString("brightnessForKeyboard:"), keyboardID))
    }

    func set(_ value: Double) {
        guard let client, let setter else { return }
        let clamped = min(max(value, 0), 1)
        _ = setter(client, NSSelectorFromString("setBrightness:forKeyboard:"), Float(clamped), keyboardID)
        level = clamped
    }

    func toggle() {
        if level > 0.01 {
            savedLevel = level
            set(0)
        } else {
            set(savedLevel)
        }
    }
}
