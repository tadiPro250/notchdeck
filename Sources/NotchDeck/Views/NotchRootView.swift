import SwiftUI
import UniformTypeIdentifiers

/// The notch outline: flared "ears" at the top corners and rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
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
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)
        let look = look
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if model.isExpanded {
                    shape.fill(look.theme.background)
                    if let glow = look.theme.glow {
                        RadialGradient(colors: [glow.opacity(0.22), .clear], center: .bottom,
                                       startRadius: 0, endRadius: 320)
                    }
                } else {
                    shape.fill(Color.black)
                }
                content
                    .padding(.horizontal, model.topRadius)
            }
            .frame(width: model.shapeSize.width, height: model.shapeSize.height, alignment: .top)
            .clipShape(shape)
            .overlay(shape.stroke(look.accent.opacity(model.dropTargeted ? 0.7 : 0), lineWidth: 1.5))
            .shadow(color: .black.opacity(model.isExpanded && settings.shadow ? 0.55 : 0), radius: 18, y: 8)
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
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.presentation)
    }

    @ViewBuilder
    private var content: some View {
        let notch = model.geometry.notchSize
        switch model.presentation {
        case .expanded:
            ExpandedView(model: model, services: services, settings: settings)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                        .animation(.easeOut(duration: 0.22).delay(0.06)),
                    removal: .opacity.animation(.easeIn(duration: 0.08))))
        case .live:
            LiveActivityView(player: player, notch: notch)
                .transition(.opacity)
        case .timer:
            TimerActivityView(timer: services.timer, notch: notch)
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

// MARK: Collapsed states

/// Collapsed, while music plays: artwork to the left of the notch, a visualiser to the right.
struct LiveActivityView: View {
    @ObservedObject var player: NowPlaying
    let notch: CGSize
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(image: player.artwork, size: notch.height - 12, corner: 5)
                .frame(width: notch.height, alignment: .center)
            Spacer(minLength: notch.width)
            Group {
                if look.visualizer == .off {
                    Image(systemName: "music.note")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(look.accent)
                } else {
                    Visualizer(style: look.visualizer, color: look.accent)
                }
            }
            .frame(width: notch.height, alignment: .center)
        }
        .padding(.horizontal, 4)
        .frame(height: notch.height)
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
            HStack(spacing: 0) {
                ZStack {
                    Circle().stroke(look.accent.opacity(0.25), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: timer.progress(at: context.date))
                        .stroke(look.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: timer.isPaused ? "pause.fill" : "timer")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(look.accent)
                }
                .frame(width: 18, height: 18)
                .frame(width: 62)
                Spacer(minLength: notch.width)
                Text(FocusTimer.clock(timer.remaining(at: context.date)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(timer.isPaused ? .white.opacity(0.5) : .white)
                    .frame(width: 62)
            }
            .frame(height: notch.height)
        }
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

/// Collapsed, right after a volume or brightness change.
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
        HStack(spacing: 0) {
            icon.frame(width: 100)
            Spacer(minLength: notch.width)
            HStack(spacing: 7) {
                LevelBar(level: hud.level, color: look.accent).frame(width: 56, height: 5)
                percent
            }
            .frame(width: 100)
        }
        .foregroundStyle(.white)
        .frame(height: notch.height)
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
