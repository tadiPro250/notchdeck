import SwiftUI

/// The lock screen, full screen: the album's colours as the whole background, a turntable whose
/// record is the album art, the lyrics beside it in time with the song, and the time in a corner in
/// the lock-screen clock's own font. No buttons: the play/pause and skip keys already do that, and
/// the tonearm swings on and off the record as the music starts and stops.
struct LockScreenView: View {
    @ObservedObject var player: NowPlaying
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var system: SystemStatus
    @ObservedObject var weather: WeatherService
    @ObservedObject var settings: AppSettings

    var body: some View {
        let accent = settings.accent(artwork: player.artworkAccent)
        let playing = player.track?.isPlaying ?? false
        GeometryReader { geo in
            // The turntable is drawn at 300 × 270 and scaled to about half the screen's height.
            let k = min(max(geo.size.height * 0.5 / 270, 1), 2.1)
            ZStack {
                // Pinned to the screen: an aspect-filled square cover would otherwise grow the stack
                // past it and push the clock and status line off the edges.
                AlbumBackdrop(artwork: player.artwork, accent: accent)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        CornerClock()
                        Spacer()
                        if let appName = player.track?.appName {
                            Text(appName.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.5)
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.top, 10)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 64 * k / 1.6) {
                        Turntable(artwork: player.artwork, isPlaying: playing, accent: accent)
                            .scaleEffect(k, anchor: .topLeading)
                            .frame(width: 300 * k, height: 270 * k, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: 0) {
                            if let track = player.track {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title)
                                        .font(.system(size: 30, weight: .bold))
                                        .lineLimit(2)
                                    Text(track.artist)
                                        .font(.system(size: 19, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                                .padding(.bottom, 22)
                                SyncedLyrics(track: track, lyrics: lyrics, accent: accent, scale: 1.35)
                            } else {
                                Spacer()
                                Text("Nothing playing")
                                    .font(.system(size: 34, weight: .bold))
                                Text("Start a song and the needle drops.")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.white.opacity(0.55))
                                Spacer()
                            }
                        }
                        .frame(maxWidth: 640, maxHeight: 270 * k, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                    StatusLine(system: system, weather: weather)
                }
                .padding(.horizontal, 64)
                .padding(.top, 48)
                .padding(.bottom, 40)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }
}

/// The background, made from the album: its art blurred far out, the colours that dominate it
/// drifting slowly underneath, and a vignette so the text always reads.
private struct AlbumBackdrop: View {
    let artwork: NSImage?
    let accent: Color

    var body: some View {
        let palette = AlbumPalette.colors(of: artwork, fallback: accent)
        ZStack {
            // Solid underneath, so the lock screen's own wallpaper never shows through.
            Color.black
            LinearGradient(colors: [palette[0].opacity(0.9), palette[1].opacity(0.75), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Large soft fields of colour, each on its own slow orbit (a minute or so per loop).
            TimelineView(.animation(minimumInterval: 1 / 15)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            let speed = [0.09, 0.07, 0.11][i]
                            let phase = Double(i) * 2.1
                            RadialGradient(colors: [palette[i].opacity(0.75), palette[i].opacity(0)],
                                           center: .center, startRadius: 0, endRadius: max(w, h) * 0.45)
                                .frame(width: max(w, h) * 0.9, height: max(w, h) * 0.9)
                                .position(x: w * (0.5 + 0.32 * cos(t * speed + phase)),
                                          y: h * (0.5 + 0.28 * sin(t * speed * 1.3 + phase)))
                        }
                    }
                }
            }
            .blendMode(.plusLighter)
            .opacity(0.55)
            if let artwork {
                Color.clear.overlay(
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 90)
                        .saturation(1.35)
                        .opacity(0.4)
                )
                .clipped()
            }
            // Vignette and a darker floor for the status line.
            RadialGradient(colors: [.clear, .black.opacity(0.6)], center: .center, startRadius: 200, endRadius: 1100)
            LinearGradient(colors: [.black.opacity(0.25), .clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
        .drawingGroup()
        .ignoresSafeArea()
    }
}

/// The three colours an album cover is mostly made of, most vivid first. Read from a 6 × 6
/// thumbnail, so it costs nothing; a plain or missing cover falls back to the accent.
enum AlbumPalette {
    private static var cache: (ObjectIdentifier, [Color])?

    static func colors(of image: NSImage?, fallback: Color) -> [Color] {
        let plain = [fallback, fallback.opacity(0.7), Color(red: 0.15, green: 0.1, blue: 0.3)]
        guard let image else { return plain }
        if let cache, cache.0 == ObjectIdentifier(image) { return cache.1 }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 6, pixelsHigh: 6, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return plain }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 6, height: 6))
        NSGraphicsContext.restoreGraphicsState()
        var picked: [NSColor] = []
        let pixels = (0..<6).flatMap { x in (0..<6).compactMap { y in rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) } }
        // Vivid and not too dark first; skip ones too close to a colour already picked.
        for c in pixels.sorted(by: { $0.saturationComponent * (0.4 + $0.brightnessComponent) >
                                      $1.saturationComponent * (0.4 + $1.brightnessComponent) }) {
            let far = picked.allSatisfy { abs($0.hueComponent - c.hueComponent) > 0.07 || abs($0.brightnessComponent - c.brightnessComponent) > 0.25 }
            if far { picked.append(c) }
            if picked.count == 3 { break }
        }
        while picked.count < 3 { picked.append(picked.last ?? NSColor(fallback)) }
        // Keep them rich but never glaring behind white text.
        let colors = picked.map { c in
            Color(hue: c.hueComponent, saturation: min(c.saturationComponent * 1.15, 1),
                  brightness: min(max(c.brightnessComponent, 0.35), 0.8))
        }
        cache = (ObjectIdentifier(image), colors)
        return colors
    }
}

