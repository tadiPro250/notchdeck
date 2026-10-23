import AudioToolbox
import CoreAudio

/// System output volume through CoreAudio, following the default output device.
final class VolumeControl: ObservableObject {
    @Published private(set) var level: Double = 0
    @Published private(set) var isMuted = false

    /// Called when the volume changes from outside the app (keyboard keys, Control Centre).
    var onExternalChange: ((Double, Bool) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var lastWrite = Date.distantPast

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private lazy var changeListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.read(notify: true)
    }
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.attach()
    }

    init() {
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress,
                                            .main, deviceListener)
        attach()
    }

    /// False for outputs macOS can't set a volume on (e.g. some HDMI and USB devices).
    var canSetVolume: Bool {
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &volumeAddress, &settable) == noErr && settable.boolValue
    }

    func set(_ value: Double) {
        lastWrite = Date()
        var volume = Float32(min(max(value, 0), 1))
        AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        level = Double(volume)
        if isMuted, volume > 0 { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        lastWrite = Date()
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        isMuted = muted
    }

    private func attach() {
        if device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &volumeAddress, .main, changeListener)
            AudioObjectRemovePropertyListenerBlock(device, &muteAddress, .main, changeListener)
        }
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, 0, nil, &size, &id)
        device = id
        AudioObjectAddPropertyListenerBlock(device, &volumeAddress, .main, changeListener)
        AudioObjectAddPropertyListenerBlock(device, &muteAddress, .main, changeListener)
        read(notify: false)
    }

    private func read(notify: Bool) {
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let hasVolume = AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume) == noErr
        var mute = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        let hasMute = AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &mute) == noErr

        let newLevel = hasVolume ? Double(volume) : level
        let newMuted = hasMute && mute != 0
        let changed = abs(newLevel - level) > 0.001 || newMuted != isMuted
        level = newLevel
        isMuted = newMuted
        if notify, changed, Date().timeIntervalSince(lastWrite) > 0.5 {
            onExternalChange?(newLevel, newMuted)
        }
    }
}
