import SwiftUI
import UniformTypeIdentifiers

/// The notch outline: flared "ears" at the top corners and rounded bottom corners. With no ears
/// (an island) it is a rounded rectangle.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var island = false

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if island {
            return Path(roundedRect: rect, cornerRadius: min(bottomRadius, rect.height / 2), style: .continuous)
        }
        let t = topRadius
        let b = min(bottomRadius, rect.height / 2, (rect.width - 2 * t) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                          control: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                          control: CGPoint(x: rect.minX + t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                          control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    let services: NotchServices
    @ObservedObject var settings: AppSettings
    @ObservedObject var player: NowPlaying

    private var look: Look {
        Look(theme: settings.theme, accent: settings.accent(artwork: player.artworkAccent),
             visualizer: settings.visualizer, hudStyle: settings.hudStyle)
    }

    var body: some View {
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius, island: model.isIsland)
        let look = look
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.islandGap)
            ZStack(alignment: .top) {
                if model.isExpanded {
                    PanelBackground(settings: settings, look: look, shape: shape, notchHeight: model.geometry.notchSize.height)
                        .transition(.opacity.animation(.easeOut(duration: 0.2)))
                } else {
                    shape.fill(Color.black)
                }
                content
                    .padding(.horizontal, model.topRadius)
            }
            .frame(width: model.shapeSize.width, height: model.shapeSize.height, alignment: .top)
            .clipShape(shape)
            // A glass edge: catches the light along the bottom, invisible where it meets the notch.
            .overlay(shape.stroke(LinearGradient(colors: [.clear, .white.opacity(model.isExpanded && settings.glass ? 0.22 : 0)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(shape.stroke(look.accent.opacity(model.dropTargeted ? 0.7 : 0), lineWidth: 1.5))
            .overlay(shape.stroke(Color.white.opacity(model.isIsland && !model.isExpanded ? 0.08 : 0), lineWidth: 1))
            .shadow(color: .black.opacity((model.isExpanded || model.isIsland) && settings.shadow ? 0.5 : 0),
                    radius: model.isExpanded ? 24 : 12, y: model.isExpanded ? 12 : 4)
            .onDrop(of: [UTType.fileURL], isTargeted: $model.dropTargeted) { providers in
                services.tray.add(providers: providers)
                model.tab = .tray
                return true
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .environment(\.look, look)
        .animation(springFor(model), value: model.presentation)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: model.hovering)
    }

    /// Opening overshoots a little and settles back, like a popover; closing tucks in quicker
    /// with a smaller bounce. Without "Bouncy animation" both are critically damped.
    private func springFor(_ model: NotchModel) -> Animation {
        guard settings.bouncyAnimation else { return .spring(response: 0.38, dampingFraction: 1) }
        return model.isExpanded ? .spring(response: 0.5, dampingFraction: 0.68)
                                : .spring(response: 0.4, dampingFraction: 0.8)
    }

    @ViewBuilder
    private var content: some View {
        let notch = model.geometry.notchSize
        switch model.presentation {
        case .expanded:
            ExpandedView(model: model, services: services, settings: settings)
                .transition(.asymmetric(
                    insertion: .popIn(scale: 0.9).animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.07)),
                    removal: .popIn(scale: 0.94).animation(.easeIn(duration: 0.12))))
        case .ringing(let ringing):
            RingingView(ringing: ringing, clock: services.clock, notch: notch)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
        case .live:
            LiveActivityView(player: player, notch: notch, privacy: model.privacy)
                .transition(.opacity)
        case .timer:
            TimerActivityView(timer: services.timer, notch: notch)
                .transition(.opacity)
        case .stopwatch:
            StopwatchActivityView(clock: services.clock, notch: notch)
                .transition(.opacity)
        case .countdown:
            if let event = model.countdown {
                CountdownActivityView(event: event, notch: notch)
                    .transition(.opacity)
            }
        case .download:
            DownloadActivityView(downloads: services.downloads, notch: notch)
                .transition(.opacity)
        case .privacy:
            PrivacyActivityView(privacy: model.privacy, notch: notch)
                .transition(.opacity)
        case .activity(let activity):
            DropActivityView(activity: activity, notch: notch)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
        case .hud(let hud):
            HUDView(hud: hud, notch: notch)
                .transition(.opacity)
        case .collapsed:
            Color.clear
        }
    }
}

/// The open panel's fill: the theme (as tinted glass, or solid), or the user's photos. The top
/// edge is always pure black so the panel stays seamless with the hardware notch.
private struct PanelBackground: View {
    @ObservedObject var settings: AppSettings
    let look: Look
    let shape: NotchShape
    let notchHeight: CGFloat

    var body: some View {
        let photos = settings.backgroundPhotos
        ZStack {
            if settings.backgroundMode != .theme, !photos.isEmpty {
                Color.black
                Slideshow(paths: settings.backgroundMode == .photo ? [photos[0]] : photos,
                          interval: settings.slideshowInterval)
                    .blur(radius: settings.backgroundBlur)
                    .scaleEffect(settings.backgroundBlur > 0 ? 1.08 : 1)
                Color.black.opacity(settings.backgroundDim)
            } else if settings.glass {
                Rectangle().fill(.ultraThinMaterial)
                look.theme.background.opacity(1 - settings.glassClarity * 0.6)
                Color.black.opacity(0.25 * (1 - settings.glassClarity))
            } else {
                look.theme.background
            }
            if let glow = look.theme.glow, settings.backgroundMode == .theme || photos.isEmpty {
                RadialGradient(colors: [glow.opacity(0.22), .clear], center: .bottom, startRadius: 0, endRadius: 340)
            }
            // Black under the notch, fading out below it.
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: 0.5),
                                   .init(color: .black.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: notchHeight * 2.2)
                .frame(maxHeight: .infinity, alignment: .top)
            // A faint sheen across the upper glass.
            LinearGradient(colors: [.white.opacity(settings.glass ? 0.05 : 0), .clear], startPoint: .top, endPoint: .center)
        }
        .clipShape(shape)
    }
}

