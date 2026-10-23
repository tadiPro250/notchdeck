import SwiftUI

struct HomeView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var player: NowPlaying
    @ObservedObject var system: SystemStatus
    @ObservedObject var tray: FileTray

    var body: some View {
        HStack(spacing: 18) {
            NowPlayingCard(player: player)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 6)
            glance
                .frame(width: 150, alignment: .leading)
        }
    }

    private var glance: some View {
        VStack(alignment: .leading, spacing: 2) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer(minLength: 6)
            Button {
                model.tab = .tray
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: tray.items.isEmpty ? "tray" : "tray.full.fill")
                    Text(tray.items.isEmpty ? "Tray is empty" : "\(tray.items.count) in tray")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

struct NowPlayingCard: View {
    @ObservedObject var player: NowPlaying

    var body: some View {
        if let track = player.track {
            HStack(spacing: 16) {
                ArtworkView(image: player.artwork, size: 104, corner: 16)
                    .shadow(color: player.accent.opacity(0.35), radius: 14)
                    .onTapGesture { player.openPlayer() }
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        Scrubber(position: track.position(at: context.date), duration: track.duration,
                                 tint: player.accent) { player.seek(to: $0) }
                    }
                    HStack(spacing: 30) {
                        MediaButton(symbol: "backward.fill", size: 15) { player.previous() }
                        MediaButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 22) { player.playPause() }
                        MediaButton(symbol: "forward.fill", size: 15) { player.next() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
        } else {
            HStack(spacing: 16) {
                ArtworkView(image: nil, size: 104, corner: 16)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing playing")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Play something in Spotify or Music and it shows up here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        ForEach(player.installedPlayers, id: \.self) { app in
                            Button("Open \(app.rawValue)") { player.openPlayer(app) }
                                .buttonStyle(PillButtonStyle())
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

struct Scrubber: View {
    let position: Double
    let duration: Double
    let tint: Color
    let onSeek: (Double) -> Void
    @StateObject private var dragFraction = ViewState<Double?>(nil)

    var body: some View {
        let fraction = dragFraction.value ?? (duration > 0 ? min(max(position / duration, 0), 1) : 0)
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(tint).frame(width: max(geo.size.width * fraction, 5))
                }
                .contentShape(Rectangle().inset(by: -6))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction.value = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                    }
                    .onEnded { _ in
                        if let f = dragFraction.value { onSeek(f * duration) }
                        dragFraction.value = nil
                    })
            }
            .frame(height: dragFraction.value == nil ? 5 : 7)
            .animation(.easeOut(duration: 0.12), value: dragFraction.value == nil)
            HStack {
                Text(Self.clock(fraction * duration))
                Spacer()
                Text("-" + Self.clock(max(duration - fraction * duration, 0)))
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct MediaButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @StateObject private var hovering = ViewState<Bool>(false)

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + 18, height: size + 14)
                .background(Circle().fill(Color.white.opacity(hovering.value ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering.value = $0 }
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0.1)))
            .contentShape(Capsule())
    }
}
