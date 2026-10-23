import AppKit
import SwiftUI

enum MediaPlayer: String, CaseIterable {
    case spotify = "Spotify"
    case music = "Music"

    var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var isPlaying: Bool
    var player: MediaPlayer
    var artworkURL: String?
    var fetchedAt: Date

    var identity: String { "\(player.rawValue)|\(title)|\(artist)|\(album)" }

    func position(at date: Date) -> Double {
        guard isPlaying else { return position }
        return min(position + date.timeIntervalSince(fetchedAt), duration)
    }
}

/// Reads Spotify and Music over AppleScript. Since macOS 15.4 the MediaRemote framework only
/// answers Apple-signed clients, so scripting the players is the dependable route.
final class NowPlaying: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white

    private let queue = DispatchQueue(label: "notchdeck.nowplaying")
    private var timer: Timer?
    private var artworkKey: String?
    private var lastPlayer: MediaPlayer?
    private var observers: [NSObjectProtocol] = []

    init(live: Bool = true) {
        guard live else { return }
        let center = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    /// Fixed sample data for `--render-previews`.
    func showPreview(_ track: Track, artwork: NSImage, accent: Color) {
        self.track = track
        self.artwork = artwork
        self.accent = accent
    }

    var installedPlayers: [MediaPlayer] { MediaPlayer.allCases.filter { $0.appURL != nil } }

    func refresh() {
        queue.async { [weak self] in
            // Only ask running players: `tell application` would launch one that isn't.
            let tracks = MediaPlayer.allCases.filter(\.isRunning).compactMap(Self.query)
            DispatchQueue.main.async { self?.apply(tracks) }
        }
    }

    private func apply(_ tracks: [Track]) {
        let chosen = tracks.first(where: \.isPlaying)
            ?? tracks.first(where: { $0.player == lastPlayer })
            ?? tracks.first
        if let chosen { lastPlayer = chosen.player }
        if chosen != track { track = chosen }

        guard let chosen else {
            artworkKey = nil
            artwork = nil
            return
        }
        if chosen.identity != artworkKey {
            artworkKey = chosen.identity
            loadArtwork(for: chosen)
        }
    }

    // MARK: Commands

    func playPause() {
        if var current = track {
            current.position = current.position(at: Date())
            current.fetchedAt = Date()
            current.isPlaying.toggle()
            track = current
        }
        send("playpause")
    }

    func next() { send("next track") }
    func previous() { send("previous track") }
    func seek(to seconds: Double) { send("set player position to \(max(seconds, 0))") }

    func openPlayer(_ player: MediaPlayer? = nil) {
        guard let url = (player ?? track?.player ?? installedPlayers.first)?.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func send(_ command: String) {
        guard let player = track?.player else { return }
        queue.async { [weak self] in
            AppleScript.run("tell application \"\(player.rawValue)\" to \(command)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.refresh() }
        }
    }

    // MARK: Scripting

    private static func query(_ player: MediaPlayer) -> Track? {
        let source: String
        switch player {
        case .spotify:
            source = """
            tell application "Spotify"
                set s to player state as string
                if s is "stopped" then return {s}
                set t to current track
                return {s, name of t, artist of t, album of t, (duration of t) / 1000, player position, artwork url of t}
            end tell
            """
        case .music:
            source = """
            tell application "Music"
                set s to player state as string
                if s is "stopped" then return {s}
                set t to current track
                return {s, name of t, artist of t, album of t, duration of t, player position}
            end tell
            """
        }
        guard let result = AppleScript.run(source), result.numberOfItems >= 6 else { return nil }
        func text(_ i: Int) -> String { result.atIndex(i)?.stringValue ?? "" }
        func number(_ i: Int) -> Double { result.atIndex(i)?.doubleValue ?? 0 }
        let title = text(2)
        guard !title.isEmpty else { return nil }
        return Track(title: title, artist: text(3), album: text(4),
                     duration: number(5), position: number(6),
                     isPlaying: text(1) == "playing", player: player,
                     artworkURL: result.numberOfItems >= 7 ? text(7) : nil,
                     fetchedAt: Date())
    }

    private func loadArtwork(for track: Track) {
        let key = track.identity
        let finish: (NSImage?) -> Void = { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.artworkKey == key else { return }
                self.artwork = image
                self.accent = image.flatMap(Self.accentColor).map { Color(nsColor: $0) } ?? .white
            }
        }
        switch track.player {
        case .spotify:
            guard let raw = track.artworkURL, let url = URL(string: raw) else { return finish(nil) }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                finish(data.flatMap(NSImage.init(data:)))
            }.resume()
        case .music:
            queue.async {
                let data = AppleScript.run("tell application \"Music\" to get raw data of artwork 1 of current track")?.data
                finish(data.flatMap(NSImage.init(data:)))
            }
        }
    }

    /// The artwork's average colour, lifted so it reads on black.
    private static func accentColor(of image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let average = NSColor(deviceRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        average.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(deviceHue: h, saturation: min(s * 1.25, 0.9), brightness: max(b, 0.8), alpha: 1)
    }
}

enum AppleScript {
    private static var cache: [String: NSAppleScript] = [:]
    private static let lock = NSLock()

    @discardableResult
    static func run(_ source: String) -> NSAppleEventDescriptor? {
        lock.lock()
        defer { lock.unlock() }
        let script: NSAppleScript
        if let cached = cache[source] {
            script = cached
        } else {
            guard let compiled = NSAppleScript(source: source) else { return nil }
            compiled.compileAndReturnError(nil)
            cache[source] = compiled
            script = compiled
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}
