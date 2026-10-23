import AppKit
import SwiftUI

/// `NotchDeck --render-previews <dir>` draws each state of the notch, every theme, and the
/// Settings window to PNGs with sample data, without opening a window or touching preferences.
@MainActor
enum Previews {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "com.premprateek.notchdeck.previews"
        UserDefaults().removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.weatherCity = "Hyderabad"
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                     notchSize: CGSize(width: 179, height: 32), hasNotch: true)
        let services = sampleServices(settings: settings)

        func shot(_ name: String, theme: String = "midnight", configure: (NotchModel) -> Void) {
            settings.themeID = theme
            let model = NotchModel(geometry: geometry, settings: settings)
            configure(model)
            let view = NotchRootView(model: model, services: services, settings: settings, player: services.player)
                .frame(width: NotchController.windowSize.width, height: NotchController.windowSize.height)
                .background(desktop)
            save(view, name: name, size: NotchController.windowSize, to: directory)
        }

        shot("01-live") { $0.isPlaying = true }
        shot("02-hud-wings") { $0.flashHUD(HUDState(kind: .volume(muted: false), level: 0.62)) }
        settings.hudStyle = .bar
        shot("03-hud-bar") { $0.flashHUD(HUDState(kind: .brightness, level: 0.4)) }
        settings.hudStyle = .wings
        shot("04-activity-charging") {
            $0.showActivity(ActivityState(symbol: "bolt.fill", title: "Charging", detail: "64%", tint: .green, progress: 0.64))
        }
        shot("05-activity-airpods") {
            $0.showActivity(ActivityState(symbol: "airpodspro", title: "Prem's AirPods Pro", detail: "Connected",
                                          tint: .blue, progress: nil))
        }
        services.timer.showPreview(remaining: 754, of: 1500)
        shot("06-timer") { $0.timerActive = true }
        services.timer.cancel()

        for tab in NotchTab.allCases {
            shot("1\(NotchTab.allCases.firstIndex(of: tab)!)-\(tab.rawValue)", theme: "aurora") {
                $0.setExpanded(true)
                $0.tab = tab
            }
        }
        for theme in Theme.all {
            shot("2-theme-\(theme.id)", theme: theme.id) {
                $0.setExpanded(true)
                $0.tab = .home
            }
        }
        settings.glanceWidget = .weather
        shot("30-glance-weather", theme: "ocean") { $0.setExpanded(true) }
        settings.glanceWidget = .calendar
        shot("31-glance-calendar", theme: "ember") { $0.setExpanded(true) }
        settings.glanceWidget = .stats
        shot("32-glance-stats", theme: "forest") { $0.setExpanded(true) }

        let settingsView = SettingsView(settings: settings)
            .frame(width: 760, height: 540)
            .background(Color(nsColor: .windowBackgroundColor))
        save(settingsView, name: "40-settings", size: CGSize(width: 760, height: 540), to: directory)
    }

    private static func save<V: View>(_ view: V, name: String, size: CGSize, to directory: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("failed: \(name)")
            return
        }
        let url = directory.appendingPathComponent("\(name).png")
        try? png.write(to: url)
        print(url.path)
    }

    /// A stand-in menu bar and wallpaper so the black shape is visible.
    private static var desktop: some View {
        VStack(spacing: 0) {
            Color(red: 0.86, green: 0.87, blue: 0.9).frame(height: 32)
            LinearGradient(colors: [Color(red: 0.35, green: 0.45, blue: 0.75), Color(red: 0.75, green: 0.5, blue: 0.7)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private static func sampleServices(settings: AppSettings) -> NotchServices {
        let player = NowPlaying(live: false)
        player.showPreview(Track(title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming",
                                 duration: 243, position: 87, isPlaying: true, player: .spotify,
                                 artworkURL: nil, fetchedAt: Date()),
                           artwork: sampleArtwork(), accent: Color(red: 1, green: 0.55, blue: 0.75))
        let tray = FileTray(persists: false)
        tray.add(["/System/Applications/Calculator.app", "/System/Library/CoreServices/Finder.app",
                  "/etc/hosts", "/System/Applications/Notes.app"].map { URL(fileURLWithPath: $0) })
        let system = SystemStatus(live: false)
        system.showPreview(level: 64, charging: true)
        let calendar = CalendarService(live: false)
        let now = Date()
        calendar.showPreview([
            CalendarEvent(id: "1", title: "Design review", start: now.addingTimeInterval(1500),
                          end: now.addingTimeInterval(4200), isAllDay: false, color: .orange, location: "Room 4B"),
            CalendarEvent(id: "2", title: "Lunch with Ayush", start: now.addingTimeInterval(9000),
                          end: now.addingTimeInterval(12600), isAllDay: false, color: .green, location: nil),
            CalendarEvent(id: "3", title: "Gym", start: now.addingTimeInterval(30000),
                          end: now.addingTimeInterval(33600), isAllDay: false, color: .purple, location: nil),
        ])
        let weather = WeatherService(settings: settings, live: false)
        weather.showPreview(Weather(city: "Hyderabad", temperature: 27, high: 31, low: 21, code: 2, isDay: true,
                                    unit: .celsius))
        let clipboard = ClipboardHistory(settings: settings, live: false)
        clipboard.showPreview([.text("https://github.com/TheBoredTeam/boring.notch"),
                               .text("Meeting moved to 4:30, same room. Bring the printed deck please."),
                               .file(URL(fileURLWithPath: "/System/Applications/Notes.app")),
                               .image(sampleArtwork())])
        let stats = SystemStats(live: false)
        stats.showPreview(cpu: 0.23, gpu: 0.41, gpuCores: 10, memory: 0.68, memoryUsedGB: 10.9, disk: 0.71, diskFreeGB: 142)
        return NotchServices(settings: settings, player: player, tray: tray, volume: VolumeControl(),
                             brightness: BrightnessControl(), system: system, actions: QuickActions(),
                             calendar: calendar, weather: weather, clipboard: clipboard, stats: stats,
                             timer: FocusTimer(), camera: CameraMirror())
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
}
