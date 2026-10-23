import SwiftUI

struct ControlsView: View {
    let model: NotchModel
    let services: NotchServices

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 11) {
                SliderRows(volume: services.volume, brightness: services.brightness)
                TimerStrip(timer: services.timer)
                StatsRow(stats: services.stats)
            }
            .frame(width: 270)
            ActionGrid(model: model, actions: services.actions)
        }
    }
}

private struct SliderRows: View {
    @ObservedObject var volume: VolumeControl
    @ObservedObject var brightness: BrightnessControl

    var body: some View {
        VStack(spacing: 10) {
            LevelSlider(value: brightness.level, low: "sun.min.fill", high: "sun.max.fill",
                        enabled: brightness.isAvailable) { brightness.set($0) }
                .help(brightness.isAvailable ? "Brightness" : "Brightness works on the built-in display only")
            LevelSlider(value: volume.isMuted ? 0 : volume.level,
                        low: volume.isMuted ? "speaker.slash.fill" : "speaker.fill",
                        high: "speaker.wave.3.fill",
                        onLowTap: { volume.setMuted(!volume.isMuted) }) { volume.set($0) }
        }
    }
}

private struct TimerStrip: View {
    @ObservedObject var timer: FocusTimer
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(look.accent)
                .frame(width: 20)
            if timer.isActive {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(FocusTimer.clock(timer.remaining(at: context.date)))
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                }
                Spacer(minLength: 0)
                Button(timer.isPaused ? "Resume" : "Pause") { timer.togglePause() }
                    .buttonStyle(PillButtonStyle())
                Button("Stop") { timer.cancel() }
                    .buttonStyle(PillButtonStyle())
            } else {
                ForEach([5, 15, 25, 50], id: \.self) { minutes in
                    Button("\(minutes)m") { timer.start(minutes: Double(minutes)) }
                        .buttonStyle(PillButtonStyle())
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 26)
    }
}

struct StatsRow: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        HStack(spacing: 8) {
            StatGauge(label: "CPU", value: stats.cpu, detail: "\(ProcessInfo.processInfo.activeProcessorCount) cores")
            StatGauge(label: "RAM", value: stats.memory, detail: String(format: "%.1f GB", stats.memoryUsedGB))
            StatGauge(label: "Disk", value: stats.disk, detail: String(format: "%.0f GB free", stats.diskFreeGB))
        }
    }
}

struct StatGauge: View {
    let label: String
    let value: Double
    let detail: String
    @Environment(\.look) private var look

    private var tint: Color { value > 0.85 ? .red : (value > 0.65 ? .orange : look.accent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 9.5, weight: .bold))
                Spacer(minLength: 0)
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
            LevelBar(level: value, color: tint).frame(height: 4)
            Text(detail)
                .font(.system(size: 8.5))
                .foregroundStyle(look.theme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look.theme.surface))
    }
}

/// The system stats widget for the Home tab.
struct StatsGlance: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SYSTEM")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
            StatGauge(label: "CPU", value: stats.cpu, detail: "\(Int(stats.cpu * 100))% in use")
            StatGauge(label: "Memory", value: stats.memory, detail: String(format: "%.1f GB used", stats.memoryUsedGB))
            StatGauge(label: "Disk", value: stats.disk, detail: String(format: "%.0f GB free", stats.diskFreeGB))
        }
    }
}

private struct ActionGrid: View {
    let model: NotchModel
    @ObservedObject var actions: QuickActions

    var body: some View {
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

/// A Control Centre style capsule slider.
struct LevelSlider: View {
    let value: Double
    let low: String
    let high: String
    var enabled = true
    var onLowTap: (() -> Void)?
    let onChange: (Double) -> Void
    @StateObject private var dragValue = ViewState<Double?>(nil)
    @Environment(\.look) private var look

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
                    Capsule().fill(look.theme.surface)
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
    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .foregroundStyle(on ? Color.black : Color.white)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(on ? AnyShapeStyle(look.accent) : AnyShapeStyle(hovering.value ? Color.white.opacity(0.15) : look.theme.surface)))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { hovering.value = $0 }
        .animation(.easeOut(duration: 0.15), value: on)
    }
}
