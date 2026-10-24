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
            .map { $0.map { ($0.identity, $0.title, $0.artist, $0.album, $0.duration) } }
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
    }

    private static func fetch(title: String, artist: String, album: String, duration: Double) async -> ([Line], String?) {
        var exact = URLComponents(string: "https://lrclib.net/api/get")!
        exact.queryItems = [URLQueryItem(name: "track_name", value: title),
                            URLQueryItem(name: "artist_name", value: artist)]
        if !album.isEmpty { exact.queryItems?.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { exact.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }

        if let record: Record = await get(exact.url!) {
            return (parse(record.syncedLyrics), record.plainLyrics)
        }
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [URLQueryItem(name: "track_name", value: title),
                             URLQueryItem(name: "artist_name", value: artist)]
        if let records: [Record] = await get(search.url!),
           let best = records.first(where: { $0.syncedLyrics != nil }) ?? records.first {
            return (parse(best.syncedLyrics), best.plainLyrics)
        }
        return ([], nil)
    }

    private static func get<T: Decodable>(_ url: URL) async -> T? {
        var request = URLRequest(url: url)
        request.setValue("NotchDeck (https://github.com)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
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
