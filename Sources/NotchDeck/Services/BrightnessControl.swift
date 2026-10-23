import AppKit
import CoreGraphics

/// Built-in display brightness through the private DisplayServices framework (what the
/// brightness keys use on Apple silicon). External displays need DDC and are not covered.
final class BrightnessControl: ObservableObject {
    @Published private(set) var level: Double = 0
    @Published private(set) var isAvailable = false

    /// Called when brightness changes from outside the app (keys, auto-brightness, Control Centre).
    var onExternalChange: ((Double) -> Void)?

    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var getter: Getter?
    private var setter: Setter?
    private var display: CGDirectDisplayID = 0
    private var timer: Timer?
    private var lastWrite = Date.distantPast

    init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) {
            if let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
                getter = unsafeBitCast(symbol, to: Getter.self)
            }
            if let symbol = dlsym(handle, "DisplayServicesSetBrightness") {
                setter = unsafeBitCast(symbol, to: Setter.self)
            }
        }
        refreshDisplay()
        // DisplayServices has no public change notification, so poll gently.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.read(notify: true) }
    }

    func refreshDisplay() {
        display = Self.builtInDisplay() ?? CGMainDisplayID()
        read(notify: false)
    }

    func set(_ value: Double) {
        guard let setter else { return }
        lastWrite = Date()
        let clamped = Float(min(max(value, 0), 1))
        if setter(display, clamped) == 0 { level = Double(clamped) }
    }

    private func read(notify: Bool) {
        guard let getter else {
            isAvailable = false
            return
        }
        var value: Float = 0
        guard getter(display, &value) == 0 else {
            if isAvailable { isAvailable = false }
            return
        }
        if !isAvailable { isAvailable = true }
        let newLevel = Double(value)
        guard abs(newLevel - level) > 0.004 else { return }
        level = newLevel
        if notify, Date().timeIntervalSince(lastWrite) > 0.6 {
            onExternalChange?(newLevel)
        }
    }

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }
}