/// The time and date, top left, in the font chosen for the lock-screen clock in System Settings.
private struct CornerClock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(LockClockFont.font(size: 64))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            }
        }
    }
}

/// The lock-screen clock's font, read from System Settings (`com.apple.loginwindow`
/// `ClockFontIdentifier` and `ClockFontWeight`). Apple's own clock faces ("rail" and friends) are
/// private to the system and can't be loaded by an app, so each is mapped to the nearest public
/// face of the system font; the weight is used as set.
enum LockClockFont {
    static func font(size: CGFloat) -> Font {
        let defaults = UserDefaults(suiteName: "com.apple.loginwindow")
        let identifier = (defaults?.string(forKey: "ClockFontIdentifier") ?? "").lowercased()
        let weight = weight(defaults?.object(forKey: "ClockFontWeight") as? Int ?? 500)
        switch identifier {
        case let id where id.contains("round") || id.contains("soft"):
            return .system(size: size, weight: weight, design: .rounded)
        case let id where id.contains("serif") || id.contains("york"):
            return .system(size: size, weight: weight, design: .serif)
        case let id where id.contains("mono"):
            return .system(size: size, weight: weight, design: .monospaced)
        case let id where id.contains("rail") || id.contains("compress"):
            return .system(size: size, weight: weight).width(.compressed)
        case let id where id.contains("condens"):
            return .system(size: size, weight: weight).width(.condensed)
        case let id where id.contains("expand") || id.contains("wide"):
            return .system(size: size, weight: weight).width(.expanded)
        default:
            return .system(size: size, weight: weight)
        }
    }

    private static func weight(_ value: Int) -> Font.Weight {
        switch value {
        case ..<150: .ultraLight
        case ..<250: .thin
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
    }
}

// MARK: Turntable

/// Keeps the platter's angle continuous: it spins up when the music starts and coasts to a stop.
final class TurntableMotor {
    private(set) var angle: Double = 0
    private var speed: Double = 0
    private var last: Date?

    /// Degrees per second. A real 33⅓ rpm (200°/s) blurs the album art into a smear; this is
    /// about 7.5 rpm, slow enough to read the cover as it turns.
    static let fullSpeed = 45.0

