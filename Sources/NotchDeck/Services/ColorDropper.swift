import AppKit
import SwiftUI

struct SavedColor: Codable, Identifiable, Equatable {
    var id = UUID()
    var hex: String
    var date = Date()

    var color: Color { Color(hex: hex) ?? .white }
}

/// Picks a colour from anywhere on screen with the system loupe, shows it in the notch, copies the
/// hex and keeps a palette of saved colours.
final class ColorDropper: ObservableObject {
    @Published private(set) var saved: [SavedColor] = []
    @Published private(set) var last: String?

    /// Called with the hex after a pick, and whether it went into the palette.
    var onPicked: ((String, Bool) -> Void)?

    private let settings: AppSettings
    private let defaults: UserDefaults
    private var sampler: NSColorSampler?

    init(settings: AppSettings, live: Bool = true) {
        self.settings = settings
        defaults = live ? .standard : UserDefaults(suiteName: "com.premprateek.notchdeck.previews") ?? .standard
        if live, let data = defaults.data(forKey: "savedColors"),
           let colors = try? JSONDecoder().decode([SavedColor].self, from: data) {
            saved = colors
        }
        last = saved.first?.hex
    }

    /// Shows the magnifier; Esc cancels. `then` runs afterwards either way.
    func pick(then: (() -> Void)? = nil) {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] color in
            DispatchQueue.main.async {
                defer { then?() }
                guard let self else { return }
                self.sampler = nil
                guard let color, let hex = Self.hex(color) else { return }
                self.last = hex
                if self.settings.colorCopyOnPick { Self.copy(hex) }
                let save = self.settings.colorAutoSave
                if save { self.save(hex) }
                self.onPicked?(hex, save)
            }
        }
    }

    /// Makes a saved colour the one on show (and copies it).
    func select(_ hex: String) {
        last = hex
        Self.copy(hex)
    }

    var isSaved: Bool { last.map { hex in saved.contains { $0.hex == hex } } ?? false }

    func save(_ hex: String) {
        saved.removeAll { $0.hex == hex }
        saved.insert(SavedColor(hex: hex), at: 0)
        if saved.count > 48 { saved.removeLast(saved.count - 48) }
        persist()
    }

    func remove(_ color: SavedColor) {
        saved.removeAll { $0.id == color.id }
        persist()
    }

    func clear() {
        saved = []
        persist()
    }

    func showPreview(_ hexes: [String]) {
        saved = hexes.map { SavedColor(hex: $0) }
        last = hexes.first
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(saved), forKey: "savedColors")
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func hex(_ color: NSColor) -> String? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    /// "rgb(255, 111, 168)" and "hsl(335, 100%, 72%)".
    static func formats(_ hex: String) -> (rgb: String, hsl: String) {
        guard let color = Color(hex: hex), let c = NSColor(color).usingColorSpace(.sRGB) else { return ("", "") }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let maxC = max(r, g, b), minC = min(r, g, b)
        let l = (maxC + minC) / 2
        var h: CGFloat = 0, s: CGFloat = 0
        if maxC != minC {
            let d = maxC - minC
            s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
            switch maxC {
            case r: h = (g - b) / d + (g < b ? 6 : 0)
            case g: h = (b - r) / d + 2
            default: h = (r - g) / d + 4
            }
            h /= 6
        }
        return (String(format: "rgb(%d, %d, %d)", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())),
                String(format: "hsl(%d, %d%%, %d%%)", Int((h * 360).rounded()), Int((s * 100).rounded()), Int((l * 100).rounded())))
    }

    /// Black or white, whichever reads better on the colour.
    static func ink(on hex: String) -> Color {
        guard let color = Color(hex: hex), let c = NSColor(color).usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luminance > 0.6 ? .black : .white
    }
}
