import Combine
import Foundation

/// Time-synced lyrics from LRCLIB (free, no account) for whatever is playing.
final class LyricsService: ObservableObject {
    struct Line: Equatable {
        let time: Double
        let text: String
    }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var plain: String?
    @Published private(set) var isLoading = false

    /// What a lookup needs from the track.
    private struct Song: Equatable {
        let identity: String
        let title: String
        let artist: String
        let album: String
        let duration: Double

        /// A lookup made before the player reported the song's length could only search, and a
        /// search can return another cut of the song (a live take, a radio edit) whose timing
        /// doesn't fit. So a song is looked up again once its length is known, and the two
        /// answers are cached apart.
        var key: String { "\(identity)|\(duration > 0 ? String(Int(duration.rounded())) : "?")" }
        var knowsLength: Bool { duration > 0 }
    }

    private var bag = Set<AnyCancellable>()
    private var settings: AppSettings?
    private var song: Song?
    private var currentKey: String?
    private var cache: [String: ([Line], String?)] = [:]

    init(player: NowPlaying, settings: AppSettings, live: Bool = true) {
        guard live else { return }
        self.settings = settings
        player.$track
            // Videos have no lyrics to find.
            .map { $0.flatMap { $0.isMusic ? Song(identity: $0.identity, title: $0.title, artist: $0.artist,
                                                   album: $0.album, duration: $0.duration) : nil } }
            .removeDuplicates { $0?.identity == $1?.identity && $0?.knowsLength == $1?.knowsLength }
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] song in self?.show(song) }
            .store(in: &bag)
        // Turning lyrics or English on or off applies to the song already playing.
        settings.$lyricsInEnglish.combineLatest(settings.$showLyrics)
            .dropFirst()
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.cache = [:]
                self.currentKey = nil
                self.show(self.song)
            }
            .store(in: &bag)
    }

    private func show(_ song: Song?) {
        let changedSong = song?.identity != self.song?.identity
        self.song = song
        guard settings?.showLyrics ?? true, let song else {
            lines = []
            plain = nil
            currentKey = nil
            isLoading = false
            return
        }
        load(song, keepShowing: !changedSong)
    }

    func showPreview(_ lines: [Line]) {
        self.lines = lines
    }

    /// Index of the line being sung at `position`, nil before the first.
    func index(at position: Double) -> Int? {
        lines.lastIndex(where: { $0.time <= position + 0.2 })
    }

    /// The line being sung at `position`, plus the next one.
    func current(at position: Double) -> (now: String?, next: String?) {
        guard let index = lines.lastIndex(where: { $0.time <= position + 0.2 }) else {
            return (nil, lines.first?.text)
        }
        let next = index + 1 < lines.count ? lines[index + 1].text : nil
        return (lines[index].text, next)
    }

    private func load(_ song: Song, keepShowing: Bool) {
        let key = song.key
        currentKey = key
        if let cached = cache[key] {
            lines = cached.0
            plain = cached.1
            isLoading = false
            return
        }
        // The same song, now with its length: keep what's on screen until the better answer lands.
        if !keepShowing {
            lines = []
            plain = nil
        }
        guard !song.title.isEmpty, !song.artist.isEmpty else {
            isLoading = false
            return
        }
        isLoading = true
        let english = settings?.lyricsInEnglish ?? false
        Task { [weak self] in
            let fetched = await Self.fetch(title: song.title, artist: song.artist, album: song.album, duration: song.duration)
            var shown = fetched
            if english, let found = fetched { shown = await Self.inEnglish(found) }
            let result = shown
            await MainActor.run {
                guard let self, self.currentKey == key else { return }
                self.isLoading = false
                // A request that failed (offline, timeout) is not an answer: don't remember it, so
                // the next time this song comes up it is asked for again.
                guard let result else { return }
                self.cache[key] = result
                self.lines = result.0
                self.plain = result.1
            }
        }
    }

    /// The same lines at the same times, in English.
    private static func inEnglish(_ found: ([Line], String?)) async -> ([Line], String?) {
        let (lines, plain) = found
        let texts = await LyricsTranslator.english(lines.map(\.text))
        let timed = zip(lines, texts).map { Line(time: $0.time, text: $1) }
        var englishPlain = plain
        if let plain {
            let rows = plain.components(separatedBy: "\n")
            englishPlain = await LyricsTranslator.english(rows).joined(separator: "\n")
        }
        return (timed, englishPlain)
    }

    private struct Record: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
        let duration: Double?
    }

    /// Asks LRCLIB in stages, each a little looser, and stops at the first synced answer:
    /// the exact match; the cleaned title with the first artist (Spotify reports "Song - Remastered
    /// 2011", "Song (feat. X)" and "A, B" as the artist); then a free-text search, preferring a
    /// timed result whose length is within a few seconds of the song's. Returns nil only when
    /// every request failed to get through.
    private static func fetch(title: String, artist: String, album: String, duration: Double) async -> ([Line], String?)? {
        let cleanTitle = cleaned(title)
        let firstArtist = primaryArtist(artist)
        var reached = false
        var plainFallback: String?

        func take(_ record: Record) -> ([Line], String?)? {
            if record.instrumental == true { return ([], nil) }
            let lines = parse(record.syncedLyrics)
            if !lines.isEmpty { return (lines, record.plainLyrics) }
            plainFallback = plainFallback ?? record.plainLyrics
            return nil
        }

        // 1 and 2: exact lookups. LRCLIB's /get wants the duration (within about 2 s).
        var attempts: [(String, String, String?)] = [(title, artist, album.isEmpty ? nil : album)]
        if cleanTitle != title || firstArtist != artist { attempts.append((cleanTitle, firstArtist, nil)) }
        for (t, a, al) in attempts where duration > 0 {
            var url = URLComponents(string: "https://lrclib.net/api/get")!
            url.queryItems = [URLQueryItem(name: "track_name", value: t), URLQueryItem(name: "artist_name", value: a),
                              URLQueryItem(name: "duration", value: String(Int(duration.rounded())))]
            if let al { url.queryItems?.append(URLQueryItem(name: "album_name", value: al)) }
            let (record, ok): (Record?, Bool) = await get(url.url!)
            reached = reached || ok
            if let record, let result = take(record) { return result }
        }

        // 3: searches, field-wise and then free text.
        var searches: [[URLQueryItem]] = [[URLQueryItem(name: "track_name", value: cleanTitle),
                                           URLQueryItem(name: "artist_name", value: firstArtist)]]
        searches.append([URLQueryItem(name: "q", value: "\(cleanTitle) \(firstArtist)")])
        for query in searches {
            var url = URLComponents(string: "https://lrclib.net/api/search")!
            url.queryItems = query
            let (records, ok): ([Record]?, Bool) = await get(url.url!)
            reached = reached || ok
            guard let records, !records.isEmpty else { continue }
            let timed = records.compactMap { record -> (Record, [Line])? in
                let lines = parse(record.syncedLyrics)
                return lines.isEmpty ? nil : (record, lines)
            }
            plainFallback = plainFallback ?? records.first { $0.plainLyrics != nil }?.plainLyrics
            guard duration > 0 else {
                // Length unknown: the best guess for now. It is asked again once the length arrives.
                if let first = timed.first { return (first.1, first.0.plainLyrics) }
                continue
            }
            // The timed version closest in length, and only if it's the same cut: lyrics timed
            // to a version 20 s longer drift further out of step with every verse.
            let closest = timed
                .compactMap { pair in pair.0.duration.map { (pair, abs($0 - duration)) } }
                .min { $0.1 < $1.1 }
            if let (pair, gap) = closest, gap <= Self.sameCut { return (pair.1, pair.0.plainLyrics) }
        }
        return reached ? ([], plainFallback) : nil
    }

    /// How far a search result's length may be from the song's and still be the same recording.
    static let sameCut: Double = 5

    /// "Song - Remastered 2011", "Song (feat. X)", "Song - Radio Edit" -> "Song".
    static func cleaned(_ title: String) -> String {
        var t = title.replacingOccurrences(of: #"\s*[\(\[](feat\.?|ft\.?|with|from)\s[^\)\]]*[\)\]]"#, with: "",
                                           options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*(remaster|version|edit|live|mix|mono|stereo|bonus|demo)[^\)\]]*[\)\]]"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s+-\s+.*(remaster|version|edit|live|mix|mono|stereo|from|bonus|demo).*$"#, with: "",
                                   options: [.regularExpression, .caseInsensitive])
        let trimmed = t.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    /// "A, B", "A & B", "A feat. B", "A x B" -> "A".
    static func primaryArtist(_ artist: String) -> String {
        let first = artist.components(separatedBy: CharacterSet(charactersIn: ",&;"))[0]
            .replacingOccurrences(of: #"\s+(feat\.?|ft\.?|x|with)\s+.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        return first.isEmpty ? artist : first
    }

    /// The decoded body, and whether the server answered at all (a 404 is an answer: no lyrics).
    private static func get<T: Decodable>(_ url: URL) async -> (T?, Bool) {
        var request = URLRequest(url: url)
        request.setValue("NotchDeck (https://github.com)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        for attempt in 0..<2 {
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let status = (response as? HTTPURLResponse)?.statusCode {
                return (status == 200 ? try? JSONDecoder().decode(T.self, from: data) : nil, status < 500)
            }
            if attempt == 0 { try? await Task.sleep(nanoseconds: 700_000_000) }
        }
        return (nil, false)
    }

    /// Parses LRC: `[mm:ss.xx] words`. A repeated line may carry several stamps
    /// (`[00:12.00][01:40.50] chorus`); `[offset:+250]` shifts every line (positive is earlier,
    /// in milliseconds); word stamps (`<00:12.40>`) are dropped; `[mm:ss:xx]` is read too.
    static func parse(_ lrc: String?) -> [Line] {
        guard let lrc else { return [] }
        var lines: [Line] = []
        var offset = 0.0
        for row in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(row.trimmingCharacters(in: .whitespaces))
            var stamps: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = stamp(tag) {
                    stamps.append(time)
                } else if tag.lowercased().hasPrefix("offset:"),
                          let ms = Double(tag.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces)) {
                    offset = ms / 1000
                }
                rest = rest[rest.index(after: close)...]
            }
            guard !stamps.isEmpty else { continue }
            let text = rest
                .replacingOccurrences(of: #"<\d+:\d+(?:[.:]\d+)?>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            for time in stamps {
                lines.append(Line(time: time, text: text.isEmpty ? "♪" : text))
            }
        }
        return lines
            .map { Line(time: max(0, $0.time - offset), text: $0.text) }
            .sorted { $0.time < $1.time }
    }

    /// "01:02.50" or "01:02:50" -> 62.5 seconds; nil for a tag like "ar:Artist".
    private static func stamp(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3, let minutes = Double(parts[0]) else { return nil }
        if parts.count == 2 {
            guard let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        }
        guard let seconds = Double(parts[1]), let hundredths = Double(parts[2]) else { return nil }
        return minutes * 60 + seconds + hundredths / pow(10, Double(parts[2].count))
    }
}