struct PopIn: ViewModifier {
    let active: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: active ? 10 : 0)
            .scaleEffect(active ? scale : 1, anchor: .top)
            .opacity(active ? 0 : 1)
    }
}

extension AnyTransition {
    /// Blurs and scales in from the top, the way system popovers bloom.
    static func popIn(scale: CGFloat) -> AnyTransition {
        .modifier(active: PopIn(active: true, scale: scale), identity: PopIn(active: false, scale: scale))
    }
}

// MARK: Closed-notch states

/// Two wings either side of the hardware notch.
private struct Wings<Left: View, Right: View>: View {
    let notch: CGSize
    let width: CGFloat
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: width)
            Spacer(minLength: notch.width)
            right.frame(width: width)
        }
        .frame(height: notch.height)
    }
}

/// Collapsed, while music plays: artwork to the left of the notch, a visualiser to the right.
struct LiveActivityView: View {
    @ObservedObject var player: NowPlaying
    let notch: CGSize
    var privacy = PrivacyState()
    @Environment(\.look) private var look

    var body: some View {
        Wings(notch: notch, width: notch.height + 4) {
            ArtworkView(image: player.artwork, size: notch.height - 12, corner: 5)
        } right: {
            ZStack(alignment: .topTrailing) {
                if look.visualizer == .off {
                    Image(systemName: "music.note")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(look.accent)
                } else {
                    Visualizer(style: look.visualizer, color: look.accent)
                }
                if privacy.any {
                    PrivacyDots(privacy: privacy).scaleEffect(0.7).offset(x: 6, y: -9)
                }
            }
        }
    }
}

struct Visualizer: View {
    let style: VisualizerStyle
    let color: Color
    var bars = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            switch style {
            case .bars, .off:
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<bars, id: \.self) { i in
                        Capsule()
                            .fill(color)
                            .frame(width: 3, height: 4 + 10 * Self.level(t, i))
                    }
                }
                .frame(height: 14)
            case .dots:
                HStack(spacing: 2.5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(color)
                            .frame(width: 4, height: 4)
                            .scaleEffect(0.6 + 0.6 * Self.level(t, i))
                            .opacity(0.5 + 0.5 * Self.level(t, i))
                    }
                }
            case .wave:
                Canvas { ctx, size in
                    var path = Path()
                    let mid = size.height / 2
                    for step in 0...20 {
                        let x = size.width * Double(step) / 20
                        let envelope = sin(Double(step) / 20 * .pi)
                        let y = mid + sin(t * 7 + Double(step) * 0.75) * mid * 0.8 * envelope
                            * (0.6 + 0.4 * sin(t * 2.3))
                        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                    }
                    ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                .frame(width: 20, height: 14)
            }
        }
    }

    static func level(_ t: Double, _ i: Int) -> Double {
        abs(sin(t * (3.1 + Double(i) * 1.37) + Double(i) * 0.9))
    }
}

/// Collapsed, while a timer runs: a progress ring on the left, the time left on the right.
struct TimerActivityView: View {
    @ObservedObject var timer: FocusTimer
    let notch: CGSize
    @Environment(\.look) private var look

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Wings(notch: notch, width: 62) {
                ProgressRing(progress: timer.progress(at: context.date), color: look.accent,
                             symbol: timer.isPaused ? "pause.fill" : "timer")
            } right: {
                Text(FocusTimer.clock(timer.remaining(at: context.date)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(timer.isPaused ? .white.opacity(0.5) : .white)
            }
        }
    }
}

struct StopwatchActivityView: View {
    @ObservedObject var clock: ClockCenter
    let notch: CGSize
    @Environment(\.look) private var look

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            Wings(notch: notch, width: 74) {
                Image(systemName: clock.stopwatchRunning ? "stopwatch.fill" : "stopwatch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(clock.stopwatchRunning ? look.accent : .white.opacity(0.5))
            } right: {
                Text(ClockCenter.stopwatchText(clock.stopwatchElapsed(at: context.date)))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(clock.stopwatchRunning ? .white : .white.opacity(0.5))
            }
        }
    }
}

