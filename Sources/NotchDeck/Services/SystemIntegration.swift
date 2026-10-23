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

/// Shows a window on the lock screen by moving it into a SkyLight space with a very high
/// absolute level — the technique boring.notch and Atoll use for their lock-screen widgets.
final class LockScreenPresenter {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private var connection: Int32 = 0
    private var space: Int32 = 0
    private var addWindows: AddWindows?

    init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let main = dlsym(handle, "SLSMainConnectionID"), let create = dlsym(handle, "SLSSpaceCreate"),
              let level = dlsym(handle, "SLSSpaceSetAbsoluteLevel"), let show = dlsym(handle, "SLSShowSpaces"),
              let add = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return }
        connection = unsafeBitCast(main, to: MainConnection.self)()
        space = unsafeBitCast(create, to: SpaceCreate.self)(connection, 1, 0)
        _ = unsafeBitCast(level, to: SpaceSetLevel.self)(connection, space, 400)
        _ = unsafeBitCast(show, to: ShowSpaces.self)(connection, [space] as CFArray)
        addWindows = unsafeBitCast(add, to: AddWindows.self)
    }

    var isAvailable: Bool { addWindows != nil && space != 0 }

    func delegate(_ window: NSWindow) {
        guard let addWindows else { return }
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