    func advance(to date: Date, playing: Bool) -> Double {
        let dt = min(max(date.timeIntervalSince(last ?? date), 0), 0.1)
        last = date
        let target = playing ? Self.fullSpeed : 0
        // Spin up a little faster than it winds down, like a belt drive.
        let rate = playing ? 2.2 : 1.4
        speed += (target - speed) * min(1, dt * rate)
        if !playing, speed < 1 { speed = 0 }
        angle = (angle + speed * dt).truncatingRemainder(dividingBy: 360)
        return angle
    }

    var isStopped: Bool { speed == 0 }
}

struct Turntable: View {
    let artwork: NSImage?
    let isPlaying: Bool
    let accent: Color
    @StateObject private var motor = ViewState(TurntableMotor())
    /// Keeps the timeline running while the platter coasts after a pause.
    @StateObject private var coasting = ViewState<Bool>(false)

    // Layout, in the turntable's 300 × 270 frame.
    private let center = CGPoint(x: 128, y: 135)
    private let radius: CGFloat = 112
    private let pivot = CGPoint(x: 266, y: 40)
    private let armLength: CGFloat = 178
    /// Down is 0°; the needle sits on the outer grooves at this angle.
    private let playAngle = 24.0
    private let restAngle = -4.0

    var body: some View {
        ZStack(alignment: .topLeading) {
            plinth
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !isPlaying && !coasting.value)) { context in
                record.rotationEffect(.degrees(motor.value.advance(to: context.date, playing: isPlaying)))
            }
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
            sheen
            spindle
            tonearm
        }
        .frame(width: 300, height: 270)
        .onChange(of: isPlaying) { playing in
            guard !playing else { return }
            coasting.value = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { coasting.value = false }
        }
    }

    private var plinth: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.09)], startPoint: .topLeading,
                                 endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                // Power light: lit while playing.
                Circle()
                    .fill(isPlaying ? accent : Color(white: 0.3))
                    .frame(width: 7, height: 7)
                    .shadow(color: isPlaying ? accent : .clear, radius: 5)
                    .padding(18)
                    .animation(.easeInOut(duration: 0.6), value: isPlaying)
            }
            .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
            .frame(width: 300, height: 270)
    }

    /// A picture disc: the album art across the whole record, with grooves pressed over it.
    private var record: some View {
        ZStack {
            Circle().fill(Color(white: 0.04))
            Group {
                if let artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                } else {
                    AngularGradient(colors: [Color(white: 0.1), Color(white: 0.18), Color(white: 0.1),
                                             Color(white: 0.16), Color(white: 0.1)], center: .center)
                }
            }
            .frame(width: radius * 2 - 10, height: radius * 2 - 10)
            .clipShape(Circle())
            Canvas { context, size in
                let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                var r: CGFloat = 26
                while r < size.width / 2 - 4 {
                    let ring = Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: 2 * r, height: 2 * r))
                    context.stroke(ring, with: .color(.black.opacity(0.16)), lineWidth: 0.6)
                    r += 2.6
                }
            }
            // The run-out edge and the lead-in groove.
            Circle().strokeBorder(Color.black.opacity(0.7), lineWidth: 5)
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 1).padding(5)
            // A label mark so the spin is visible even on plain artwork.
            Capsule().fill(Color.white.opacity(0.35)).frame(width: 2, height: 10).offset(y: -34)
        }
        .frame(width: radius * 2, height: radius * 2)
    }

    /// Light on vinyl doesn't turn with the record, so the sheen sits on top, still.
    private var sheen: some View {
        Circle()
            .fill(AngularGradient(colors: [.clear, .white.opacity(0.16), .clear, .clear, .white.opacity(0.1), .clear],
                                  center: .center, angle: .degrees(-20)))
            .frame(width: radius * 2, height: radius * 2)
            .blendMode(.screen)
            .position(center)
            .allowsHitTesting(false)
    }

    private var spindle: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.55)).frame(width: 30, height: 30)
            Circle().fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.45)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 9, height: 9)
        }
        .position(center)
    }

    private var tonearm: some View {
        let anchor = UnitPoint(x: pivot.x / 300, y: pivot.y / 270)
        return ZStack(alignment: .topLeading) {
            // Counterweight behind the pivot.
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.3)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 16, height: 22)
                .position(x: pivot.x, y: pivot.y - 22)
            // The arm, with a slight dogleg near the head like a real S-arm.
            Path { path in
                path.move(to: pivot)
                path.addLine(to: CGPoint(x: pivot.x, y: pivot.y + armLength * 0.78))
                path.addLine(to: CGPoint(x: pivot.x - 10, y: pivot.y + armLength))
            }
            .stroke(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.55)], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.5), radius: 3, x: 3, y: 4)
            // Headshell and needle.
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color(white: 0.75))
                .frame(width: 12, height: 22)
                .rotationEffect(.degrees(24))
                .position(x: pivot.x - 13, y: pivot.y + armLength + 6)
            Circle().fill(accent).frame(width: 3, height: 3)
                .position(x: pivot.x - 17, y: pivot.y + armLength + 15)
            // Pivot base.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.7), Color(white: 0.25)], center: .topLeading,
                                     startRadius: 0, endRadius: 30))
                .frame(width: 34, height: 34)
                .overlay(Circle().fill(Color(white: 0.15)).frame(width: 10, height: 10))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
                .position(pivot)
        }
        .frame(width: 300, height: 270)
        .rotationEffect(.degrees(isPlaying ? playAngle : restAngle), anchor: anchor)
        .animation(.spring(response: 1.15, dampingFraction: 0.78), value: isPlaying)
    }
}

