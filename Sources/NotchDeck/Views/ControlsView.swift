import SwiftUI

struct ControlsView: View {
    let model: NotchModel
    @ObservedObject var volume: VolumeControl
    @ObservedObject var brightness: BrightnessControl
    @ObservedObject var actions: QuickActions

    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                LevelSlider(value: brightness.level, low: "sun.min.fill", high: "sun.max.fill",
                            enabled: brightness.isAvailable) { brightness.set($0) }
                LevelSlider(value: volume.isMuted ? 0 : volume.level,
                            low: volume.isMuted ? "speaker.slash.fill" : "speaker.fill",
                            high: "speaker.wave.3.fill",
                            onLowTap: { volume.setMuted(!volume.isMuted) }) { volume.set($0) }
                if !brightness.isAvailable {
                    Text("Brightness works on the built-in display only")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: 250)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ActionTile(symbol: "cup.and.saucer.fill", title: "Keep Awake", on: actions.keepAwake) {
                    actions.toggleKeepAwake()
                }
                ActionTile(symbol: "circle.lefthalf.filled", title: "Dark Mode", on: actions.darkMode) {
                    actions.toggleDarkMode()
                }
                ActionTile(symbol: "eye.slash.fill", title: "Hide Desktop", on: actions.desktopHidden) {
                    actions.toggleDesktopIcons()
                }
                ActionTile(symbol: "camera.viewfinder", title: "Screenshot", on: false) {
                    model.requestCollapse()
                    actions.screenshot()
                }
                ActionTile(symbol: "moon.zzz.fill", title: "Display Off", on: false) {
                    model.requestCollapse()
                    actions.sleepDisplay()
                }
                ActionTile(symbol: "lock.fill", title: "Lock", on: false) {
                    model.requestCollapse()
                    actions.lockScreen()
                }
            }
        }
    }
}

/// A Control Centre style capsule slider.
struct LevelSlider: View {
    let value: Double
    let low: String
    let high: String
    var enabled = true
    var onLowTap: (() -> Void)?
    let onChange: (Double) -> Void
    @StateObject private var dragValue = ViewState<Double?>(nil)

    var body: some View {
        let shown = dragValue.value ?? value
        HStack(spacing: 10) {
            Button { onLowTap?() } label: {
                Image(systemName: low)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .disabled(onLowTap == nil)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(Color.white)
                        .frame(width: max(geo.size.height, geo.size.width * shown))
                }
                .contentShape(Capsule())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let next = min(max(drag.location.x / max(geo.size.width, 1), 0), 1)
                        dragValue.value = next
                        onChange(next)
                    }
                    .onEnded { _ in dragValue.value = nil })
            }
            .frame(height: 24)
            Image(systemName: high)
                .frame(width: 20)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
        .opacity(enabled ? 1 : 0.35)
        .allowsHitTesting(enabled)
    }
}

struct ActionTile: View {
    let symbol: String
    let title: String
    let on: Bool
    let action: () -> Void
    @StateObject private var hovering = ViewState<Bool>(false)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .foregroundStyle(on ? Color.black : Color.white)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(on ? Color.white : Color.white.opacity(hovering.value ? 0.14 : 0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hovering.value = $0 }
        .animation(.easeOut(duration: 0.15), value: on)
    }
}
