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

/// What's playing, as far as the notch cares.
enum MediaKind: Equatable {
    /// A song: track buttons, lyrics, the record player on the lock screen.
    case music
    /// A film, a show, a video in a browser tab: skip buttons, "Watching".
    case video
    /// A podcast or an audiobook: skip buttons, nothing else.
    case spoken
}

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var isPlaying: Bool
    /// Set when the track came from scripting Spotify or Music.
    var player: MediaPlayer?
    /// The app playing it (any app when it came from the system's Now Playing).
    var bundleID: String?
    var appName: String
    var artworkURL: String?
    var fetchedAt: Date
    var kind: MediaKind = .music
    /// Only songs get the record player on the lock screen and a lyrics search.
    var isMusic: Bool { kind == .music }

    var identity: String { "\(bundleID ?? appName)|\(title)|\(artist)|\(album)" }

    func position(at date: Date) -> Double {
        guard isPlaying else { return position }
        let now = position + date.timeIntervalSince(fetchedAt)
        return duration > 0 ? min(now, duration) : now
    }
}

/// What's playing, from any app. The system Now Playing (Safari, Brave, YouTube, Podcasts,
/// QuickTime, Spotify, Music…) is read through a small bridge that runs inside Apple's
/// `/usr/bin/perl`, because since macOS 15.4 MediaRemote only answers Apple-signed processes.
/// If the bridge can't run, Spotify and Music are read over AppleScript instead.
final class NowPlaying: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    /// The album art's colour, lifted to read on black. Nil until artwork loads.
    @Published private(set) var artworkAccent: Color?
    /// True while the current track comes from the system Now Playing bridge.
    @Published private(set) var usesSystemNowPlaying = false

    private let queue = DispatchQueue(label: "notchdeck.nowplaying")
    private var timer: Timer?
    private var artworkKey: String?
    private var lastPlayer: MediaPlayer?
    private var observers: [NSObjectProtocol] = []
    private let bridge = MediaRemoteBridge()

    init(live: Bool = true) {
        guard live else { return }
        bridge.onUpdate = { [weak self] update in self?.applyRemote(update) }
        bridge.onFailure = { [weak self] in
            self?.usesSystemNowPlaying = false
            self?.refresh()
        }
        bridge.start()

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
        self.artworkAccent = accent
    }

    var installedPlayers: [MediaPlayer] { MediaPlayer.allCases.filter { $0.appURL != nil } }

    func refresh() {
        // The bridge pushes changes itself; scripting is only the fallback.
        guard !usesSystemNowPlaying else { return }
        queue.async { [weak self] in
            // Only ask running players: `tell application` would launch one that isn't.
            let tracks = MediaPlayer.allCases.filter(\.isRunning).compactMap(Self.query)
            DispatchQueue.main.async { self?.applyScripted(tracks) }
        }
    }

    // MARK: Sources

    private func applyRemote(_ update: MediaRemoteBridge.Update) {
        guard let title = update.title, !title.isEmpty else {
            // Nothing from the system (or the system withholds it): let scripting answer.
            if usesSystemNowPlaying {
                usesSystemNowPlaying = false
                setTrack(nil)
            }
            refresh()
            return
        }
        usesSystemNowPlaying = true
        let appName = update.bundleID.flatMap(Self.appName(for:)) ?? "Now Playing"
        let player = MediaPlayer.allCases.first { $0.bundleID == update.bundleID }
        var position = update.elapsed ?? 0
        if let stamp = update.timestamp, (update.rate ?? 0) > 0 {
            position += Date().timeIntervalSince(stamp) * (update.rate ?? 1)
        }
        let next = Track(title: title, artist: update.artist ?? "", album: update.album ?? "",
                         duration: update.duration ?? 0, position: position, isPlaying: update.playing,
                         player: player, bundleID: update.bundleID, appName: appName,
                         artworkURL: nil, fetchedAt: Date(), kind: Self.kind(update))
        setTrack(next)
        if let data = update.artwork, let image = NSImage(data: data) {
            artworkKey = next.identity
            setArtwork(image)
        } else if update.artworkHash == nil, artworkKey != next.identity {
            artworkKey = next.identity
            setArtwork(nil)
        }
    }

    private func applyScripted(_ tracks: [Track]) {
        guard !usesSystemNowPlaying else { return }
        let chosen = tracks.first(where: \.isPlaying)
            ?? tracks.first(where: { $0.player == lastPlayer })
            ?? tracks.first
        if let chosen { lastPlayer = chosen.player }
        setTrack(chosen)
        guard let chosen else { return }
        if chosen.identity != artworkKey {
            artworkKey = chosen.identity
            loadScriptedArtwork(for: chosen)
        }
    }

    private func setTrack(_ next: Track?) {
        if next != track { track = next }
        if next == nil, artwork != nil {
            artworkKey = nil
            setArtwork(nil)
        }
    }

    private func setArtwork(_ image: NSImage?) {
        artwork = image
        artworkAccent = image.flatMap(Self.accentColor).map { Color(nsColor: $0) }
    }

    // MARK: Commands

    func playPause() {
        if var current = track {
            current.position = current.position(at: Date())
            current.fetchedAt = Date()
            current.isPlaying.toggle()
            track = current
        }
        send(remote: "toggle", script: "playpause")
    }

    func next() { send(remote: "next", script: "next track") }
    func previous() { send(remote: "previous", script: "previous track") }

    func seek(to seconds: Double) {
        if var current = track {
            current.position = max(seconds, 0)
            current.fetchedAt = Date()
            track = current
        }
        send(remote: "seek:\(max(seconds, 0))", script: "set player position to \(max(seconds, 0))")
    }

    func openPlayer(_ player: MediaPlayer? = nil) {
        if player == nil, let bundle = track?.bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        guard let url = (player ?? track?.player ?? installedPlayers.first)?.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func send(remote: String, script: String) {
        if usesSystemNowPlaying {
            bridge.send(remote)
            return
        }
        guard let player = track?.player else { return }
        queue.async { [weak self] in
            AppleScript.run("tell application \"\(player.rawValue)\" to \(script)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.refresh() }
        }
    }

    // MARK: Scripting fallback

    private static func query(_ player: MediaPlayer) -> Track? {
        let source: String
        switch player {
        case .spotify:
            source = """
            with timeout of 3 seconds
                tell application "Spotify"
                    set s to player state as string
                    if s is "stopped" then return {s}
                    set t to current track
                    return {s, name of t, artist of t, album of t, (duration of t) / 1000, player position, artwork url of t}
                end tell
            end timeout
            """
        case .music:
            source = """
            with timeout of 3 seconds
                tell application "Music"
                    set s to player state as string
                    if s is "stopped" then return {s}
                    set t to current track
                    return {s, name of t, artist of t, album of t, duration of t, player position}
                end tell
            end timeout
            """
        }
        guard let result = AppleScript.run(source), result.numberOfItems >= 6 else { return nil }
        func text(_ i: Int) -> String { result.atIndex(i)?.stringValue ?? "" }
        func number(_ i: Int) -> Double { result.atIndex(i)?.doubleValue ?? 0 }
        let title = text(2)
        guard !title.isEmpty else { return nil }
        return Track(title: title, artist: text(3), album: text(4),
                     duration: number(5), position: number(6),
                     isPlaying: text(1) == "playing", player: player, bundleID: player.bundleID,
                     appName: player.rawValue,
                     artworkURL: result.numberOfItems >= 7 ? text(7) : nil,
                     fetchedAt: Date())
    }

    private func loadScriptedArtwork(for track: Track) {
        let key = track.identity
        let finish: (NSImage?) -> Void = { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.artworkKey == key else { return }
                self.setArtwork(image)
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
                let data = AppleScript.run("""
                with timeout of 3 seconds
                    tell application "Music" to get raw data of artwork 1 of current track
                end timeout
                """)?.data
                finish(data.flatMap(NSImage.init(data:)))
            }
        case nil:
            finish(nil)
        }
    }

    // MARK: Song or video

    static let musicApps: Set<String> = [
        "com.spotify.client", "com.apple.Music", "com.apple.iTunes", "com.tidal.desktop", "com.deezer.deezer-desktop",
        "com.amazon.music", "com.github.th-ch.youtube-music", "com.ytmdesktop.app", "sh.cider.electron",
        "com.cider.Cider", "co.brushedtype.doppler-macos", "com.coppertino.Vox", "com.swinsian.Swinsian",
        "tv.plex.plexamp", "com.qobuz.QobuzDesktop", "com.soundcloud.desktop",
    ]
    static let videoApps: Set<String> = [
        "com.apple.QuickTimePlayerX", "com.apple.TV", "com.netflix.Netflix", "com.colliderli.iina", "org.videolan.vlc",
        "com.firecore.infuse", "tv.plex.desktop", "com.amazon.aiv.AIVApp", "com.disney.disneyplus", "com.movist.MovistPro",
        "com.eltima.elmedia-video", "io.mpv", "com.apple.FaceTime",
    ]
    /// Podcast and audiobook players: never songs, whatever the episode's length.
    static let spokenApps: Set<String> = [
        "com.apple.podcasts", "fm.overcast.overcast", "au.com.shiftyjelly.podcasts", "co.supertop.Castro",
        "com.apple.iBooksX", "com.audible.mac",
    ]
    static let browsers: [String] = [
        "com.apple.Safari", "com.apple.WebKit", "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
        "org.mozilla.firefox", "company.thebrowser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "com.duckduckgo.macos.browser", "com.kagi.kagimacOS", "app.zen-browser",
    ]

    /// Whether what's playing is a song. MediaRemote says so outright for some players; for a web
    /// page it rarely does, and Netflix, YouTube and every other video site look like a "track"
    /// with a title. So a tab counts as music only with the marks of a song: an artist AND an
    /// album (Spotify, YouTube Music and Apple Music on the web all send both), or a YouTube
    /// "– Topic" / VEVO channel. Anything over 15 minutes outside a music app is a video.
    static func kind(_ u: MediaRemoteBridge.Update) -> MediaKind {
        let type = u.mediaType?.lowercased() ?? ""
        if type.contains("video") || type.contains("movie") { return .video }
        let bundle = u.bundleID ?? "", parent = u.parentBundleID ?? ""
        if type.contains("podcast") || type.contains("audiobook") || spokenApps.contains(bundle) || spokenApps.contains(parent) {
            return .spoken
        }
        let inBrowser = browsers.contains { bundle.hasPrefix($0) || parent.hasPrefix($0) }
        // A browser may call any tab "music"; only the tab's own details are trusted there.
        let saysMusic = type.contains("music") || u.isMusicApp == true
        if !inBrowser && saysMusic { return .music }
        if musicApps.contains(bundle) || musicApps.contains(parent) { return .music }
        if videoApps.contains(bundle) || videoApps.contains(parent) { return .video }
        let artist = (u.artist ?? "").trimmingCharacters(in: .whitespaces)
        let album = (u.album ?? "").trimmingCharacters(in: .whitespaces)
        let duration = u.duration ?? 0
        if duration > 15 * 60 { return .video }
        if inBrowser {
            if artist.hasSuffix("- Topic") || artist.uppercased().hasSuffix("VEVO") { return .music }
            return !artist.isEmpty && !album.isEmpty ? .music : .video
        }
        // Some other app: a song has an artist and a song's length.
        return !artist.isEmpty && (duration == 0 || duration >= 30) ? .music : .video
    }

    /// `--test-media`: what counts as a song.
    static func selfTest() {
        func u(_ bundle: String, parent: String? = nil, artist: String = "", album: String = "", duration: Double = 240,
               type: String? = nil, musicApp: Bool? = nil) -> MediaRemoteBridge.Update {
            var x = MediaRemoteBridge.Update()
            x.bundleID = bundle; x.parentBundleID = parent; x.title = "Title"; x.artist = artist; x.album = album
            x.duration = duration; x.mediaType = type; x.isMusicApp = musicApp
            return x
        }
        let cases: [(String, Bool, MediaRemoteBridge.Update)] = [
            ("Spotify song", true, u("com.spotify.client", artist: "Shreya Ghoshal", album: "Singham", type: "kMRMediaRemoteNowPlayingInfoTypeAudio")),
            ("Apple Music song", true, u("com.apple.Music", artist: "M83", album: "Hurry Up")),
            ("Netflix in Chrome", false, u("com.google.Chrome", duration: 3200)),
            ("Netflix in Chrome, short episode, no artist", false, u("com.google.Chrome", duration: 1300)),
            ("YouTube video in Brave", false, u("com.brave.Browser", artist: "Some Channel", duration: 600)),
            ("YouTube video in Safari, typed as music", false, u("com.apple.WebKit.GPU", parent: "com.apple.Safari", artist: "Channel", type: "MRMediaRemoteMediaTypeMusic")),
            ("Spotify Web Player", true, u("com.google.Chrome", artist: "Coldplay", album: "Parachutes")),
            ("YouTube auto-generated song", true, u("com.google.Chrome", artist: "Arijit Singh - Topic")),
            ("film in QuickTime", false, u("com.apple.QuickTimePlayerX", duration: 5400)),
            ("Netflix app", false, u("com.netflix.Netflix", artist: "", duration: 2700)),
            ("video by media type", false, u("com.example.player", artist: "x", type: "kMRMediaRemoteNowPlayingInfoTypeVideo")),
            ("unknown app, a song", true, u("com.example.player", artist: "Artist")),
            ("unknown app, 2-hour mix", false, u("com.example.player", artist: "DJ", duration: 7200)),
            ("podcast episode", false, u("com.apple.podcasts", artist: "The Daily", duration: 1800,
                                         type: "kMRMediaRemoteNowPlayingInfoTypeAudio")),
            ("short podcast episode (10 min)", false, u("com.apple.podcasts", artist: "Up First", duration: 600,
                                                        type: "kMRMediaRemoteNowPlayingInfoTypeAudio")),
            ("Overcast episode", false, u("fm.overcast.overcast", artist: "A Show", duration: 900)),
            ("browser video that says it's a music app", false,
             u("com.google.Chrome", artist: "Channel", duration: 500, musicApp: true)),
            ("Music app that says it's a music app", true, u("com.example.player", artist: "A", musicApp: true)),
        ]
        print("\(SelfTest.mark(kind(u("com.apple.podcasts", artist: "x", duration: 600)) == .spoken)) podcasts are spoken word")
        print("\(SelfTest.mark(kind(u("com.google.Chrome", duration: 3200)) == .video)) Netflix in Chrome is a video")
        for (name, expected, update) in cases {
            let got = kind(update) == .music
            print("\(SelfTest.mark(got == expected)) \(name): \(got ? "song" : "video")")
        }
    }

    private static func appName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// The artwork's average colour, lifted so it reads on black.
    static func accentColor(of image: NSImage) -> NSColor? {
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
        // Near-grey artwork makes a muddy accent; let the theme's accent take over instead.
        guard s > 0.18 else { return nil }
        return NSColor(deviceHue: h, saturation: min(s * 1.25, 0.9), brightness: max(b, 0.8), alpha: 1)
    }
}