// MARK: Lyrics

/// The song's lines, the one being sung large and bright, the rest fading out above and below.
private struct SyncedLyrics: View {
    let track: Track
    @ObservedObject var lyrics: LyricsService
    let accent: Color
    var scale: CGFloat = 1

    var body: some View {
        if lyrics.lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text(lyrics.isLoading ? "Finding lyrics…" : (lyrics.plain == nil ? "♪" : "Lyrics aren't timed for this one"))
                    .font(.system(size: 24 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                if let plain = lyrics.plain {
                    Text(plain.split(separator: "\n").prefix(4).joined(separator: "\n"))
                        .font(.system(size: 14 * scale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(4)
                } else if !lyrics.isLoading {
                    Text(track.album.isEmpty ? track.appName : track.album)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
        } else {
            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                LyricsColumn(lines: lyrics.lines, index: lyrics.index(at: track.position(at: context.date)),
                             accent: accent, scale: scale)
            }
        }
    }
}

private struct LyricsColumn: View {
    let lines: [LyricsService.Line]
    let index: Int?
    let accent: Color
    var scale: CGFloat = 1

    var body: some View {
        let current = index ?? -1
        GeometryReader { geo in
            let lineHeight: CGFloat = 40 * scale
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { offset, line in
                    let distance = abs(offset - current)
                    Text(line.text)
                        .font(.system(size: (offset == current ? 23 : 18) * scale, weight: .bold))
                        .foregroundStyle(offset == current ? Color.white : Color.white.opacity(distance == 1 ? 0.42 : 0.22))
                        .shadow(color: offset == current ? accent.opacity(0.6) : .clear, radius: 12)
                        .blur(radius: distance >= 3 ? 1.2 : 0)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .scaleEffect(offset == current ? 1 : 0.97, anchor: .leading)
                        .frame(height: lineHeight, alignment: .leading)
                }
            }
            // The current line sits a third of the way down; the column glides as it changes.
            .offset(y: geo.size.height * 0.36 - (CGFloat(max(current, 0)) + 0.5) * lineHeight)
            .animation(.spring(response: 0.55, dampingFraction: 0.86), value: current)
        }
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                     .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }
}

private struct StatusLine: View {
    @ObservedObject var system: SystemStatus
    @ObservedObject var weather: WeatherService

    var body: some View {
        HStack(spacing: 16) {
            if let level = system.batteryLevel {
                Label("\(level)%", systemImage: system.isCharging ? "battery.100.bolt" : "battery.75")
            }
            if let w = weather.weather {
                Label("\(Int(w.temperature.rounded()))° \(w.summary)", systemImage: w.symbol)
                    .symbolRenderingMode(.multicolor)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
    }
}
