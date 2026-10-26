import AppKit

/// File and app icons, looked up once each. `NSWorkspace.icon(forFile:)` reads the disk, and the
/// views that show icons redraw whenever any setting changes (every step of a slider in
/// Settings), so looking them up in `body` each time adds up.
enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(forFile path: String) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}
