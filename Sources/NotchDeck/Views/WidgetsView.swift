import SwiftUI
import UniformTypeIdentifiers

/// Tiles the user picks: photos, clocks, weather, battery, the cat… Add with +, remove or change
/// from each tile's right-click menu or in edit mode.
struct WidgetsView: View {
    @ObservedObject var model: NotchModel
    let services: NotchServices
    @ObservedObject var settings: AppSettings
    @StateObject private var editing = ViewState<Bool>(false)
    @Environment(\.look) private var look

    static let tile: CGFloat = 150

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Rows that wrap and scroll VERTICALLY. A horizontal row could not be scrolled: the panel
            // turns every two-finger horizontal swipe into a tab change, and a mouse wheel only
            // scrolls vertically, so a new widget appended off the right edge was out of reach.
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    WrapLayout(spacing: 10) {
                        ForEach(settings.widgets) { item in
                            WidgetTile(item: item, model: model, services: services, settings: settings,
                                       editing: editing.value) { remove(item) }
                                .id(item.id)
                                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                        if settings.widgets.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No widgets yet").font(.system(size: 14, weight: .semibold))
                                Text("Press + to add photos, clocks, weather, your cat and more.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(look.theme.secondaryText)
                            }
                            .frame(width: 260, height: Self.tile, alignment: .leading)
                        }
                    }
                    // Room for the hover lift and shadow, which a scroll view would otherwise clip.
                    .padding(6)
                }
                .onChange(of: settings.widgets.count) { old, count in
                    guard count > old, let last = settings.widgets.last else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            VStack(spacing: 6) {
                Menu {
                    ForEach(WidgetItem.Kind.allCases) { kind in
                        Button { add(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(look.accent.opacity(0.25)))
                        .foregroundStyle(look.accent)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 30, height: 30)
                .help("Add a widget")
                IconButton(symbol: editing.value ? "checkmark" : "slider.horizontal.3",
                           help: editing.value ? "Done" : "Edit widgets") { editing.value.toggle() }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: settings.widgets)
    }

    private func add(_ kind: WidgetItem.Kind) {
        var item = WidgetItem(kind: kind)
        switch kind {
        case .worldClock: item.text = "America/New_York"
        case .countdown:
            item.text = "Weekend"
            item.date = Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: 7),
                                                  matchingPolicy: .nextTime)
        default: break
        }
        settings.widgets.append(item)
        if kind == .photo { choosePhotos(for: item.id) }
    }

    private func remove(_ item: WidgetItem) {
        settings.widgets.removeAll { $0.id == item.id }
        ImageLibrary.prune(keeping: settings.referencedImages)
    }

    private func choosePhotos(for id: UUID) {
        let settings = settings
        model.pick({ FilePicker.images(multiple: true, completion: $0) }, reopen: .widgets) { urls in
            guard !urls.isEmpty, let index = settings.widgets.firstIndex(where: { $0.id == id }) else { return }
            settings.widgets[index].images = ImageLibrary.importImages(urls)
            ImageLibrary.prune(keeping: settings.referencedImages)
        }
    }
}

private struct WidgetTile: View {
    let item: WidgetItem
    let model: NotchModel
    let services: NotchServices
    @ObservedObject var settings: AppSettings
    let editing: Bool
    let remove: () -> Void
    @StateObject private var hovering = ViewState<Bool>(false)
    @Environment(\.look) private var look

