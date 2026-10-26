import AppKit
import ServiceManagement
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, customise, appearance, displays, modules, media, activities, tasks, clock, desk, tray, weather, cat, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .customise: "Customise"
        case .tasks: "Tasks"
        case .appearance: "Appearance"
        case .displays: "Displays"
        case .modules: "Modules"
        case .media: "Media & HUD"
        case .activities: "Live Activities"
        case .clock: "Clock"
        case .desk: "Desk"
        case .tray: "Tray & Clipboard"
        case .weather: "Weather"
        case .cat: "Your Dog"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .customise: "slider.horizontal.below.square.and.square.filled"
        case .tasks: "checklist.checked"
        case .appearance: "paintpalette.fill"
        case .displays: "display.2"
        case .modules: "square.grid.2x2.fill"
        case .media: "speaker.wave.2.fill"
        case .activities: "bell.badge.fill"
        case .clock: "alarm.fill"
        case .desk: "square.and.pencil"
        case .tray: "tray.full.fill"
        case .weather: "cloud.sun.fill"
        case .cat: "dog.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .customise: .purple
        case .tasks: .red
        case .appearance: .pink
        case .displays: .teal
        case .modules: .indigo
        case .media: .orange
        case .activities: .red
        case .clock: .orange
        case .desk: .yellow
        case .tray: .blue
        case .weather: .cyan
        case .cat: .orange
        case .about: .secondary
        }
    }
}

final class SettingsWindowController {
    private var window: NSWindow?
    var services: NotchServices?

