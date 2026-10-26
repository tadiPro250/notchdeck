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

    private var bag = Set<AnyCancellable>()
    private var currentKey: String?
    private var cache: [String: ([Line], String?)] = [:]

    init(player: NowPlaying, settings: AppSettings, live: Bool = true) {
        guard live else { return }
        player.$track
            // Videos have no lyrics to find.
            .map { $0.flatMap { $0.isMusic ? ($0.identity, $0.title, $0.artist, $0.album, $0.duration) : nil } }
            .removeDuplicates { $0?.0 == $1?.0 }
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] info in
                guard let self else { return }
                guard settings.showLyrics, let info else {
                    self.lines = []
                    self.plain = nil
                    self.currentKey = nil
                    return
                }
                self.load(key: info.0, title: info.1, artist: info.2, album: info.3, duration: info.4)
            }
            .store(in: &bag)
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

    private func load(key: String, title: String, artist: String, album: String, duration: Double) {
        currentKey = key
        if let cached = cache[key] {
            lines = cached.0
            plain = cached.1
            return
        }
        lines = []
        plain = nil
        guard !title.isEmpty, !artist.isEmpty else { return }
        isLoading = true
        Task { [weak self] in
            let result = await Self.fetch(title: title, artist: artist, album: album, duration: duration)
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
            let timed = records.filter { !parse($0.syncedLyrics).isEmpty }
            let close = timed.first { record in
                guard duration > 0, let d = record.duration else { return false }
                return abs(d - duration) <= 3
            }
            if let best = close ?? timed.first { return (parse(best.syncedLyrics), best.plainLyrics) }
            plainFallback = plainFallback ?? records.first { $0.plainLyrics != nil }?.plainLyrics
        }
        return reached ? ([], plainFallback) : nil
    }

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

    /// Parses LRC: `[mm:ss.xx] words`.
    static func parse(_ lrc: String?) -> [Line] {
        guard let lrc else { return [] }
        var lines: [Line] = []
        for raw in lrc.split(separator: "\n") {
            guard raw.hasPrefix("["), let close = raw.firstIndex(of: "]") else { continue }
            let stamp = raw[raw.index(after: raw.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let minutes = Double(stamp[0]), let seconds = Double(stamp[1]) else { continue }
            let text = raw[raw.index(after: close)...].trimmingCharacters(in: .whitespaces)
            lines.append(Line(time: minutes * 60 + seconds, text: text.isEmpty ? "♪" : text))
        }
        return lines.sorted { $0.time < $1.time }
    }
}
