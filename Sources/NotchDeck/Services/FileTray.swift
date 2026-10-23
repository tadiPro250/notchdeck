import AppKit
import QuickLookThumbnailing

/// A shelf of file references. Files stay where they are; the tray only remembers their paths.
final class FileTray: ObservableObject {
    @Published private(set) var items: [URL] = []

    private let defaultsKey = "tray.paths"
    private let persists: Bool

    init(persists: Bool = true) {
        self.persists = persists
        guard persists else { return }
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(providers: [NSItemProvider]) {
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async { self?.add([url]) }
            }
        }
    }

    /// Where dropped files are copied when "Copy dropped files into the tray" is on.
    static let storage: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchDeck/Tray", isDirectory: true)

    func add(_ urls: [URL]) {
        let copy = persists && AppSettings.shared.copyDroppedFiles
        for url in urls {
            let stored = copy ? (Self.copyIntoStorage(url) ?? url) : url
            if !items.contains(stored) { items.append(stored) }
        }
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        Self.deleteIfStored(url)
        save()
    }

    func clear() {
        items.forEach(Self.deleteIfStored)
        items.removeAll()
        save()
    }

    private static func copyIntoStorage(_ url: URL) -> URL? {
        guard !url.path.hasPrefix(storage.path) else { return url }
        let folder = storage.appendingPathComponent(UUID().uuidString.prefix(8).description, isDirectory: true)
        let target = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }

    private static func deleteIfStored(_ url: URL) {
        guard url.path.hasPrefix(storage.path) else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func airDrop(_ urls: [URL]? = nil) {
        let targets = urls ?? items
        guard !targets.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: targets)
    }

    private func save() {
        guard persists else { return }
        UserDefaults.standard.set(items.map(\.path), forKey: defaultsKey)
    }
}

enum Thumbnails {
    static func image(for url: URL, size: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
}