    var body: some View {
        let size = WidgetsView.tile
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !editing)) { context in
            content
                .frame(width: item.kind.isWide ? size * 2 + 10 : size, height: size)
                .background(GlassTile())
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if editing {
                        Button(action: remove) {
                            Image(systemName: "minus")
                                .font(.system(size: 9, weight: .heavy))
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.white.opacity(0.9)))
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                // A gentle wobble while editing, like the Home Screen.
                .rotationEffect(.degrees(editing ? sin(context.date.timeIntervalSinceReferenceDate * 14
                                                       + Double(item.id.hashValue % 7)) * 1.2 : 0))
        }
        .scaleEffect(hovering.value && !editing ? 1.03 : 1)
        .shadow(color: .black.opacity(hovering.value ? 0.35 : 0.15), radius: hovering.value ? 10 : 4, y: 3)
        .onHover { hovering.value = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering.value)
        .contextMenu { menu }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .photo: PhotoWidget(item: item) { choosePhotos() }
        case .analogClock: AnalogClockWidget(zone: .current, label: nil)
        case .worldClock: AnalogClockWidget(zone: TimeZone(identifier: item.text) ?? .current,
                                            label: WorldZones.name(item.text))
        case .weather: WeatherWidget(weather: services.weather)
        case .battery: BatteryWidget(system: services.system)
        case .nextEvent: EventWidget(calendar: services.calendar)
        case .countdown: CountdownWidget(item: item)
        case .stats: StatsWidget(stats: services.stats)
        case .cat: CatWidget(brain: services.cat, settings: settings)
        case .note: NoteWidget(notes: services.notes) { model.tab = .desk }
        }
    }

    @ViewBuilder
    private var menu: some View {
        switch item.kind {
        case .photo:
            Button("Choose Photos…") { choosePhotos() }
        case .worldClock:
            Menu("Time Zone") {
                ForEach(WorldZones.all, id: \.0) { zone in
                    Button(zone.1) { update { $0.text = zone.0 } }
                }
            }
        case .countdown:
            Menu("Count Down To") {
                ForEach(CountdownWidget.presets, id: \.0) { preset in
                    Button(preset.0) { update { $0.text = preset.0; $0.date = preset.1() } }
                }
            }
        default:
            EmptyView()
        }
        Button("Remove Widget", role: .destructive, action: remove)
    }

    private func update(_ change: (inout WidgetItem) -> Void) {
        guard let index = settings.widgets.firstIndex(where: { $0.id == item.id }) else { return }
        change(&settings.widgets[index])
    }

    private func choosePhotos() {
        let settings = settings
        let id = item.id
        model.pick({ FilePicker.images(multiple: true, completion: $0) }, reopen: .widgets) { urls in
            guard !urls.isEmpty, let index = settings.widgets.firstIndex(where: { $0.id == id }) else { return }
            settings.widgets[index].images = ImageLibrary.importImages(urls)
            ImageLibrary.prune(keeping: settings.referencedImages)
        }
    }
}

/// Lays its children out left to right and starts a new row when the next one would not fit.
/// Wide tiles simply take more of a row.
struct WrapLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (index, size) in row.items {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(Int, CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].items.isEmpty { rows.append(Row()) }
            var row = rows[rows.count - 1]
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.items.isEmpty }
    }
}

/// Frosted tile: a light wash with a bright top edge, like glass catching the light.
struct GlassTile: View {
    var corner: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.04)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
    }
}

// MARK: Tiles

private struct PhotoWidget: View {
    let item: WidgetItem
    let choose: () -> Void

    var body: some View {
        if item.images.isEmpty {
            Button(action: choose) {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 26))
                    Text("Choose photos").font(.system(size: 11, weight: .semibold))
                    Text("One stays put; several take turns.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Slideshow(paths: item.images, interval: 8, maxPixel: 700)
        }
    }
}

/// Cross-fades through `paths`, with a slow drift so stills feel alive.
struct Slideshow: View {
    let paths: [String]
    let interval: Double
    var maxPixel: CGFloat = 1400

    var body: some View {
        TimelineView(.periodic(from: .now, by: paths.count > 1 ? interval : 3600)) { context in
            let slot = Int(context.date.timeIntervalSinceReferenceDate / interval)
            let path = paths[slot % paths.count]
            ZStack {
                if let image = ImageLibrary.image(path, maxPixel: maxPixel) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                        .id(path + "\(slot)")
                } else {
                    Color.white.opacity(0.05)
                }
            }
            .animation(.easeInOut(duration: 1.2), value: slot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private struct AnalogClockWidget: View {
    let zone: TimeZone
    let label: String?
    @Environment(\.look) private var look

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            var calendar = Calendar.current
            let _ = calendar.timeZone = zone
            let parts = calendar.dateComponents([.hour, .minute, .second], from: context.date)
            let h = Double(parts.hour ?? 0), m = Double(parts.minute ?? 0), s = Double(parts.second ?? 0)
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.92))
                    ForEach(0..<12, id: \.self) { i in
                        Capsule()
                            .fill(Color.black.opacity(i % 3 == 0 ? 0.8 : 0.35))
                            .frame(width: i % 3 == 0 ? 2.2 : 1.4, height: i % 3 == 0 ? 8 : 5)
                            .offset(y: -44)
                            .rotationEffect(.degrees(Double(i) * 30))
                    }
                    hand(width: 3.5, length: 26, angle: (h.truncatingRemainder(dividingBy: 12) + m / 60) * 30, color: .black)
                    hand(width: 2.5, length: 38, angle: (m + s / 60) * 6, color: .black)
                    hand(width: 1.2, length: 42, angle: s * 6, color: look.accent == .white ? .orange : look.accent)
                    Circle().fill(Color.black).frame(width: 6, height: 6)
                }
                .frame(width: label == nil ? 112 : 100, height: label == nil ? 112 : 100)
                .animation(.spring(response: 0.25, dampingFraction: 0.55), value: s)
                if let label {
                    Text("\(label) · \(context.date.formatted(Date.FormatStyle(timeZone: zone).hour().minute()))")
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                }
            }
        }
    }

    private func hand(width: CGFloat, length: CGFloat, angle: Double, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2 + 4)
            .rotationEffect(.degrees(angle))
    }
}

