import Foundation

/// Watches ~/Downloads for browser downloads in progress (.crdownload from Chrome, Brave, Edge
/// and Arc; .download bundles from Safari; .part from Firefox) and announces when they finish.
final class DownloadWatcher: ObservableObject {
    struct Download: Equatable, Identifiable {
        var id: String { partialPath }
        let partialPath: String
        let name: String
        var bytes: Int64
        /// 0…1 when the browser publishes a total, nil otherwise.
        var fraction: Double?
        var bytesPerSecond: Double = 0
    }

    @Published private(set) var active: [Download] = []

    var onFinished: ((URL) -> Void)?

    private let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    private var source: DispatchSourceFileSystemObject?
    private var poll: Timer?
    private var progressToken: Any?
    private var published: [String: Progress] = [:]
    private let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial"]

    init(live: Bool = true) {
        guard live else { return }
        let fd = open(folder.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename],
                                                                   queue: .main)
            source.setEventHandler { [weak self] in self?.scan() }
            source.setCancelHandler { close(fd) }
            source.resume()
            self.source = source
        }
        // Browsers that publish NSProgress for their downloads give us a real percentage.
        progressToken = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
            let path = (progress.userInfo[.fileURLKey] as? URL)?.path ?? progress.fileURL?.path ?? ""
            DispatchQueue.main.async { self?.published[path] = progress }
            return { [weak self] in
                DispatchQueue.main.async { self?.published[path] = nil }
            }
        }
        scan()
    }

    deinit {
        if let progressToken { Progress.removeSubscriber(progressToken) }
    }

    func showPreview(_ download: Download) {
        active = [download]
    }

    private func scan() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let partials = names.filter { partialExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        let previous = Dictionary(active.map { ($0.partialPath, $0) }, uniquingKeysWith: { a, _ in a })
        var next: [Download] = []
        for name in partials {
            let path = folder.appendingPathComponent(name).path
            let bytes = Self.size(of: path)
            var download = previous[path] ?? Download(partialPath: path, name: Self.finalName(name), bytes: bytes)
            if let old = previous[path] {
                download.bytesPerSecond = max(Double(bytes - old.bytes), 0)
            }
            download.bytes = bytes
            download.fraction = fraction(for: path, name: name)
            next.append(download)
        }
        // Anything that was partial and is gone: finished (if the final file exists) or cancelled.
        for old in active where !next.contains(where: { $0.partialPath == old.partialPath }) {
            let final = folder.appendingPathComponent(old.name)
            if FileManager.default.fileExists(atPath: final.path) { onFinished?(final) }
        }
        if next != active { active = next }

        if next.isEmpty {
            poll?.invalidate()
            poll = nil
        } else if poll == nil {
            poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.scan() }
        }
    }

    private func fraction(for path: String, name: String) -> Double? {
        if let progress = published[path] ?? published.first(where: { $0.key.hasPrefix(path) })?.value,
           progress.totalUnitCount > 0 {
            return progress.fractionCompleted
        }
        // Safari keeps the totals in the bundle's Info.plist.
        if name.hasSuffix(".download"),
           let info = NSDictionary(contentsOfFile: path + "/Info.plist"),
           let done = info["DownloadEntryProgressBytesSoFar"] as? Double,
           let total = info["DownloadEntryProgressTotalToLoad"] as? Double, total > 0 {
            return done / total
        }
        return nil
    }

    private static func finalName(_ partial: String) -> String {
        var name = (partial as NSString).deletingPathExtension
        // Chrome: "Unconfirmed 123.crdownload" until it knows the name.
        if name.hasPrefix("Unconfirmed ") { name = "Download" }
        return name
    }

    private static func size(of path: String) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        }
        let enumerator = FileManager.default.enumerator(atPath: path)
        var total: Int64 = 0
        while let item = enumerator?.nextObject() as? String {
            total += (try? FileManager.default.attributesOfItem(atPath: path + "/" + item)[.size] as? Int64) ?? 0
        }
        return total
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
