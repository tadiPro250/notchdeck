import SwiftUI

struct ControlsView: View {
    let model: NotchModel
    let services: NotchServices

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 9) {
                SliderRows(volume: services.volume, brightness: services.brightness,
                           displays: services.displays, keyboard: services.keyboard)
                AudioRow(audio: services.audio)
            }
            .frame(width: 300)
            ActionGrid(model: model, actions: services.actions, audio: services.audio)
        }
    }
}

private struct SliderRows: View {
    @ObservedObject var volume: VolumeControl
    @ObservedObject var brightness: BrightnessControl
    @ObservedObject var displays: ExternalDisplays
    @ObservedObject var keyboard: KeyboardBacklight

    var body: some View {
        VStack(spacing: 8) {
            if brightness.isAvailable || displays.displays.isEmpty {
                LevelSlider(value: brightness.level, low: "sun.min.fill", high: "sun.max.fill",
                            enabled: brightness.isAvailable) { brightness.set($0) }
                    .help("Built-in display")
            }
            ForEach(displays.displays) { display in
                LevelSlider(value: display.brightness, low: "display", high: "sun.max.fill") {
                    displays.set(display, brightness: $0)
                }
                .help(display.name)
            }
            if keyboard.isAvailable {
                LevelSlider(value: keyboard.level, low: "keyboard", high: "keyboard.fill",
                            onLowTap: { keyboard.toggle() }) { keyboard.set($0) }
                    .help("Keyboard backlight")
            }
            LevelSlider(value: volume.isMuted ? 0 : volume.level,
                        low: volume.isMuted ? "speaker.slash.fill" : "speaker.fill",
                        high: "speaker.wave.3.fill",
                        onLowTap: { volume.setMuted(!volume.isMuted) }) { volume.set($0) }
        }
    }
}

/// Output device picker and microphone mute.
private struct AudioRow: View {
    @ObservedObject var audio: AudioDevices
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(audio.outputs) { device in
                    Button {
                        audio.select(device)
                    } label: {
                        Label(device.name, systemImage: device.id == audio.currentOutput ? "checkmark" : device.symbol)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: audio.currentOutputDevice?.symbol ?? "hifispeaker.fill")
                    Text(audio.currentOutputDevice?.name ?? "Output")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(look.theme.surface))
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Sound output")
            Button { audio.toggleMicMute() } label: {
                Image(systemName: audio.micMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 34, height: 26)
                    .background(Capsule().fill(audio.micMuted ? Color.red.opacity(0.85) : look.theme.surface))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(audio.micMuted ? "Unmute \(audio.micName)" : "Mute \(audio.micName)")
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

/// The system stats widget for the Home tab: a 2×2 grid of gauges.
struct StatsGlance: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SYSTEM")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                StatGauge(label: "CPU", value: stats.cpu, detail: "\(ProcessInfo.processInfo.activeProcessorCount) cores")
                StatGauge(label: "GPU", value: stats.gpu, detail: stats.gpuCores.map { "\($0) cores" } ?? "GPU")
                StatGauge(label: "RAM", value: stats.memory, detail: String(format: "%.1f GB", stats.memoryUsedGB))
                StatGauge(label: "Disk", value: stats.disk, detail: String(format: "%.0f GB free", stats.diskFreeGB))
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ActionGrid: View {
    let model: NotchModel
    @ObservedObject var actions: QuickActions
    @ObservedObject var audio: AudioDevices

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ActionTile(symbol: "cup.and.saucer.fill", title: "Keep Awake", on: actions.keepAwake) {
                actions.toggleKeepAwake()
            }
            ActionTile(symbol: "circle.lefthalf.filled", title: "Dark Mode", on: actions.darkMode) {
                actions.toggleDarkMode()
            }
            ActionTile(symbol: "eye.slash.fill", title: "Hide Desktop", on: actions.desktopHidden) {
                actions.toggleDesktopIcons()
            }
            ActionTile(symbol: audio.micMuted ? "mic.slash.fill" : "mic.fill", title: "Mic Mute", on: audio.micMuted) {
                audio.toggleMicMute()
            }
            ActionTile(symbol: "camera.viewfinder", title: "Screenshot", on: false) {
                model.requestCollapse()
                actions.screenshot()
            }
            ActionTile(symbol: "moon.zzz.fill", title: "Display Off", on: false) {
                model.requestCollapse()
                actions.sleepDisplay()
            }
            ActionTile(symbol: "powersleep", title: "Sleep", on: false) {
                model.requestCollapse()
                actions.sleepMac()
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
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
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