enum WorldZones {
    static let all: [(String, String)] = [
        ("Asia/Kolkata", "India"), ("America/New_York", "New York"), ("America/Los_Angeles", "San Francisco"),
        ("Europe/London", "London"), ("Europe/Paris", "Paris"), ("Asia/Dubai", "Dubai"),
        ("Asia/Singapore", "Singapore"), ("Asia/Tokyo", "Tokyo"), ("Australia/Sydney", "Sydney"),
    ]

    static func name(_ id: String) -> String {
        all.first { $0.0 == id }?.1 ?? (id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id)
    }
}

private struct WeatherWidget: View {
    @ObservedObject var weather: WeatherService

    var body: some View {
        if let w = weather.weather {
            VStack(alignment: .leading, spacing: 2) {
                Text(w.city).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text("\(Int(w.temperature.rounded()))°")
                    .font(.system(size: 40, weight: .medium, design: .rounded))
                Spacer(minLength: 0)
                Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 18))
                Text(w.summary).font(.system(size: 11, weight: .semibold))
                Text("H \(Int(w.high.rounded()))°  L \(Int(w.low.rounded()))°")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: w.isDay ? [Color(red: 0.25, green: 0.5, blue: 0.9).opacity(0.55), .clear]
                                                       : [Color(red: 0.1, green: 0.12, blue: 0.35).opacity(0.7), .clear],
                                       startPoint: .top, endPoint: .bottom))
        } else {
            placeholder("cloud.sun.fill", weather.problem ?? "Loading weather…")
        }
    }
}

private struct BatteryWidget: View {
    @ObservedObject var system: SystemStatus

    var body: some View {
        let level = system.batteryLevel ?? 0
        let tint: Color = level <= 20 && !system.onPower ? .red : .green
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(tint.opacity(0.22), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: Double(level) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: system.isCharging ? "bolt.fill" : "laptopcomputer")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 84, height: 84)
            Text(system.batteryLevel.map { "\($0)%" } ?? "—")
                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
            Text(system.isCharging ? "Charging" : (system.onPower ? "On power" : "On battery"))
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
        }
    }
}