/// Runs `Helpers/MediaRemoteBridge.m` (built into the app bundle) inside `/usr/bin/perl` and
/// streams its JSON lines.
final class MediaRemoteBridge {
    struct Update {
        var playing = false
        var bundleID: String?
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double?
        var elapsed: Double?
        var rate: Double?
        var timestamp: Date?
        var artwork: Data?
        var artworkHash: String?
        var parentBundleID: String?
        var mediaType: String?
        var isMusicApp: Bool?
        var genre: String?
    }

    var onUpdate: ((Update) -> Void)?
    var onFailure: (() -> Void)?

    private var process: Process?
    private var input: Pipe?
    private var buffer = Data()
    private var restarts = 0

    private var library: String? { Bundle.main.path(forResource: "MediaRemoteBridge", ofType: "dylib") }
    private var script: String? { Bundle.main.path(forResource: "mediaremote", ofType: "pl") }

    func start() {
        guard let library, let script else {
            onFailure?()
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script, library, "stream"]
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.restart() }
        }
        do {
            try process.run()
            self.process = process
            self.input = input
        } catch {
            onFailure?()
        }
    }

    func send(_ command: String) {
        guard let library, let script else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script, library, "send"]
        process.environment = ["NOTCHDECK_COMMAND": command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func restart() {
        process = nil
        restarts += 1
        // Give up after repeated crashes and fall back to scripting.
        guard restarts < 4 else {
            onFailure?()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(restarts) * 2) { [weak self] in self?.start() }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if object["error"] != nil {
                restarts = 99
                process?.terminate()
                onFailure?()
                return
            }
            restarts = 0
            var update = Update()
            update.playing = (object["playing"] as? NSNumber)?.boolValue ?? false
            update.bundleID = object["bundle"] as? String
            update.title = object["title"] as? String
            update.artist = object["artist"] as? String
            update.album = object["album"] as? String
            update.duration = object["duration"] as? Double
            update.elapsed = object["elapsed"] as? Double
            update.rate = object["rate"] as? Double
            update.timestamp = (object["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:))
            update.artwork = (object["artwork"] as? String).flatMap { Data(base64Encoded: $0) }
            update.artworkHash = object["artworkHash"] as? String
            update.parentBundleID = object["parentBundle"] as? String
            update.mediaType = object["mediaType"] as? String
            update.isMusicApp = (object["isMusicApp"] as? NSNumber)?.boolValue
            update.genre = object["genre"] as? String
            onUpdate?(update)
        }
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
