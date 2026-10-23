import AppKit
import SwiftUI

/// `NotchDeck --render-previews <dir>` draws each state of the notch to a PNG with sample data,
/// without opening a window. Useful for checking layout and for the README.
@MainActor
enum Previews {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                     notchSize: CGSize(width: 179, height: 32), hasNotch: true)
        let artwork = sampleArtwork()
        let track = Track(title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming",
                          duration: 243, position: 87, isPlaying: true, player: .spotify,
                          artworkURL: nil, fetchedAt: Date())

        let cases: [(String, (NotchModel, NowPlaying, FileTray) -> Void)] = [
            ("1-live", { model, player, _ in
                player.showPreview(track, artwork: artwork, accent: Color(red: 1, green: 0.55, blue: 0.75))
                model.isPlaying = true
            }),
            ("2-hud-volume", { model, _, _ in model.flashHUD(HUDState(kind: .volume(muted: false), level: 0.62)) }),
            ("3-home", { model, player, tray in
                player.showPreview(track, artwork: artwork, accent: Color(red: 1, green: 0.55, blue: 0.75))
                tray.add(sampleFiles())
                model.setExpanded(true)
                model.tab = .home
            }),
            ("4-home-idle", { model, _, _ in
                model.setExpanded(true)
                model.tab = .home
            }),
            ("5-tray", { model, _, tray in
                tray.add(sampleFiles())
                model.setExpanded(true)
                model.tab = .tray
            }),
            ("6-tray-empty", { model, _, _ in
                model.setExpanded(true)
                model.tab = .tray
            }),
            ("7-controls", { model, _, _ in
                model.setExpanded(true)
                model.tab = .controls
            }),
        ]

        for (name, configure) in cases {
            let model = NotchModel(geometry: geometry)
            let player = NowPlaying(live: false)
            let tray = FileTray(persists: false)
            configure(model, player, tray)
            let view = NotchRootView(model: model, player: player, tray: tray, volume: VolumeControl(),
                                     brightness: BrightnessControl(), system: SystemStatus(),
                                     actions: QuickActions())
                .frame(width: NotchController.windowSize.width, height: NotchController.windowSize.height)
                // A stand-in menu bar and wallpaper so the black shape is visible.
                .background(
                    VStack(spacing: 0) {
                        Color(red: 0.86, green: 0.87, blue: 0.9).frame(height: 32)
                        LinearGradient(colors: [Color(red: 0.35, green: 0.45, blue: 0.75),
                                                Color(red: 0.75, green: 0.5, blue: 0.7)],
                                       startPoint: .top, endPoint: .bottom)
                    })
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("failed: \(name)")
                continue
            }
            let url = directory.appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print(url.path)
        }
    }

    private static func sampleArtwork() -> NSImage {
        NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            let gradient = NSGradient(colors: [NSColor(red: 0.95, green: 0.3, blue: 0.55, alpha: 1),
                                               NSColor(red: 0.35, green: 0.2, blue: 0.75, alpha: 1)])
            gradient?.draw(in: rect, angle: -45)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 110, dy: 110)).fill()
            return true
        }
    }

    private static func sampleFiles() -> [URL] {
        ["/System/Applications/Calculator.app", "/System/Library/CoreServices/Finder.app",
         "/Library/Desktop Pictures", "/etc/hosts", "/System/Applications/Notes.app"]
            .map { URL(fileURLWithPath: $0) }
    }
}
