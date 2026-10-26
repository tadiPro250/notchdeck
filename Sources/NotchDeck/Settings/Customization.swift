import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum BackgroundMode: String, CaseIterable, Identifiable {
    case theme, photo, slideshow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .theme: "Theme"
        case .photo: "Photo"
        case .slideshow: "Slideshow"
        }
    }
}

/// One tile on the Widgets tab.
struct WidgetItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case photo, analogClock, worldClock, weather, battery, nextEvent, countdown, stats, cat, note
        var id: String { rawValue }

        var title: String {
            switch self {
            case .photo: "Photos"
            case .analogClock: "Analog clock"
            case .worldClock: "World clock"
            case .weather: "Weather"
            case .battery: "Battery"
            case .nextEvent: "Next event"
            case .countdown: "Countdown"
            case .stats: "System"
            case .cat: "Dog"
            case .note: "Note"
            }
        }

        var symbol: String {
            switch self {
            case .photo: "photo.on.rectangle.angled"
            case .analogClock: "clock.fill"
            case .worldClock: "globe"
            case .weather: "cloud.sun.fill"
            case .battery: "battery.75"
            case .nextEvent: "calendar"
            case .countdown: "hourglass"
            case .stats: "cpu.fill"
            case .cat: "dog.fill"
            case .note: "note.text"
            }
        }

        /// Photos are twice as wide as the rest.
        /// Two tiles wide: a photo, and the dog (it and its card side by side).
        var isWide: Bool { self == .photo || self == .cat }
    }

    var id = UUID()
    var kind: Kind
    /// Photos: images in the app's library folder (one shows still, several cycle).
    var images: [String] = []
    /// World clock: a time zone identifier. Countdown and note: the title or text.
    var text: String = ""
    /// Countdown: the date counted down to.
    var date: Date?
}

/// An app or folder in the quick-launch row along the bottom of the open notch.
struct QuickItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var path: String

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "") }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    static let defaults: [QuickItem] = [
        "/System/Library/CoreServices/Finder.app",
        NSHomeDirectory() + "/Downloads",
        NSHomeDirectory() + "/Documents",
        "/Applications",
        "/System/Applications/System Settings.app",
    ].filter { FileManager.default.fileExists(atPath: $0) }.map { QuickItem(path: $0) }
}

/// Photos the user picks are copied here, so they keep working if the originals move.
enum ImageLibrary {
    static let folder: URL = {
        let url = AppSupport.folder.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let cache = NSCache<NSString, NSImage>()

    /// Copies the files in and returns their new paths.
    static func importImages(_ urls: [URL]) -> [String] {
        urls.compactMap { url in
            let target = folder.appendingPathComponent(UUID().uuidString + "." + (url.pathExtension.isEmpty ? "jpg" : url.pathExtension))
            do {
                try FileManager.default.copyItem(at: url, to: target)
                return target.path
            } catch {
                return nil
            }
        }
    }

    /// Deletes copies nobody refers to any more.
    static func prune(keeping paths: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where !paths.contains(file.path) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// A downscaled copy, cached, so large photos don't cost memory on every redraw.
    static func image(_ path: String, maxPixel: CGFloat = 1400) -> NSImage? {
        let key = "\(path)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Open panels for the notch. The notch folds away while the panel is up and reopens after.
enum FilePicker {
    static func images(multiple: Bool, completion: @escaping ([URL]) -> Void) {
        run(types: [.image], directories: false, multiple: multiple, prompt: "Choose", completion: completion)
    }

    static func appsOrFolders(completion: @escaping ([URL]) -> Void) {
        run(types: [.application, .folder], directories: true, multiple: true, prompt: "Add",
            start: URL(fileURLWithPath: "/Applications"), completion: completion)
    }

    private static func run(types: [UTType], directories: Bool, multiple: Bool, prompt: String,
                            start: URL? = nil, completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.canChooseDirectories = directories
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = multiple
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = prompt
        if let start { panel.directoryURL = start }
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            completion(response == .OK ? panel.urls : [])
        }
    }
}
