import AppKit
import ServiceManagement
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, modules, media, activities, tray, weather, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .modules: "Modules"
        case .media: "Media & HUD"
        case .activities: "Live Activities"
        case .tray: "Tray & Clipboard"
        case .weather: "Weather"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .modules: "square.grid.2x2.fill"
        case .media: "speaker.wave.2.fill"
        case .activities: "bell.badge.fill"
        case .tray: "tray.full.fill"
        case .weather: "cloud.sun.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: .pink
        case .modules: .indigo
        case .media: .orange
        case .activities: .red
        case .tray: .blue
        case .weather: .cyan
        case .about: .secondary
        }
    }
}

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingView(rootView: SettingsView(settings: .shared))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "NotchDeck Settings"
            window.titlebarAppearsTransparent = true
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var pane = ViewState<SettingsPane>(.appearance)

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 15, weight: .semibold))
                    Text("NotchDeck").font(.system(size: 15, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.top, 38)
                .padding(.bottom, 14)
                ForEach(SettingsPane.allCases) { item in
                    Button { pane.value = item } label: {
                        HStack(spacing: 9) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(item.tint.gradient))
                            Text(item.title).font(.system(size: 13))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(pane.value == item ? Color.accentColor.opacity(0.18) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(width: 210)
            .background(.regularMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(pane.value.title)
                        .font(.system(size: 22, weight: .bold))
                        .padding(.bottom, 14)
                    content
                }
                .padding(.horizontal, 28)
                .padding(.top, 38)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 760, minHeight: 540)
    }

    @ViewBuilder
    private var content: some View {
        switch pane.value {
        case .general: GeneralPane(settings: settings)
        case .appearance: AppearancePane(settings: settings)
        case .modules: ModulesPane(settings: settings)
        case .media: MediaPane(settings: settings)
        case .activities: ActivitiesPane(settings: settings)
        case .tray: TrayPane(settings: settings)
        case .weather: WeatherPane(settings: settings)
        case .about: AboutPane()
        }
    }
}

// MARK: Building blocks

private struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
        .padding(.bottom, 18)
    }
}

private struct Row<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 8)
    }
}

private struct ToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Row(title: title, detail: detail) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

// MARK: Panes

private struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var loginEnabled = ViewState<Bool>(SMAppService.mainApp.status == .enabled)

    var body: some View {
        Card(title: "Opening") {
            Row(title: "Open the notch on", detail: "Click mode keeps the notch shut until you click it. Dragging a file always opens it.") {
                Picker("", selection: $settings.openTrigger) {
                    ForEach(OpenTrigger.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }
            Divider()
            Row(title: "Hover delay", detail: "\(Int(settings.hoverDelay * 1000)) ms before the notch opens") {
                Slider(value: $settings.hoverDelay, in: 0...0.6, step: 0.02).frame(width: 180)
            }
            .opacity(settings.openTrigger == .hover ? 1 : 0.4)
            Divider()
            ToggleRow(title: "Swipe between tabs", detail: "Two-finger swipe left or right on the open notch.",
                      isOn: $settings.swipeBetweenTabs)
            Divider()
            ToggleRow(title: "Haptic feedback", detail: "A soft tick on the trackpad when the notch opens.",
                      isOn: $settings.haptics)
        }
        Card(title: "System") {
            Row(title: "Launch at login", detail: "Works once NotchDeck is in /Applications.") {
                Toggle("", isOn: Binding(get: { loginEnabled.value }, set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {}
                    loginEnabled.value = SMAppService.mainApp.status == .enabled
                }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
    }
}

private struct AppearancePane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Card(title: "Theme") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(Theme.all) { theme in
                    ThemeSwatch(theme: theme, selected: settings.themeID == theme.id) { settings.themeID = theme.id }
                }
            }
            .padding(.vertical, 10)
        }
        Card(title: "Accent colour") {
            Row(title: "Accent", detail: "Used for progress bars, the visualiser, the selected tab and active toggles.") {
                Picker("", selection: $settings.accentSource) {
                    ForEach(AccentSource.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 170)
            }
            if settings.accentSource == .custom {
                Divider()
                Row(title: "Custom colour") {
                    HStack(spacing: 6) {
                        ForEach(["#FF6FA8", "#FF9F43", "#FECA57", "#1DD1A1", "#54A0FF", "#A29BFE"], id: \.self) { hex in
                            Circle().fill(Color(hex: hex) ?? .white).frame(width: 18, height: 18)
                                .onTapGesture { settings.customAccent = Color(hex: hex) ?? .white }
                        }
                        ColorPicker("", selection: $settings.customAccent, supportsOpacity: false).labelsHidden()
                    }
                }
            }
        }
        Card(title: "Shape") {
            Row(title: "Corner roundness", detail: "\(Int(settings.cornerRadius)) pt") {
                Slider(value: $settings.cornerRadius, in: 12...40, step: 1).frame(width: 180)
            }
            Divider()
            ToggleRow(title: "Drop shadow", isOn: $settings.shadow)
        }
        Card(title: "Home") {
            Row(title: "Right-hand widget", detail: "What sits next to Now Playing.") {
                Picker("", selection: $settings.glanceWidget) {
                    ForEach(GlanceWidget.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 150)
            }
        }
    }
}

private struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.background)
                    if let glow = theme.glow {
                        RadialGradient(colors: [glow.opacity(0.35), .clear], center: .bottom, startRadius: 0, endRadius: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    VStack(spacing: 5) {
                        Capsule().fill(Color.black).frame(width: 36, height: 8).overlay(Capsule().stroke(Color.white.opacity(0.08)))
                        Spacer()
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4).fill(theme.accent.opacity(0.85)).frame(width: 18, height: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Capsule().fill(Color.white.opacity(0.8)).frame(width: 34, height: 3)
                                Capsule().fill(theme.accent).frame(width: 26, height: 3)
                            }
                        }
                        .padding(.bottom, 10)
                    }
                }
                .frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2.5 : 1))
                Text(theme.name).font(.system(size: 11.5, weight: selected ? .semibold : .regular))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ModulesPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Card(title: "Tabs in the notch") {
            ForEach(Array(NotchTab.allCases.enumerated()), id: \.element) { index, tab in
                if index > 0 { Divider() }
                Row(title: tab.title, detail: Self.detail(tab)) {
                    Toggle("", isOn: Binding(get: { settings.isEnabled(tab) }, set: { settings.setEnabled(tab, $0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .disabled(tab == .home)
                }
            }
        }
    }

    static func detail(_ tab: NotchTab) -> String {
        switch tab {
        case .home: "Now playing, the time, weather and your next event. Always on."
        case .tray: "A shelf for files: drag in, drag out, AirDrop."
        case .calendar: "Today's and tomorrow's events."
        case .clipboard: "Your recent copies, one click to copy again."
        case .mirror: "The front camera, for a quick check before calls."
        case .controls: "Brightness, volume, timer, system stats and quick toggles."
        }
    }
}

private struct MediaPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Card(title: "Now playing") {
            Row(title: "Visualiser") {
                Picker("", selection: $settings.visualizer) {
                    ForEach(VisualizerStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
            }
            Divider()
            ToggleRow(title: "Show live activity", detail: "Album art and the visualiser around the closed notch while music plays.",
                      isOn: $settings.showLiveActivity)
        }
        Card(title: "Volume and brightness") {
            ToggleRow(title: "Replace the macOS HUD",
                      detail: "Volume and brightness keys show only the notch HUD. Needs Accessibility access.",
                      isOn: $settings.replaceSystemHUD)
            if settings.replaceSystemHUD, !MediaKeyInterceptor.isTrusted {
                Button("Open Accessibility settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .padding(.bottom, 8)
            }
            Divider()
            Row(title: "HUD style") {
                Picker("", selection: $settings.hudStyle) {
                    ForEach(HUDStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
            }
            Divider()
            Row(title: "Key step size", detail: "How far one press moves the level. Shift-Option is four times finer.") {
                Picker("", selection: $settings.volumeSteps) {
                    ForEach(VolumeSteps.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 120)
            }
        }
    }
}

private struct ActivitiesPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Card(title: "Announce in the notch") {
            ToggleRow(title: "Charging and battery", detail: "Plugging in, unplugging, and low battery at 20%, 10% and 5%.",
                      isOn: $settings.chargingActivity)
            Divider()
            ToggleRow(title: "Bluetooth devices", detail: "AirPods, keyboards, mice and controllers connecting or leaving. macOS asks for Bluetooth access.",
                      isOn: $settings.bluetoothActivity)
            Divider()
            ToggleRow(title: "Upcoming events", detail: "Five minutes before a calendar event starts.",
                      isOn: $settings.calendarActivity)
        }
    }
}

private struct TrayPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Card(title: "File tray") {
            ToggleRow(title: "Copy dropped files into the tray",
                      detail: "Keeps a copy even if the original moves or is deleted. Off: the tray only remembers where files are.",
                      isOn: $settings.copyDroppedFiles)
        }
        Card(title: "Clipboard history") {
            ToggleRow(title: "Keep clipboard history",
                      detail: "In memory only, cleared when NotchDeck quits. Items marked concealed by password managers are skipped.",
                      isOn: $settings.clipboardEnabled)
            Divider()
            Row(title: "Items to keep") {
                Stepper("\(settings.clipboardLimit)", value: $settings.clipboardLimit, in: 5...100, step: 5)
                    .frame(width: 110)
            }
        }
    }
}

private struct WeatherPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Card(title: "Location") {
            Row(title: "City", detail: "Weather comes from Open-Meteo. Only the city name leaves your Mac.") {
                TextField("e.g. Hyderabad", text: $settings.weatherCity)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            Divider()
            Row(title: "Units") {
                Picker("", selection: $settings.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { Text($0.symbol).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 110)
            }
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("NotchDeck").font(.system(size: 17, weight: .bold))
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .foregroundStyle(.secondary)
                Text("A mission control for the MacBook notch. Inspired by Alcove, NotchNook, boring.notch, MewNotch and Atoll.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
        }
        Card(title: "Permissions") {
            ForEach([("Accessibility", "Privacy_Accessibility", "Replacing the volume and brightness HUD"),
                     ("Automation", "Privacy_Automation", "Spotify, Music and Dark Mode"),
                     ("Calendars", "Privacy_Calendars", "The Calendar tab and event reminders"),
                     ("Camera", "Privacy_Camera", "The Mirror tab")], id: \.0) { name, anchor, use in
                Row(title: name, detail: use) {
                    Button("Open") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
                    }
                }
                if name != "Camera" { Divider() }
            }
        }
    }
}
