import AppKit
import ApplicationServices

/// Catches the volume and brightness keys before macOS does, so the system's own HUD never
/// appears and the notch HUD is the only one. Needs Accessibility access (an active event tap).
final class MediaKeyInterceptor {
    enum Key {
        case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
        case keyboardUp, keyboardDown, keyboardToggle
    }

    /// Return true when the key was handled; the event is then swallowed. Return false to let
    /// macOS handle it as usual (e.g. a device whose volume can't be set).
    var handler: ((Key, _ fineStep: Bool) -> Bool)?

    private(set) var isRunning = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var permissionPoll: Timer?
    /// Keys whose key-down we swallowed, so their key-up is swallowed too.
    private var swallowed = Set<Int>()

    static var isTrusted: Bool { AXIsProcessTrusted() }

    func start(prompt: Bool) {
        guard !isRunning else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            install()
        } else {
            // Wait for the user to tick NotchDeck in System Settings, then start without a relaunch.
            permissionPoll?.invalidate()
            permissionPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.permissionPoll = nil
                self?.install()
            }
        }
    }

    func stop() {
        permissionPoll?.invalidate()
        permissionPoll = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isRunning = false
    }

    private func install() {
        let systemDefined = CGEventMask(1 << 14) // NX_SYSDEFINED: media and brightness keys
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: systemDefined,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isRunning = true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let code = (ns.data1 & 0xFFFF_0000) >> 16
        let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA

        // NX_KEYTYPE_* from IOKit/hidsystem/ev_keymap.h
        let key: Key
        switch code {
        case 0: key = .volumeUp
        case 1: key = .volumeDown
        case 7: key = .mute
        case 2: key = .brightnessUp
        case 3: key = .brightnessDown
        case 21: key = .keyboardUp
        case 22: key = .keyboardDown
        case 23: key = .keyboardToggle
        default: return Unmanaged.passUnretained(event)
        }

        let flags = ns.modifierFlags
        // Option alone + a media key opens the matching System Settings pane; leave that to macOS.
        if flags.contains(.option), !flags.contains(.shift) { return Unmanaged.passUnretained(event) }

        if isDown {
            if handler?(key, flags.contains([.option, .shift])) == true {
                swallowed.insert(code)
                return nil
            }
            swallowed.remove(code)
            return Unmanaged.passUnretained(event)
        }
        return swallowed.remove(code) != nil ? nil : Unmanaged.passUnretained(event)
    }
}
