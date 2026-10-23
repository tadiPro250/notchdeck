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
    @ObservedObject var player: NowPlaying
    let tray: FileTray
    let volume: VolumeControl
    let brightness: BrightnessControl
    let system: SystemStatus
    let actions: QuickActions

    var body: some View {
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(Color.black)
                content
                    .padding(.horizontal, model.topRadius)
            }
            .frame(width: model.shapeSize.width, height: model.shapeSize.height, alignment: .top)
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(model.dropTargeted ? 0.45 : 0), lineWidth: 1.5))
            .shadow(color: .black.opacity(model.isExpanded ? 0.5 : 0), radius: 16, y: 6)
            .onDrop(of: [UTType.fileURL], isTargeted: $model.dropTargeted) { providers in
                tray.add(providers: providers)
                model.tab = .tray
                return true
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.presentation)
    }

    @ViewBuilder
    private var content: some View {
        let notch = model.geometry.notchSize
        switch model.presentation {
        case .expanded:
            ExpandedView(model: model, player: player, tray: tray, volume: volume,
                         brightness: brightness, system: system, actions: actions)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                        .animation(.easeOut(duration: 0.22).delay(0.06)),
                    removal: .opacity.animation(.easeIn(duration: 0.08))))
        case .live:
            LiveActivityView(player: player, notch: notch)
                .transition(.opacity)
        case .hud(let hud):
            HUDView(hud: hud, notch: notch)
                .transition(.opacity)
        case .collapsed:
            Color.clear
        }
    }
}

/// Collapsed, while music plays: artwork to the left of the notch, a little visualiser to the right.
struct LiveActivityView: View {
    @ObservedObject var player: NowPlaying
    let notch: CGSize

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(image: player.artwork, size: notch.height - 12, corner: 5)
                .frame(width: notch.height, alignment: .center)
            Spacer(minLength: notch.width)
            AudioBars(color: player.accent)
                .frame(width: notch.height, alignment: .center)
        }
        .padding(.horizontal, 4)
        .frame(height: notch.height)
    }
}

struct AudioBars: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let wave = abs(sin(t * (3.1 + Double(i) * 1.37) + Double(i) * 0.9))
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: 4 + 10 * wave)
                }
            }
            .frame(height: 14)
        }
    }
}

/// Collapsed, right after a volume or brightness change.
struct HUDView: View {
    let hud: HUDState
    let notch: CGSize

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: hud.symbol)
                .font(.system(size: 13, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 100)
            Spacer(minLength: notch.width)
            HStack(spacing: 7) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule().fill(Color.white).frame(width: geo.size.width * hud.level)
                    }
                }
                .frame(width: 56, height: 5)
                Text("\(Int((hud.level * 100).rounded()))")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .frame(width: 22, alignment: .trailing)
            }
            .frame(width: 100)
        }
        .foregroundStyle(.white)
        .frame(height: notch.height)
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
