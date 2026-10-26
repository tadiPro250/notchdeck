import AppKit
import CoreAudio
import SwiftUI

/// `NotchDeck --render-previews <dir>` draws every state of the notch to PNGs with sample data,
/// without opening a window or touching preferences.
@MainActor
enum Previews {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "com.premprateek.notchdeck.previews"
        UserDefaults().removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.weatherCity = "Hyderabad"
        settings.scriptCommand = "git status -sb"
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let notched = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                    notchSize: CGSize(width: 179, height: 32), hasNotch: true)
        let island = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                   notchSize: CGSize(width: 150, height: 28), hasNotch: false, isIsland: true)
        let services = sampleServices(settings: settings)

        func shot(_ name: String, theme: String = "midnight", geometry: NotchGeometry? = nil,
                  configure: (NotchModel) -> Void) {
            settings.themeID = theme
            let model = NotchModel(geometry: geometry ?? notched, settings: settings)
            configure(model)
            let view = NotchRootView(model: model, services: services, settings: settings, player: services.player)
                .frame(width: NotchController.windowSize.width, height: NotchController.windowSize.height)
                .background(desktop)
            save(view, name: name, size: NotchController.windowSize, to: directory)
        }

        // Closed notch
        shot("a01-live-privacy") {
            $0.isPlaying = true
            $0.privacy = PrivacyState(camera: true, microphone: true)
        }
        shot("a02-hud-volume") { $0.flashHUD(HUDState(kind: .volume(muted: false), level: 0.62)) }
        shot("a03-hud-keyboard") { $0.flashHUD(HUDState(kind: .keyboard, level: 0.4)) }
        settings.hudStyle = .bar
        shot("a04-hud-bar-external") { $0.flashHUD(HUDState(kind: .externalBrightness, level: 0.7)) }
        settings.hudStyle = .wings
        shot("a05-airpods-battery") {
            $0.showActivity(ActivityState(symbol: "airpodspro", title: "Prem's AirPods Pro",
                                          detail: "L 85% · R 80% · Case 60%", tint: .green, progress: 0.8))
        }
        shot("a06-focus") {
            $0.showActivity(ActivityState(symbol: "briefcase.fill", title: "Work", detail: "On", tint: .indigo, progress: nil))
        }
        shot("a07-download-done") {
            $0.showActivity(ActivityState(symbol: "arrow.down.circle.fill", title: "Figma-Installer.dmg",
                                          detail: "Downloaded · added to the tray", tint: .blue, progress: 1))
        }
        shot("a08-reminder-due") {
            $0.showActivity(ActivityState(symbol: "checklist", title: "Call the bank", detail: "Reminder · Personal",
                                          tint: .orange, progress: nil))
        }
        shot("a09-alarm-ringing") {
            $0.ringing = Ringing(kind: .alarm(Alarm(hour: 7, minute: 30, label: "Gym")))
        }
        shot("a10-timer-ringing") { $0.ringing = Ringing(kind: .timer) }
        services.timer.showPreview(remaining: 754, of: 1500)
        shot("a11-timer") { $0.timerActive = true }
        services.timer.cancel()
        services.clock.showPreview(stopwatch: 83.4)
        shot("a12-stopwatch") { $0.stopwatchActive = true }
        services.clock.resetStopwatch()
        shot("a13-countdown") { $0.countdown = services.calendar.events.first }
        shot("a14-download-progress") { $0.downloading = true }
        shot("a15-privacy") { $0.privacy = PrivacyState(camera: true, screen: true, micMuted: true) }
        shot("a16-island-live", geometry: island) { $0.isPlaying = true }
        shot("a17-island-closed", geometry: island) { _ in }

        // Open notch, every tab
        for (index, tab) in NotchTab.allCases.enumerated() {
            shot("b\(index)-\(tab.rawValue)", theme: "aurora") {
                $0.setExpanded(true)
                $0.tab = tab
            }
        }
        shot("c1-island-open", theme: "ocean", geometry: island) { $0.setExpanded(true) }

        // Tasks, Pomodoro, colours.
        shot("e1-tasks", theme: "midnight") {
            $0.setExpanded(true)
            $0.tab = .tasks
        }
        shot("e2-overdue") { $0.overdueTask = services.tasks.overdue }
        shot("e3-nudge") { $0.nudge = services.tasks.overdue }
        services.pomodoro.showPreview(phase: .work, remaining: 14 * 60 + 32, round: 2)
        shot("e4-pomodoro") { $0.pomodoroActive = true }
        shot("e5-clock-focus", theme: "ember") {
            $0.setExpanded(true)
            $0.tab = .clock
        }
        shot("e6-color-picked") {
            $0.showActivity(ActivityState(symbol: "eyedropper", title: "#FF6FA8", detail: "Copied · Saved to Colours · rgb(255, 111, 168)",
                                          tint: .pink, progress: nil, swatch: "#FF6FA8"))
        }
        shot("e7-desk-colours", theme: "graphite") {
            $0.setExpanded(true)
            $0.tab = .desk
            $0.deskSection = .colors
        }

        let pickerModel = NotchModel(geometry: notched, settings: settings)
        let picker = DeadlinePicker(model: pickerModel, current: Date().addingTimeInterval(3 * 86400 + 4 * 3600 + 30 * 60)) { _ in }
            .padding(12)
            .frame(width: 300)
            .background(Color(white: 0.12))
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
        save(picker, name: "e8-deadline-picker", size: CGSize(width: 300, height: 240), to: directory)

        // Lock screen, playing and paused.
        for playing in [true, false] {
            if !playing {
                services.player.showPreview(Track(title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming",
                                                  duration: 243, position: 87, isPlaying: false, player: .spotify,
                                                  bundleID: "com.spotify.client", appName: "Spotify", artworkURL: nil,
                                                  fetchedAt: Date()),
                                            artwork: sampleArtwork(), accent: Color(red: 1, green: 0.55, blue: 0.75))
            }
            let screen = CGSize(width: 1512, height: 982)
            let lock = LockScreenView(player: services.player, lyrics: services.lyrics, system: services.system,
                                      weather: services.weather, settings: settings)
                .frame(width: screen.width, height: screen.height)
            save(lock, name: playing ? "d1-lock-playing" : "d2-lock-paused", size: screen, to: directory)
        }

        // The cat in every pose.
        let cats = HStack(spacing: 20) {
            ForEach(Array([CatBrain.Pose.walk, .sit, .sleep, .eat].enumerated()), id: \.offset) { index, pose in
                CatFigure(pose: pose, mood: index == 1 ? .happy : .content, color: CatColor.allCases[index], time: 1.3)
                    .frame(width: 150, height: 108)
            }
        }
        .padding(20)
        .background(Color(white: 0.25))
        save(cats, name: "d3-cats", size: CGSize(width: 700, height: 150), to: directory)

        // The newer poses, and the dog fat, sick and lonely.
        let more: [(CatBrain.Pose, CatBrain.Mood, Double)] = [
            (.lie, .content, 1), (.stretch, .happy, 1), (.sniff, .content, 1), (.scratch, .content, 1),
            (.bark, .hungry, 1), (.walk, .content, 1.5), (.sick, .sick, 1), (.vomit, .stuffed, 1.3), (.lie, .lonely, 1),
        ]
        let poses = HStack(spacing: 14) {
            ForEach(Array(more.enumerated()), id: \.offset) { index, item in
                CatFigure(pose: item.0, mood: item.1, color: CatColor.allCases[index % 4], time: 1.3, girth: item.2)
                    .frame(width: 120, height: 86)
            }
        }
        .padding(16)
        .background(Color(white: 0.25))
        save(poses, name: "d4-dog-poses", size: CGSize(width: 1250, height: 120), to: directory)

        // The dog's card, as it hangs over the desktop pet (its window allots 90 pt to it).
        let card = VStack(spacing: 0) {
            CatCard(brain: CatBrain(settings: AppSettings(defaults: UserDefaults(suiteName: "notchdeck.previews.card") ?? .standard),
                                    live: false), name: "Mochi", compact: true)
                .frame(height: 90)
        }
        .padding(20)
        .background(Color(white: 0.25))
        .environment(\.colorScheme, .dark)
        save(card, name: "d5-dog-card", size: CGSize(width: 300, height: 130), to: directory)
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
                                 bundleID: "com.spotify.client", appName: "Spotify", artworkURL: nil, fetchedAt: Date()),
                           artwork: sampleArtwork(), accent: Color(red: 1, green: 0.55, blue: 0.75))
        let lyrics = LyricsService(player: player, settings: settings, live: false)
        lyrics.showPreview([.init(time: 0, text: "Waiting in a car"), .init(time: 80, text: "Waiting for a ride in the dark"),
                            .init(time: 95, text: "The night city grows")])
        let tray = FileTray(persists: false)
        tray.add(["/System/Applications/Calculator.app", "/System/Library/CoreServices/Finder.app",
                  "/etc/hosts", "/System/Applications/Notes.app"].map { URL(fileURLWithPath: $0) })
        let system = SystemStatus(live: false)
        system.showPreview(level: 64, charging: true)
        let calendar = CalendarService(live: false)
        let now = Date()
        calendar.showPreview([
            CalendarEvent(id: "1", title: "Design review", start: now.addingTimeInterval(240),
                          end: now.addingTimeInterval(3600), isAllDay: false, color: .orange, location: "Room 4B",
                          joinURL: URL(string: "https://meet.google.com/abc-defg-hij")),
            CalendarEvent(id: "2", title: "Lunch with Ayush", start: now.addingTimeInterval(9000),
                          end: now.addingTimeInterval(12600), isAllDay: false, color: .green, location: nil),
        ])
        let reminders = RemindersService(live: false)
        reminders.showPreview([
            ReminderItem(id: "r1", title: "Call the bank", due: now.addingTimeInterval(-600), listName: "Personal",
                         color: .orange, priority: 1),
            ReminderItem(id: "r2", title: "Send the W9 report", due: now.addingTimeInterval(7200), listName: "Work",
                         color: .blue, priority: 0),
        ])
        let weather = WeatherService(settings: settings, live: false)
        weather.showPreview(Weather(city: "Hyderabad", temperature: 27, high: 31, low: 21, code: 2, isDay: true,
                                    unit: .celsius))
        let clipboard = ClipboardHistory(settings: settings, live: false)
        clipboard.showPreview([.text("ssh deploy@staging.internal"),
                               .text("https://github.com/TheBoredTeam/boring.notch"),
                               .text("Meeting moved to 4:30, same room."),
                               .file(URL(fileURLWithPath: "/System/Applications/Notes.app"))], pinnedFirst: true)
        let stats = SystemStats(live: false)
        stats.showPreview(cpu: 0.23, gpu: 0.41, gpuCores: 10, memory: 0.68, memoryUsedGB: 10.9, disk: 0.71, diskFreeGB: 142)
        stats.showPreview(network: (down: 2_400_000, up: 180_000), battery: (health: 0.96, cycles: 87, temperature: 31.4))
        let timer = FocusTimer()
        let clock = ClockCenter(timer: timer, settings: settings, live: false)
        clock.alarms = [Alarm(hour: 7, minute: 0, label: "Wake up", repeatDays: [2, 3, 4, 5, 6]),
                        Alarm(hour: 18, minute: 30, label: "Gym", repeatDays: [], enabled: false)]
        let downloads = DownloadWatcher(live: false)
        downloads.showPreview(.init(partialPath: "/x.crdownload", name: "Figma-Installer.dmg", bytes: 84_000_000, fraction: 0.42))
        let accessories = AccessoryBatteries()
        accessories.showPreview([
            .init(name: "Prem's AirPods Pro", symbol: "airpodspro", main: nil, left: 85, right: 80, caseLevel: 60),
            .init(name: "Magic Mouse", symbol: "computermouse.fill", main: 18, left: nil, right: nil, caseLevel: nil),
        ])
        let audio = AudioDevices(live: false)
        audio.showPreview(outputs: [.init(id: 1, name: "MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn)],
                          current: 1)
        let shortcuts = ShortcutsService()
        shortcuts.showPreview(["Start Focus", "Resize Images", "Log Water", "Send ETA", "Clean Downloads"])
        let script = ScriptRunner(settings: settings)
        script.showPreview("## main...origin/main [ahead 2]\n M Sources/NotchDeck/App.swift\n?? Helpers/")
        let notes = NotesStore(live: false)
        notes.text = "Ideas: lyrics karaoke mode\nBuy: milk, coffee"
        let tasks = TaskStore(settings: settings, live: false)
        let hour: TimeInterval = 3600
        tasks.showPreview([
            TaskItem(title: "Forson's Flyers", due: now.addingTimeInterval(-1.31 * hour), spent: 2.1 * hour),
            TaskItem(title: "Ntifafa Hotel Artworks", due: now.addingTimeInterval(41 * 60),
                     steps: [TaskStep(title: "Get logo from hotel")]),
            TaskItem(title: "Go through Jova's application", due: now.addingTimeInterval(3.7 * hour)),
            TaskItem(title: "Generate newsletter", due: now.addingTimeInterval(-3 * hour), doneAt: now.addingTimeInterval(-hour),
                     spent: 2.05 * hour),
        ], focused: 6.37 * hour)
        let pomodoro = PomodoroTimer(settings: settings, live: false)
        let colors = ColorDropper(settings: settings, live: false)
        colors.showPreview(["#FF6FA8", "#1DD1A1", "#54A0FF", "#FECA57", "#A29BFE", "#2E3440", "#F5F5F7", "#FF9F43"])
        return NotchServices(
            settings: settings, player: player, lyrics: lyrics, tray: tray, volume: VolumeControl(),
            brightness: BrightnessControl(), system: system, actions: QuickActions(), calendar: calendar,
            reminders: reminders, weather: weather, clipboard: clipboard, stats: stats, timer: timer, clock: clock,
            camera: CameraMirror(), downloads: downloads, focus: FocusWatcher(live: false),
            privacy: PrivacyMonitor(live: false), accessories: accessories, audio: audio,
            displays: ExternalDisplays(live: false), keyboard: KeyboardBacklight(live: false), notes: notes,
            shortcuts: shortcuts, script: script, updates: UpdateChecker(),
            cat: CatBrain(settings: settings, live: false),
            tasks: tasks, pomodoro: pomodoro, colors: colors)
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
