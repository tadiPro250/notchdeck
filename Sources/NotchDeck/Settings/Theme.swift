import SwiftUI

/// A look for the expanded panel. Every theme starts pure black at the top edge so the panel
/// stays seamless with the hardware notch; the colour lives lower down.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    /// Gradient stops from the top edge (always black) to the bottom.
    let gradient: [Color]
    let accent: Color
    /// Fill for tiles, pills and slider tracks.
    let surface: Color
    let secondaryText: Color
    /// A soft glow behind the panel's lower half.
    let glow: Color?

    var background: LinearGradient {
        LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
    }

    static let midnight = Theme(
        id: "midnight", name: "Midnight",
        gradient: [.black, .black],
        accent: .white, surface: .white.opacity(0.09), secondaryText: .white.opacity(0.55), glow: nil)

    static let aurora = Theme(
        id: "aurora", name: "Aurora",
        gradient: [.black, .black, Color(red: 0.05, green: 0.16, blue: 0.2), Color(red: 0.12, green: 0.08, blue: 0.26)],
        accent: Color(red: 0.42, green: 0.95, blue: 0.82), surface: .white.opacity(0.1),
        secondaryText: Color(red: 0.7, green: 0.85, blue: 0.88).opacity(0.7),
        glow: Color(red: 0.3, green: 0.9, blue: 0.8))

    static let ember = Theme(
        id: "ember", name: "Ember",
        gradient: [.black, .black, Color(red: 0.2, green: 0.06, blue: 0.03), Color(red: 0.3, green: 0.1, blue: 0.02)],
        accent: Color(red: 1, green: 0.55, blue: 0.25), surface: .white.opacity(0.1),
        secondaryText: Color(red: 1, green: 0.82, blue: 0.7).opacity(0.65),
        glow: Color(red: 1, green: 0.4, blue: 0.15))

    static let ocean = Theme(
        id: "ocean", name: "Ocean",
        gradient: [.black, .black, Color(red: 0.02, green: 0.08, blue: 0.2), Color(red: 0.03, green: 0.13, blue: 0.32)],
        accent: Color(red: 0.4, green: 0.7, blue: 1), surface: .white.opacity(0.1),
        secondaryText: Color(red: 0.72, green: 0.82, blue: 1).opacity(0.65),
        glow: Color(red: 0.2, green: 0.5, blue: 1))

    static let forest = Theme(
        id: "forest", name: "Forest",
        gradient: [.black, .black, Color(red: 0.03, green: 0.14, blue: 0.07), Color(red: 0.06, green: 0.2, blue: 0.1)],
        accent: Color(red: 0.55, green: 0.9, blue: 0.45), surface: .white.opacity(0.1),
        secondaryText: Color(red: 0.75, green: 0.9, blue: 0.75).opacity(0.65),
        glow: Color(red: 0.35, green: 0.85, blue: 0.4))

    static let sakura = Theme(
        id: "sakura", name: "Sakura",
        gradient: [.black, .black, Color(red: 0.2, green: 0.05, blue: 0.13), Color(red: 0.28, green: 0.08, blue: 0.2)],
        accent: Color(red: 1, green: 0.55, blue: 0.75), surface: .white.opacity(0.1),
        secondaryText: Color(red: 1, green: 0.8, blue: 0.9).opacity(0.65),
        glow: Color(red: 1, green: 0.4, blue: 0.7))

    static let graphite = Theme(
        id: "graphite", name: "Graphite",
        gradient: [.black, .black, Color(white: 0.11), Color(white: 0.16)],
        accent: Color(red: 0.95, green: 0.78, blue: 0.35), surface: .white.opacity(0.1),
        secondaryText: .white.opacity(0.55), glow: nil)

    static let all: [Theme] = [.midnight, .aurora, .ember, .ocean, .forest, .sakura, .graphite]
}

/// The resolved look for the current moment, handed down the view tree.
struct Look {
    var theme: Theme
    var accent: Color
    var visualizer: VisualizerStyle
    var hudStyle: HUDStyle

    static let `default` = Look(theme: .midnight, accent: .white, visualizer: .bars, hudStyle: .wings)
}

private struct LookKey: EnvironmentKey {
    static let defaultValue = Look.default
}

extension EnvironmentValues {
    var look: Look {
        get { self[LookKey.self] }
        set { self[LookKey.self] = newValue }
    }
}