    func show() {
        if window == nil {
            let hosting = NSHostingView(rootView: SettingsView(settings: .shared, services: services))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
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
    var services: NotchServices?
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
        .frame(minWidth: 800, minHeight: 600)
    }

    @ViewBuilder
    private var content: some View {
        switch pane.value {
        case .general: GeneralPane(settings: settings)
        case .customise: CustomisePane(settings: settings, services: services)
        case .tasks: TasksPane(settings: settings)
        case .appearance: AppearancePane(settings: settings, services: services)
        case .displays: DisplaysPane(settings: settings)
        case .modules: ModulesPane(settings: settings)
        case .media: MediaPane(settings: settings)
        case .activities: ActivitiesPane(settings: settings, focus: services?.focus)
        case .clock: ClockPane(settings: settings)
        case .desk: DeskPane(settings: settings)
        case .tray: TrayPane(settings: settings)
        case .weather: WeatherPane(settings: settings)
        case .cat: CatPane(settings: settings, brain: services?.cat)
        case .about: AboutPane(settings: settings, updates: services?.updates ?? UpdateChecker())
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
            Row(title: "Hover sensitivity", detail: settings.hoverSensitivity.detail) {
                Picker("", selection: $settings.hoverSensitivity) {
                    ForEach(HoverSensitivity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 250)
            }
            .opacity(settings.openTrigger == .hover ? 1 : 0.4)
            Divider()
            Row(title: "Hover delay", detail: "\(Int(settings.hoverDelay * 1000)) ms of resting before the notch opens") {
                Slider(value: $settings.hoverDelay, in: 0.08...0.8, step: 0.02).frame(width: 180)
            }
            .opacity(settings.openTrigger == .hover ? 1 : 0.4)
            Divider()
            Row(title: "Keyboard shortcut", detail: "Opens and closes the notch from anywhere. While open: ← → switch tabs, ⌘1–9 jump, Esc closes.") {
                Picker("", selection: $settings.hotKey) {
                    ForEach(HotKeyChoice.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 130)
            }
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
    var services: NotchServices?

    var body: some View {
        if let services {
            Card(title: "Live preview") {
                NotchPreview(settings: settings, services: services)
                    .frame(height: 190)
                    .padding(.vertical, 8)
            }
        }
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
        Card(title: "Glass and motion") {
            ToggleRow(title: "Glass", detail: "The open notch is frosted glass tinted by the theme. The edge under the notch stays black.",
                      isOn: $settings.glass)
            Divider()
            Row(title: "Clarity", detail: "How much of the desktop shows through.") {
                Slider(value: $settings.glassClarity, in: 0...1).frame(width: 180)
            }
            .opacity(settings.glass ? 1 : 0.4)
            .disabled(!settings.glass)
            Divider()
            ToggleRow(title: "Bouncy animation", detail: "Opening overshoots a touch and settles back, like a popover. Off: a smooth glide.",
                      isOn: $settings.bouncyAnimation)
        }
        BackgroundCard(settings: settings)
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

extension AboutPane {
    var updateText: String {
        switch updates.state {
        case .idle: return "Version \(UpdateChecker.currentVersion)"
        case .checking: return "Checking…"
        case .upToDate: return "You're up to date (\(UpdateChecker.currentVersion))"
        case .available(let version, _): return "Version \(version) is available"
        case .failed(let message): return message
        }
    }
}

/// A scaled-down, live copy of the open notch for the Appearance pane.
private struct NotchPreview: View {
    @ObservedObject var settings: AppSettings
    let services: NotchServices
    @StateObject private var model = PreviewModelBox()

    var body: some View {
        GeometryReader { geo in
            let size = NotchController.windowSize
            let scale = min(geo.size.width / size.width, geo.size.height / (NotchModel.expandedContentSize.height + NotchModel.dockHeight + 60))
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.35, green: 0.45, blue: 0.75), Color(red: 0.75, green: 0.5, blue: 0.7)],
                               startPoint: .top, endPoint: .bottom)
                NotchRootView(model: model.model(settings: settings), services: services, settings: settings,
                              player: services.player)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private final class PreviewModelBox: ObservableObject {
    private var stored: NotchModel?

    func model(settings: AppSettings) -> NotchModel {
        if let stored { return stored }
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                     notchSize: CGSize(width: 179, height: 32), hasNotch: true)
        let model = NotchModel(geometry: geometry, settings: settings)
        model.setExpanded(true)
        stored = model
        return model
    }
}

private struct TasksPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Card(title: "Deadlines") {
            ToggleRow(title: "Count overtime in the closed notch",
                      detail: "Once the task you're on is past its deadline: a red ring and +1:18:34, ticking.",
                      isOn: $settings.tasksInNotch)
            Divider()
            ToggleRow(title: "Ask \u{201C}Still on it?\u{201D}",
                      detail: "A card with Done, Not done and +10 min drops from the notch when a task runs over.",
                      isOn: $settings.taskNudges)
            Divider()
            Row(title: "Ask again every") {
                Stepper("\(settings.taskNudgeMinutes) min", value: $settings.taskNudgeMinutes, in: 5...120, step: 5)
                    .frame(width: 120)
            }
            .disabled(!settings.taskNudges)
            .opacity(settings.taskNudges ? 1 : 0.4)
        }
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Done finishes it. Not done steps away from it: it stays on the list and the next task becomes current. +10 min pushes the deadline ten minutes from now. × asks again later.")
                Text("Focused time counts while a task is current (or a Pomodoro work phase runs) and you're at the Mac. The flame is the number of days in a row you finished something.")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.vertical, 10)
        }
    }
}

/// Everything about the notch itself, from the closed shape to the open panel.
private struct CustomisePane: View {
    @ObservedObject var settings: AppSettings
    var services: NotchServices?

    var body: some View {
        if let services {
            Card(title: "Live preview") {
                NotchPreview(settings: settings, services: services)
                    .frame(height: 210)
                    .padding(.vertical, 8)
            }
        }
        Card(title: "Tabs: order and which show") {
            let enabled = settings.visibleTabs
            let disabled = NotchTab.allCases.filter { !enabled.contains($0) }
            ForEach(Array((enabled + disabled).enumerated()), id: \.element) { index, tab in
                if index > 0 { Divider() }
                let on = enabled.contains(tab)
                HStack(spacing: 10) {
                    Image(systemName: tab.symbol).frame(width: 20).foregroundStyle(on ? Color.accentColor : .secondary)
                    Text(tab.title).font(.system(size: 13)).foregroundStyle(on ? .primary : .secondary)
                    Spacer()
                    if on {
                        Button { settings.moveTab(tab, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless).disabled(enabled.first == tab)
                        Button { settings.moveTab(tab, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless).disabled(enabled.last == tab)
                    }
                    Toggle("", isOn: Binding(get: { on }, set: { settings.setEnabled(tab, $0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .disabled(tab == .home)
                }
                .padding(.vertical, 5)
            }
            Divider()
            Row(title: "Opens on", detail: "The tab the notch shows when it opens.") {
                Picker("", selection: $settings.openingTab) {
                    Text("Where I left it").tag("last")
                    Divider()
                    ForEach(enabled) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden().frame(width: 160)
            }
        }
        Card(title: "Size and shape") {
            Row(title: "Width", detail: "\(Int(settings.panelWidth)) pt") {
                Slider(value: $settings.panelWidth, in: 680...900, step: 10).frame(width: 200)
            }
            Divider()
            Row(title: "Extra height", detail: settings.panelExtraHeight == 0 ? "None" : "+\(Int(settings.panelExtraHeight)) pt") {
                Slider(value: $settings.panelExtraHeight, in: 0...60, step: 5).frame(width: 200)
            }
            Divider()
            Row(title: "Corner roundness", detail: "\(Int(settings.cornerRadius)) pt") {
                Slider(value: $settings.cornerRadius, in: 12...40, step: 1).frame(width: 200)
            }
            Divider()
            ToggleRow(title: "Quick-launch row", detail: "Apps and folders along the bottom.", isOn: $settings.showQuickLaunch)
        }
        Card(title: "Header") {
            ToggleRow(title: "Battery", isOn: $settings.headerBattery)
            Divider()
            ToggleRow(title: "Clock", isOn: $settings.headerClock)
        }
        Card(title: "Text") {
            Row(title: "Font") {
                Picker("", selection: $settings.fontStyle) {
                    ForEach(FontStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            }
        }
        Card(title: "Closed notch and motion") {
            ToggleRow(title: "Swell on hover", detail: "The closed notch grows a touch under the pointer before it opens.",
                      isOn: $settings.hoverSwell)
            Divider()
            Row(title: "Opens on", detail: "Hover opens after the delay; click waits for a click.") {
                Picker("", selection: $settings.openTrigger) {
                    ForEach(OpenTrigger.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }
            Divider()
            Row(title: "Hover sensitivity", detail: settings.hoverSensitivity.detail) {
                Picker("", selection: $settings.hoverSensitivity) {
                    ForEach(HoverSensitivity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 250)
            }
            Divider()
            Row(title: "Hover delay", detail: "\(Int(settings.hoverDelay * 1000)) ms of resting") {
                Slider(value: $settings.hoverDelay, in: 0.08...0.8, step: 0.02).frame(width: 200)
            }
            Divider()
            ToggleRow(title: "Bouncy animation", detail: "Overshoots and settles like a popover. Off: a smooth glide.",
                      isOn: $settings.bouncyAnimation)
            Divider()
            Row(title: "Animation speed", detail: settings.animationSpeed < 0.95 ? "Snappier" : settings.animationSpeed > 1.05 ? "Slower" : "Standard") {
                Slider(value: Binding(get: { 2.5 - settings.animationSpeed }, set: { settings.animationSpeed = 2.5 - $0 }),
                       in: 0.5...2, step: 0.05).frame(width: 200)
            }
        }
        HStack {
            Text("Theme, colours, glass and background are in Appearance; HUD style in Media & HUD.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button("Reset Customisation") { settings.resetCustomisation() }
        }
    }
}

private struct BackgroundCard: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Card(title: "Background") {
            Row(title: "Background", detail: "A theme, one of your photos, or a slideshow of several.") {
                Picker("", selection: $settings.backgroundMode) {
                    ForEach(BackgroundMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
            }
            if settings.backgroundMode != .theme {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(settings.backgroundPhotos, id: \.self) { path in
                            ZStack(alignment: .topTrailing) {
                                if let image = ImageLibrary.image(path, maxPixel: 240) {
                                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                                        .frame(width: 96, height: 60).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                Button {
                                    settings.backgroundPhotos.removeAll { $0 == path }
                                    ImageLibrary.prune(keeping: settings.referencedImages)
                                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6)) }
                                .buttonStyle(.plain).padding(3)
                            }
                        }
                        Button {
                            FilePicker.images(multiple: settings.backgroundMode == .slideshow) { urls in
                                let added = ImageLibrary.importImages(urls)
                                if settings.backgroundMode == .photo {
                                    settings.backgroundPhotos = added + settings.backgroundPhotos.filter { !added.contains($0) }
                                } else {
                                    settings.backgroundPhotos += added
                                }
                                ImageLibrary.prune(keeping: settings.referencedImages)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                                Text(settings.backgroundMode == .photo ? "Choose" : "Add").font(.system(size: 11))
                            }
                            .frame(width: 96, height: 60)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4])))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 10)
                }
                if settings.backgroundMode == .photo, settings.backgroundPhotos.count > 1 {
                    Text("Photo mode shows the first one; switch to Slideshow to cycle through them all.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 6)
                }
                if settings.backgroundMode == .slideshow {
                    Divider()
                    Row(title: "Change every", detail: "\(Int(settings.slideshowInterval)) seconds") {
                        Slider(value: $settings.slideshowInterval, in: 4...120, step: 1).frame(width: 180)
                    }
                }
                Divider()
                Row(title: "Dim", detail: "Keeps text readable over bright photos.") {
                    Slider(value: $settings.backgroundDim, in: 0...0.85).frame(width: 180)
                }
                Divider()
                Row(title: "Blur") {
                    Slider(value: $settings.backgroundBlur, in: 0...30).frame(width: 180)
                }
                Divider()
                ToggleRow(title: "Keep text readable", detail: "A light shade over the photo and a soft shadow under text.",
                          isOn: $settings.photoReadability)
            }
        }
    }
}

private struct CatPane: View {
    @ObservedObject var settings: AppSettings
    let brain: CatBrain?

    private func hour(_ h: Int) -> String {
        var parts = DateComponents()
        parts.hour = h
        return (Calendar.current.date(from: parts) ?? Date()).formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        Card(title: "Your dog") {
            ToggleRow(title: "Dog on the desktop", detail: "Wanders, naps and asks for food. Click it to pet it.",
                      isOn: $settings.catEnabled)
            Divider()
            Row(title: "Name") {
                TextField("Name", text: $settings.catName).textFieldStyle(.roundedBorder).frame(width: 160)
            }
            Divider()
            Row(title: "Coat") {
                Picker("", selection: $settings.catColor) {
                    ForEach(CatColor.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            }
            Divider()
            Row(title: "Where it lives", detail: settings.catPlacement == .notch
                ? "Curled up in the menu bar beside the notch, and it stays there."
                : "Along the top of the Dock; it roams the screen when it plays.") {
                Picker("", selection: $settings.catPlacement) {
                    ForEach(CatPlacement.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            Divider()
            Row(title: "Playful mood", detail: "How often a happy dog chases your pointer for a while.") {
                Picker("", selection: $settings.catPlayfulness) {
                    ForEach(Playfulness.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            }
            Divider()
            Row(title: "Feed from", detail: settings.catFeeding == .hover
                ? "Rest the pointer on the dog for a moment and a Feed card appears."
                : "Feed it from its tile in the notch's Widgets tab; nothing pops up on the desktop.") {
                Picker("", selection: $settings.catFeeding) {
                    ForEach(PetFeeding.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            Divider()
            Row(title: "Bedtime", detail: "It sleeps right through from \(hour(settings.catBedtime)) to \(hour(settings.catWakeTime)), and wakes with a stretch.") {
                HStack(spacing: 6) {
                    Picker("", selection: $settings.catBedtime) {
                        ForEach(18..<24, id: \.self) { Text(hour($0)).tag($0) }
                        ForEach(0..<3, id: \.self) { Text(hour($0)).tag($0) }
                    }
                    .labelsHidden().frame(width: 90)
                    Text("to").foregroundStyle(.secondary)
                    Picker("", selection: $settings.catWakeTime) {
                        ForEach(4..<12, id: \.self) { Text(hour($0)).tag($0) }
                    }
                    .labelsHidden().frame(width: 90)
                }
            }
            Divider()
            Row(title: "Size", detail: settings.catPlacement == .notch
                ? "Fitted to the notch" : "\(Int(settings.catSize * 100))%") {
                Slider(value: $settings.catSize, in: 0.7...1.6, step: 0.05).frame(width: 180)
                    .disabled(settings.catPlacement == .notch)
            }
        }
        if let brain {
            Card(title: "How it's doing") {
                HStack(spacing: 18) {
                    TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                        CatFigure(pose: brain.isSick ? .sick : .sit, mood: brain.mood, color: settings.catColor,
                                  time: context.date.timeIntervalSinceReferenceDate * 2, girth: brain.girth)
                    }
                    .frame(width: 110, height: 80)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.75)))
                    CatCard(brain: brain, name: settings.catName)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.75)))
                        .environment(\.colorScheme, .dark)
                }
                .padding(.vertical, 10)
                Text("A full bowl lasts about ten waking hours; time stops while the Mac sleeps. Feed it when it's hungry: food past full makes it fat and, twice in a row, sick. Pet it, or it gets lonely. A dog kept fat, hungry or lonely falls ill and needs the vet.")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 10)
            }
        }
    }
}

private struct DisplaysPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Card(title: "Where the notch appears") {
            Row(title: "Show on") {
                Picker("", selection: $settings.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 190)
            }
            Divider()
            ToggleRow(title: "Island style on displays without a notch",
                      detail: "A floating pill just below the top edge, like the Dynamic Island. Off: a notch attached to the top.",
                      isOn: $settings.islandOnPlainDisplays)
        }
        Card(title: "Lock screen") {
            ToggleRow(title: "Show a widget on the lock screen",
                      detail: "A full-screen record player while your Mac is locked: the album's colours, the lyrics and the time. Type your password as usual to unlock.",
                      isOn: $settings.lockScreenWidget)
        }
    }
}

private struct ClockPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Card(title: "Alarms and timer") {
            Row(title: "Sound", detail: "Plays on a loop until you snooze or stop (at most five minutes).") {
                HStack(spacing: 6) {
                    Picker("", selection: $settings.alarmSound) {
                        ForEach(AppSettings.systemSounds, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                    Button {
                        NSSound(named: NSSound.Name(settings.alarmSound))?.play()
                    } label: { Image(systemName: "play.fill") }
                }
            }
            Divider()
            Row(title: "Snooze for") {
                Stepper("\(settings.snoozeMinutes) min", value: $settings.snoozeMinutes, in: 1...30).frame(width: 120)
            }
        }
        Card(title: "Pomodoro (Clock → Focus)") {
            Row(title: "Work") {
                Stepper("\(settings.pomodoroWork) min", value: $settings.pomodoroWork, in: 5...120, step: 5).frame(width: 120)
            }
            Divider()
            Row(title: "Short break") {
                Stepper("\(settings.pomodoroShortBreak) min", value: $settings.pomodoroShortBreak, in: 1...30).frame(width: 120)
            }
            Divider()
            Row(title: "Long break") {
                Stepper("\(settings.pomodoroLongBreak) min", value: $settings.pomodoroLongBreak, in: 5...60, step: 5).frame(width: 120)
            }
            Divider()
            Row(title: "Rounds before a long break") {
                Stepper("\(settings.pomodoroRounds)", value: $settings.pomodoroRounds, in: 2...8).frame(width: 120)
            }
            Divider()
            ToggleRow(title: "Start the next phase by itself", detail: "Off: each phase waits for you to press Start.",
                      isOn: $settings.pomodoroAutoStart)
            Divider()
            Row(title: "Sound between phases") {
                HStack(spacing: 6) {
                    Picker("", selection: $settings.pomodoroSound) {
                        ForEach(AppSettings.systemSounds, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                    Button { NSSound(named: NSSound.Name(settings.pomodoroSound))?.play() } label: { Image(systemName: "play.fill") }
                }
            }
        }
        Card {
            Text("Alarms ring while NotchDeck is running and your Mac is awake. A sleeping Mac can't ring.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.vertical, 10)
        }
    }
}

private struct DeskPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Card(title: "Colour picker (Desk → Colours)") {
            Row(title: "Shortcut", detail: "Shows the loupe from anywhere. Click to take a colour, Esc to cancel.") {
                Picker("", selection: $settings.colorHotKey) {
                    ForEach([HotKeyChoice.controlOptionC, .controlOptionP, .off]) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 110)
            }
            Divider()
            ToggleRow(title: "Copy the hex code", isOn: $settings.colorCopyOnPick)
            Divider()
            ToggleRow(title: "Save every pick to the palette", detail: "Off: press Save in Desk → Colours for the ones you want.",
                      isOn: $settings.colorAutoSave)
        }
        Card(title: "Script widget") {
            Row(title: "Command", detail: "Runs in zsh from your home folder; output shows in Desk → Script.") {
                TextField("e.g. git -C ~/code/app status -sb", text: $settings.scriptCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 280)
            }
            Divider()
            Row(title: "Refresh every") {
                Stepper("\(settings.scriptInterval) s", value: $settings.scriptInterval, in: 5...600, step: 5).frame(width: 120)
            }
        }
        Card {
            Text("Notes save automatically to ~/Library/Application Support/NotchDeck/notes.txt. To-do uses your default Reminders list.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.vertical, 10)
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
        Card(title: "Quick-launch row") {
            ToggleRow(title: "Show along the bottom of the notch",
                      detail: "Apps and folders one click away. Drop files on an app to open them with it.",
                      isOn: $settings.showQuickLaunch)
            ForEach(settings.quickItems) { item in
                Divider()
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().frame(width: 20, height: 20)
                    Text(item.name).font(.system(size: 13))
                    if !item.exists { Text("missing").font(.system(size: 11)).foregroundStyle(.red) }
                    Spacer()
                    Button { settings.quickItems.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            Divider()
            HStack {
                Button("Add Apps or Folders…") {
                    FilePicker.appsOrFolders { urls in
                        let known = Set(settings.quickItems.map(\.path))
                        settings.quickItems += urls.map(\.path).filter { !known.contains($0) }.map { QuickItem(path: $0) }
                    }
                }
                Spacer()
                Button("Reset") { settings.quickItems = QuickItem.defaults }
            }
            .padding(.vertical, 8)
        }
    }

    static func detail(_ tab: NotchTab) -> String {
        switch tab {
        case .home: "Now playing, the time, weather and your next event. Always on."
        case .tasks: "What you're on, what's next by deadline, overtime in the closed notch and a \u{201C}Still on it?\u{201D} nudge."
        case .widgets: "Tiles you choose: photos, clocks, world time, weather, battery, countdowns, notes and your dog."
        case .tray: "A shelf for files: drag in, drag out, AirDrop."
        case .calendar: "Today's and tomorrow's events."
        case .clock: "Alarms, a timer, a Pomodoro focus timer and a stopwatch, all of which show in the closed notch."
        case .desk: "Notes, your Apple Reminders, the colour picker and palette, Shortcuts and a shell-command widget."
        case .system: "CPU, GPU, memory, disk, network speed, battery health and device batteries."
        case .clipboard: "Your recent copies, one click to copy again."
        case .mirror: "The front camera, for a quick check before calls."
        case .controls: "Brightness (built-in, external, keyboard), volume, sound output, mic mute and quick toggles."
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
            Divider()
            ToggleRow(title: "Synced lyrics", detail: "The current line under the song, from LRCLIB. The song title and artist are sent to lrclib.net.",
                      isOn: $settings.showLyrics)
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
    var focus: FocusWatcher?

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
            Divider()
            ToggleRow(title: "Meeting countdown", detail: "The closed notch counts down the last ten minutes before a meeting.",
                      isOn: $settings.calendarCountdown)
            Divider()
            ToggleRow(title: "Reminders due", detail: "An alert with a chime when an Apple Reminder comes due.",
                      isOn: $settings.reminderActivity)
            Divider()
            ToggleRow(title: "Accessory battery", detail: "AirPods (left, right, case), mice and keyboards show their level when they connect.",
                      isOn: $settings.accessoryBattery)
            Divider()
            ToggleRow(title: "Downloads", detail: "Progress in the notch while a browser downloads to ~/Downloads, and a card when it finishes.",
                      isOn: $settings.downloadActivity)
            Divider()
            ToggleRow(title: "Focus", detail: "Do Not Disturb, Work, Sleep… turning on or off. Needs Full Disk Access to read the Focus state.",
                      isOn: $settings.focusActivity)
            if settings.focusActivity, focus?.needsFullDiskAccess == true {
                Button("Open Full Disk Access settings…") { focus?.openFullDiskAccessSettings() }
                    .padding(.bottom, 8)
            }
            Divider()
            ToggleRow(title: "Privacy dots", detail: "Green: camera in use. Orange: microphone. Purple: screen recording. Red: your mic is muted.",
                      isOn: $settings.privacyIndicators)
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
            Divider()
            ToggleRow(title: "Add finished downloads to the tray", isOn: $settings.downloadsToTray)
        }
        Card(title: "Clipboard history") {
            ToggleRow(title: "Keep clipboard history",
                      detail: "Items marked concealed by password managers are never recorded.",
                      isOn: $settings.clipboardEnabled)
            Divider()
            ToggleRow(title: "Remember across restarts",
                      detail: "Saves text and file items encrypted (AES-GCM, key in your Keychain). Images are never saved.",
                      isOn: $settings.clipboardPersist)
            Divider()
            Row(title: "Items to keep", detail: "Pinned items don't count and are never removed.") {
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
    @ObservedObject var settings: AppSettings
    @ObservedObject var updates: UpdateChecker

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
                     ("Reminders", "Privacy_Reminders", "Desk → To-do and due alerts"),
                     ("Full Disk Access", "Privacy_AllFiles", "Reading which Focus mode is on"),
                     ("Camera", "Privacy_Camera", "The Mirror tab")], id: \.0) { name, anchor, use in
                Row(title: name, detail: use) {
                    Button("Open") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
                    }
                }
                if name != "Camera" { Divider() }
            }
        }
        Card(title: "Updates") {
            Row(title: "GitHub repository", detail: "Where releases are published, e.g. you/notchdeck. NotchDeck checks its latest release.") {
                TextField("owner/repo", text: $settings.updateRepository)
                    .textFieldStyle(.roundedBorder).frame(width: 200)
            }
            Divider()
            Row(title: updateText) {
                switch updates.state {
                case .available(_, let url):
                    Button("Download") { NSWorkspace.shared.open(url) }
                case .checking:
                    ProgressView().controlSize(.small)
                default:
                    Button("Check now") { updates.check(repository: settings.updateRepository) }
                }
            }
        }
    }
}
