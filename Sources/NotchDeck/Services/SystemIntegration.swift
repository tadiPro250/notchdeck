import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A system-wide keyboard shortcut (Carbon hot keys need no Accessibility permission).
final class GlobalHotKey {
    var action: (() -> Void)?

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(_ choice: HotKeyChoice) {
        unregister()
        guard let (keyCode, modifiers) = choice.carbon else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let me = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { me.action?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x4E44_4B31), id: 1),
                            GetApplicationEventTarget(), 0, &reference)
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil
        handler = nil
    }
}

/// A SkyLight space with an absolute level, which floats above the ordinary and full-screen spaces.
/// A window moved into one is drawn over everything below that level, on every display. This is
/// the technique boring.notch and Atoll use for their lock-screen widgets.
final class FloatingSpace {
    /// Absolute space levels, from SkyLight's own ordering. 300 is the screen lock itself.
    enum Level: Int32 {
        /// Over normal and full-screen spaces, but under the screen lock and the security agent,
        /// so nothing in it can be seen or clicked while the Mac is locked.
        case aboveFullScreen = 1
        /// Over the screen lock: the lock-screen player.
        case aboveScreenLock = 400
    }

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private var connection: Int32 = 0
    private var space: Int32 = 0
    private var addWindows: AddWindows?

    init(level: Level) {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let main = dlsym(handle, "SLSMainConnectionID"), let create = dlsym(handle, "SLSSpaceCreate"),
              let setLevel = dlsym(handle, "SLSSpaceSetAbsoluteLevel"), let show = dlsym(handle, "SLSShowSpaces"),
              let add = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return }
        connection = unsafeBitCast(main, to: MainConnection.self)()
        space = unsafeBitCast(create, to: SpaceCreate.self)(connection, 1, 0)
        _ = unsafeBitCast(setLevel, to: SpaceSetLevel.self)(connection, space, level.rawValue)
        _ = unsafeBitCast(show, to: ShowSpaces.self)(connection, [space] as CFArray)
        addWindows = unsafeBitCast(add, to: AddWindows.self)
    }

    var isAvailable: Bool { addWindows != nil && space != 0 }

    /// Moves `window` into the space. It must already be on screen (it needs a window number).
    func delegate(_ window: NSWindow) {
        guard let addWindows, window.windowNumber > 0 else { return }
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }
}

/// Checks a GitHub repository's latest release against this build's version.
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate, available(version: String, url: URL), failed(String)
    }

    @Published private(set) var state: State = .idle

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func check(repository: String) {
        let repo = repository.trimmingCharacters(in: .whitespaces)
        guard repo.contains("/"), let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            state = .failed("Set a repository like owner/notchdeck")
            return
        }
        state = .checking
        Task { [weak self] in
            struct Release: Decodable { let tag_name: String; let html_url: String }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let release = try JSONDecoder().decode(Release.self, from: data)
                let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                await MainActor.run {
                    if latest.compare(Self.currentVersion, options: .numeric) == .orderedDescending,
                       let page = URL(string: release.html_url) {
                        self?.state = .available(version: latest, url: page)
                    } else {
                        self?.state = .upToDate
                    }
                }
            } catch {
                await MainActor.run { self?.state = .failed("Couldn't reach GitHub") }
            }
        }
    }
}
