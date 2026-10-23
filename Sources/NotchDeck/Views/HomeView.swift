import SwiftUI

struct HomeView: View {
    @ObservedObject var model: NotchModel
    let services: NotchServices
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 18) {
            NowPlayingCard(player: services.player)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 6)
            Group {
                switch settings.glanceWidget {
                case .clock: ClockGlance(model: model, services: services)
                case .weather: WeatherGlance(weather: services.weather, large: true)
                case .calendar: NextEventGlance(calendar: services.calendar, large: true)
                case .stats: StatsGlance(stats: services.stats)
                }
            }
            .frame(width: 170, alignment: .leading)
        }
    }
}

/// Time and date, with a line each for weather and the next event when there is one.
private struct ClockGlance: View {
    @ObservedObject var model: NotchModel
    let services: NotchServices
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(look.theme.secondaryText)
                }
            }
            Spacer(minLength: 4)
            WeatherGlance(weather: services.weather, large: false)
            NextEventGlance(calendar: services.calendar, large: false)
            TrayChip(model: model, tray: services.tray)
                .padding(.top, 2)
        }
    }
}

private struct TrayChip: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var tray: FileTray

    var body: some View {
        if !tray.items.isEmpty {
            Button {
                model.tab = .tray
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full.fill")
                    Text("\(tray.items.count) in tray")
                }
                .font(.system(size: 10.5, weight: .medium))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

struct WeatherGlance: View {
    @ObservedObject var weather: WeatherService
    let large: Bool
    @Environment(\.look) private var look

    var body: some View {
        if let w = weather.weather {
            if large {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Image(systemName: w.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 30))
                        Text("\(Int(w.temperature.rounded()))°")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                    }
                    Text(w.summary)
                        .font(.system(size: 12, weight: .semibold))
                    Text("H \(Int(w.high.rounded()))°  L \(Int(w.low.rounded()))°  ·  \(w.city)")
                        .font(.system(size: 11))
                        .foregroundStyle(look.theme.secondaryText)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: w.symbol)
                        .symbolRenderingMode(.multicolor)
                    Text("\(Int(w.temperature.rounded()))° \(w.summary)")
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            }
        } else if large {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "cloud.sun.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 26))
                Text(weather.problem ?? "Loading weather…")
                    .font(.system(size: 11))
                    .foregroundStyle(look.theme.secondaryText)
            }
        }
    }
}

struct NextEventGlance: View {
    @ObservedObject var calendar: CalendarService
    let large: Bool
    @Environment(\.look) private var look

    var body: some View {
        if let event = calendar.nextEvent {
            if large {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.isNow ? "NOW" : "UP NEXT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(event.color)
                    Text(event.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Text(EventTime.describe(event))
                        .font(.system(size: 11))
                        .foregroundStyle(look.theme.secondaryText)
                    if let location = event.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.system(size: 10.5))
                            .foregroundStyle(look.theme.secondaryText)
                            .lineLimit(1)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Circle().fill(event.color).frame(width: 7, height: 7)
                    Text("\(event.title) · \(EventTime.short(event))")
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            }
        } else if large {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 24))
                    .foregroundStyle(look.accent)
                Text(calendar.access == .granted ? "Nothing else today" : "Calendar not connected")
                    .font(.system(size: 12, weight: .medium))
                if calendar.access != .granted {
                    Button("Connect") { calendar.requestAccess() }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
    }
}

enum EventTime {
    static func describe(_ event: CalendarEvent) -> String {
        if event.isAllDay { return Calendar.current.isDateInToday(event.start) ? "All day" : "Tomorrow, all day" }
        let time = event.start.formatted(date: .omitted, time: .shortened) + " – "
            + event.end.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(event.start) ? time : "Tomorrow, " + time
    }

    static func short(_ event: CalendarEvent) -> String {
        if event.isNow { return "now" }
        if event.isAllDay { return "all day" }
        let minutes = Int(event.start.timeIntervalSinceNow / 60)
        if minutes < 60 { return "in \(max(minutes, 1))m" }
        return event.start.formatted(date: .omitted, time: .shortened)
    }
}

struct NowPlayingCard: View {
    @ObservedObject var player: NowPlaying
    @Environment(\.look) private var look

    var body: some View {
        if let track = player.track {
            HStack(spacing: 16) {
                ArtworkView(image: player.artwork, size: 112, corner: 16)
                    .shadow(color: look.accent.opacity(0.35), radius: 16)
                    .onTapGesture { player.openPlayer() }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if track.isPlaying, look.visualizer != .off {
                            Visualizer(style: look.visualizer, color: look.accent)
                        }
                    }
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(look.theme.secondaryText)
                        .lineLimit(1)
                    Text(track.player.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(look.accent.opacity(0.8))
                    Spacer(minLength: 4)
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        Scrubber(position: track.position(at: context.date), duration: track.duration,
                                 tint: look.accent) { player.seek(to: $0) }
                    }
                    HStack(spacing: 30) {
                        MediaButton(symbol: "backward.fill", size: 15) { player.previous() }
                        MediaButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 22) { player.playPause() }
                        MediaButton(symbol: "forward.fill", size: 15) { player.next() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
            }
        } else {
            HStack(spacing: 16) {
                ArtworkView(image: nil, size: 112, corner: 16)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing playing")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Play something in Spotify or Music and it shows up here.")
                        .font(.system(size: 11))
                        .foregroundStyle(look.theme.secondaryText)
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