/// Collapsed, in the ten minutes before a meeting.
struct CountdownActivityView: View {
    let event: CalendarEvent
    let notch: CGSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            Wings(notch: notch, width: 118) {
                HStack(spacing: 6) {
                    Circle().fill(event.color).frame(width: 7, height: 7)
                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } right: {
                Text("in \(max(Int(ceil(event.start.timeIntervalSince(context.date) / 60)), 0)) min")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(event.color)
            }
            .foregroundStyle(.white)
        }
    }
}

struct DownloadActivityView: View {
    @ObservedObject var downloads: DownloadWatcher
    let notch: CGSize
    @Environment(\.look) private var look

    var body: some View {
        let download = downloads.active.first
        Wings(notch: notch, width: 62) {
            ProgressRing(progress: download?.fraction ?? 0, color: look.accent, symbol: "arrow.down",
                         indeterminate: download?.fraction == nil)
        } right: {
            Group {
                if let fraction = download?.fraction {
                    Text("\(Int(fraction * 100))%")
                } else {
                    Text(DownloadWatcher.sizeText(download?.bytes ?? 0))
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
        }
    }
}

struct PrivacyActivityView: View {
    let privacy: PrivacyState
    let notch: CGSize

    var body: some View {
        Wings(notch: notch, width: 18) {
            Color.clear
        } right: {
            PrivacyDots(privacy: privacy, vertical: true)
        }
    }
}

struct PrivacyDots: View {
    let privacy: PrivacyState
    var vertical = false

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
        layout {
            if privacy.camera { Circle().fill(Color.green).frame(width: 6, height: 6).help("Camera in use") }
            if privacy.microphone { Circle().fill(Color.orange).frame(width: 6, height: 6).help("Microphone in use") }
            if privacy.screen { Circle().fill(Color.purple).frame(width: 6, height: 6).help("Screen being recorded") }
            if privacy.micMuted {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.red)
                    .help("Microphone muted")
            }
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let color: Color
    let symbol: String
    var indeterminate = false

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
            if indeterminate {
                TimelineView(.animation) { context in
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 360))
                }
            } else {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: 18, height: 18)
    }
}

/// An alarm or a finished timer: stays until you snooze or stop it.
struct RingingView: View {
    let ringing: Ringing
    @ObservedObject var clock: ClockCenter
    let notch: CGSize
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height)
            HStack(spacing: 12) {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    Image(systemName: ringing.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(look.accent)
                        .rotationEffect(.degrees(sin(t * 28) * 12))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(look.accent.opacity(0.18)))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(ringing.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(ringing.detail)
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                Button("Snooze") { clock.snooze() }
                    .buttonStyle(RingButtonStyle(fill: Color.white.opacity(0.14), text: .white))
                Button("Stop") { clock.stopRinging() }
                    .buttonStyle(RingButtonStyle(fill: look.accent, text: .black))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 62)
        }
    }
}

private struct RingButtonStyle: ButtonStyle {
    let fill: Color
    let text: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(fill.opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Capsule())
    }
}

/// Collapsed, for a moment: a card that drops down from the notch (charging, AirPods, meetings).
struct DropActivityView: View {
    let activity: ActivityState
    let notch: CGSize

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height)
            HStack(spacing: 12) {
                ZStack {
                    if let progress = activity.progress {
                        Circle().stroke(activity.tint.opacity(0.25), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(activity.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    } else {
                        Circle().fill(activity.tint.opacity(0.2))
                    }
                    Image(systemName: activity.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(activity.tint)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(activity.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let detail = activity.detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
    }
}

/// Collapsed, right after a volume, brightness or keyboard-light change.
struct HUDView: View {
    let hud: HUDState
    let notch: CGSize
    @Environment(\.look) private var look

    var body: some View {
        switch look.hudStyle {
        case .wings: wings
        case .bar: bar
        }
    }

    private var icon: some View {
        Image(systemName: hud.symbol)
            .font(.system(size: 13, weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
    }

    private var percent: some View {
        Text("\(Int((hud.level * 100).rounded()))")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .frame(width: 24, alignment: .trailing)
    }

    private var wings: some View {
        Wings(notch: notch, width: 100) {
            icon
        } right: {
            HStack(spacing: 7) {
                LevelBar(level: hud.level, color: look.accent).frame(width: 56, height: 5)
                percent
            }
        }
        .foregroundStyle(.white)
    }

    private var bar: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height)
            HStack(spacing: 10) {
                icon.frame(width: 18)
                LevelBar(level: hud.level, color: look.accent).frame(height: 6)
                percent
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 24)
        }
    }
}

struct LevelBar: View {
    let level: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(color).frame(width: max(geo.size.height, geo.size.width * level))
            }
        }
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.22), Color(white: 0.1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