private struct EventWidget: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Text(context.date, format: .dateTime.weekday(.wide))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)
                    Text(context.date, format: .dateTime.day())
                        .font(.system(size: 32, weight: .regular, design: .rounded))
                }
            }
            Spacer(minLength: 0)
            if let event = calendar.nextEvent {
                HStack(alignment: .top, spacing: 6) {
                    Capsule().fill(event.color).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(2)
                        Text(EventTime.short(event)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No more events").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CountdownWidget: View {
    let item: WidgetItem
    @Environment(\.look) private var look

    static let presets: [(String, () -> Date?)] = [
        ("Weekend", { Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: 7), matchingPolicy: .nextTime) }),
        ("New Year", { Calendar.current.nextDate(after: Date(), matching: DateComponents(month: 1, day: 1), matchingPolicy: .nextTime) }),
        ("End of month", {
            let calendar = Calendar.current
            return calendar.date(byAdding: DateComponents(month: 1, day: -1),
                                 to: calendar.dateInterval(of: .month, for: Date())?.start ?? Date())
        }),
        ("Diwali 2026", { DateComponents(calendar: .current, year: 2026, month: 11, day: 8).date }),
        ("Christmas", { Calendar.current.nextDate(after: Date(), matching: DateComponents(month: 12, day: 25), matchingPolicy: .nextTime) }),
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let seconds = max((item.date ?? context.date).timeIntervalSince(context.date), 0)
            let days = Int(seconds / 86400)
            let hours = Int(seconds.truncatingRemainder(dividingBy: 86400) / 3600)
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "hourglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(look.accent)
                Spacer(minLength: 0)
                Text(days > 0 ? "\(days)" : "\(hours)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                Text(days > 0 ? (days == 1 ? "day to go" : "days to go") : (hours == 1 ? "hour to go" : "hours to go"))
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                Text(item.text).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct StatsWidget: View {
    @ObservedObject var stats: SystemStats
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            row("CPU", stats.cpu)
            row("GPU", stats.gpu)
            row("RAM", stats.memory)
            row("Disk", stats.disk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func row(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(Int((value * 100).rounded()))%").font(.system(size: 10, weight: .semibold).monospacedDigit())
            }
            LevelBar(level: value, color: value > 0.85 ? .red : look.accent).frame(height: 4)
        }
    }
}

private struct CatWidget: View {
    @ObservedObject var brain: CatBrain
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .top) {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    CatFigure(pose: brain.pose == .walk ? .sit : brain.pose, mood: brain.mood, color: settings.catColor,
                              time: context.date.timeIntervalSinceReferenceDate * 2)
                }
                .frame(width: 100, height: 72)
                .onTapGesture { brain.pet() }
                CatHearts(since: brain.heartsAt)
            }
            CatCard(brain: brain, name: settings.catName).scaleEffect(0.95)
        }
        .padding(.top, 6)
    }
}

private struct NoteWidget: View {
    @ObservedObject var notes: NotesStore
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Note", systemImage: "note.text")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.3))
                Text(notes.text.isEmpty ? "Nothing jotted yet. Tap to write in Desk." : notes.text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(notes.text.isEmpty ? 0.5 : 0.9))
                    .lineLimit(7)
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private func placeholder(_ symbol: String, _ text: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: symbol).symbolRenderingMode(.multicolor).font(.system(size: 24))
        Text(text).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
    }
    .padding(10)
}

// MARK: Quick launch

/// A little dock along the bottom of the open notch: apps and folders you pick. Click to open,
/// drop files on an app to open them with it.
struct QuickLaunchRow: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 4) {
            ForEach(settings.quickItems.filter(\.exists)) { item in
                QuickIcon(item: item) {
                    settings.quickItems.removeAll { $0.id == item.id }
                }
            }
            Button {
                let settings = settings
                model.pick({ FilePicker.appsOrFolders(completion: $0) }, reopen: model.tab) { urls in
                    let known = Set(settings.quickItems.map(\.path))
                    settings.quickItems += urls.map(\.path).filter { !known.contains($0) }.map { QuickItem(path: $0) }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .foregroundStyle(.white.opacity(0.6))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Add apps or folders")
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Capsule().fill(Color.white.opacity(0.07))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.03)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 0.8)))
    }
}

private struct QuickIcon: View {
    let item: QuickItem
    let remove: () -> Void
    @StateObject private var hovering = ViewState<Bool>(false)
    @StateObject private var targeted = ViewState<Bool>(false)

    var body: some View {
        let isApp = item.path.hasSuffix(".app")
        Button {
            NSWorkspace.shared.open(item.url)
        } label: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 26, height: 26)
                .scaleEffect(hovering.value || targeted.value ? 1.35 : 1, anchor: .bottom)
                .offset(y: hovering.value || targeted.value ? -3 : 0)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.name)
        .onHover { hovering.value = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: hovering.value || targeted.value)
        .onDrop(of: [UTType.fileURL], isTargeted: isApp ? $targeted.value : .constant(false)) { providers in
            guard isApp else { return false }
            FileTray.loadURLs(providers) { urls in
                NSWorkspace.shared.open(urls, withApplicationAt: item.url, configuration: NSWorkspace.OpenConfiguration())
            }
            return true
        }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Remove from Row", role: .destructive, action: remove)
        }
    }
}
