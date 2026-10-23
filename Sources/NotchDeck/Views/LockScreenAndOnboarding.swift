import AVFoundation
import EventKit
import SwiftUI

/// Shown on the lock screen: what's playing (with controls), battery and weather.
struct LockScreenView: View {
    @ObservedObject var player: NowPlaying
    @ObservedObject var system: SystemStatus
    @ObservedObject var weather: WeatherService
    @ObservedObject var settings: AppSettings

    var body: some View {
        let accent = settings.accent(artwork: player.artworkAccent)
        VStack(spacing: 10) {
            if let track = player.track {
                HStack(spacing: 14) {
                    ArtworkView(image: player.artwork, size: 64, corner: 12)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(track.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            LevelBar(level: track.duration > 0 ? track.position(at: context.date) / track.duration : 0,
                                     color: accent)
                                .frame(height: 4)
                        }
                        .padding(.top, 4)
                    }
                    HStack(spacing: 14) {
                        MediaButton(symbol: "backward.fill", size: 14) { player.previous() }
                        MediaButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 20) { player.playPause() }
                        MediaButton(symbol: "forward.fill", size: 14) { player.next() }
                    }
                }
            }
            HStack(spacing: 16) {
                if let level = system.batteryLevel {
                    Label("\(level)%", systemImage: system.isCharging ? "battery.100.bolt" : "battery.75")
                }
                if let w = weather.weather {
                    Label("\(Int(w.temperature.rounded()))° \(w.summary)", systemImage: w.symbol)
                        .symbolRenderingMode(.multicolor)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// First launch: what NotchDeck does, and the permissions behind each feature.
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(settings: AppSettings, onOpenSettings: @escaping () -> Void) {
        let view = OnboardingView(settings: settings, close: { [weak self] in
            settings.onboarded = true
            self?.window?.close()
        }, openSettings: { [weak self] in
            settings.onboarded = true
            self?.window?.close()
            onOpenSettings()
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    let close: () -> Void
    let openSettings: () -> Void
    @StateObject private var refresh = ViewState<Int>(0)

    private struct Permission: Identifiable {
        let id: String
        let symbol: String
        let tint: Color
        let title: String
        let detail: String
        let granted: () -> Bool
        let request: () -> Void
    }

    private var permissions: [Permission] {
        func open(_ anchor: String) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
        }
        return [
            Permission(id: "ax", symbol: "keyboard.fill", tint: .blue, title: "Accessibility",
                       detail: "Replaces the macOS volume and brightness pop-up with the notch.",
                       granted: { MediaKeyInterceptor.isTrusted }, request: { open("Privacy_Accessibility") }),
            Permission(id: "cal", symbol: "calendar", tint: .red, title: "Calendars",
                       detail: "Your events, meeting countdowns and reminders before they start.",
                       granted: { EKEventStore.authorizationStatus(for: .event) == .fullAccess },
                       request: { EKEventStore().requestFullAccessToEvents { _, _ in } }),
            Permission(id: "rem", symbol: "checklist", tint: .orange, title: "Reminders",
                       detail: "The To-do list in Desk, and alerts when a reminder is due.",
                       granted: { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess },
                       request: { EKEventStore().requestFullAccessToReminders { _, _ in } }),
            Permission(id: "cam", symbol: "camera.fill", tint: .green, title: "Camera",
                       detail: "The Mirror tab. The camera only runs while that tab is open.",
                       granted: { AVCaptureDevice.authorizationStatus(for: .video) == .authorized },
                       request: { AVCaptureDevice.requestAccess(for: .video) { _ in } }),
            Permission(id: "fda", symbol: "moon.fill", tint: .indigo, title: "Full Disk Access (optional)",
                       detail: "Lets NotchDeck see which Focus mode is on, for the Focus live activity.",
                       granted: { FileManager.default.isReadableFile(atPath: NSHomeDirectory() + "/Library/DoNotDisturb/DB/Assertions.json") },
                       request: { open("Privacy_AllFiles") }),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to NotchDeck").font(.system(size: 24, weight: .bold))
                    Text("Hover the notch (or press \(settings.hotKey.title)) to open it. Drag files onto it to stash them.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 20)

            Text("PERMISSIONS").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(permissions.enumerated()), id: \.element.id) { index, permission in
                    if index > 0 { Divider() }
                    HStack(spacing: 12) {
                        Image(systemName: permission.symbol)
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(permission.tint.gradient))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(permission.title).font(.system(size: 13, weight: .semibold))
                            Text(permission.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if permission.granted() {
                            Label("Allowed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 12, weight: .medium))
                        } else {
                            Button("Allow") {
                                permission.request()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { refresh.value += 1 }
                            }
                        }
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 14)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
            .id(refresh.value)

            Text("Spotify, Music, Bluetooth and your Downloads folder ask the first time they're used. Everything can be turned off in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            Spacer(minLength: 16)
            HStack {
                Button("Open Settings", action: openSettings)
                Spacer()
                Button("Get Started", action: close)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 620, height: 560)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in refresh.value += 1 }
    }
}
