import AVFoundation
import SwiftUI

// MARK: Calendar

struct CalendarTabView: View {
    @ObservedObject var calendar: CalendarService
    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Text(context.date, format: .dateTime.weekday(.wide))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(look.accent)
                        .textCase(.uppercase)
                    Text(context.date, format: .dateTime.day())
                        .font(.system(size: 54, weight: .semibold, design: .rounded))
                    Text(context.date, format: .dateTime.month(.wide).year())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(look.theme.secondaryText)
                    if calendar.access == .granted, !calendar.week.isEmpty {
                        WeekStrip(days: calendar.week).padding(.top, 10)
                    }
                    Spacer(minLength: 0)
                    Button { calendar.openCalendarApp() } label: {
                        Label("Open Calendar", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }
            .frame(width: 176, alignment: .leading)

            Group {
                switch calendar.access {
                case .granted:
                    if calendar.events.isEmpty {
                        placeholder(symbol: "checkmark.circle", title: "Nothing left today or tomorrow",
                                    detail: "Enjoy the free time.")
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 6) {
                                ForEach(calendar.events) { event in
                                    EventRow(event: event, onOpen: { calendar.open(event) },
                                             onJoin: { calendar.join(event) })
                                }
                            }
                        }
                    }
                case .unknown:
                    placeholder(symbol: "calendar.badge.plus", title: "See your day in the notch",
                                detail: "Today's and tomorrow's events from every calendar in Calendar.app.") {
                        Button("Connect Calendar") { calendar.requestAccess() }
                            .buttonStyle(PillButtonStyle())
                    }
                case .denied:
                    placeholder(symbol: "calendar.badge.exclamationmark", title: "Calendar access is off",
                                detail: "Turn on NotchDeck in Privacy & Security → Calendars.") {
                        Button("Open Settings") { calendar.openPrivacySettings() }
                            .buttonStyle(PillButtonStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func placeholder<Extra: View>(symbol: String, title: String, detail: String,
                                          @ViewBuilder extra: () -> Extra = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(look.accent)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(look.theme.secondaryText)
            extra().padding(.top, 4)
        }
        .padding(.top, 6)
    }
}

/// The next seven days, with a dot per event (up to three).
private struct WeekStrip: View {
    let days: [CalendarDay]
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 2) {
            ForEach(days) { day in
                let today = Calendar.current.isDateInToday(day.date)
                VStack(spacing: 2) {
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(day.date, format: .dateTime.day())
                        .font(.system(size: 11, weight: today ? .bold : .medium).monospacedDigit())
                        .frame(width: 21, height: 21)
                        .background(Circle().fill(today ? look.accent.opacity(0.35) : .clear))
                    HStack(spacing: 1.5) {
                        ForEach(Array(day.colors.enumerated()), id: \.offset) { _, color in
                            Circle().fill(color).frame(width: 3.5, height: 3.5)
                        }
                    }
                    .frame(height: 4)
                }
                .frame(maxWidth: .infinity)
                .help(day.count == 0 ? "Free" : "\(day.count) event\(day.count == 1 ? "" : "s")")
            }
        }
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    var onOpen: () -> Void = {}
    var onJoin: () -> Void = {}
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 10) {
            // The colour bar, title and time open the event; the Join button beside them is a
            // separate control, so joining never opens Calendar too.
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(EventTime.describe(event) + (event.location.map { "  ·  \($0)" } ?? ""))
                            .font(.system(size: 10.5))
                            .foregroundStyle(look.theme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in Calendar")
            if event.joinURL != nil {
                Button(action: onJoin) {
                    Label("Join", systemImage: "video.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().fill(event.isJoinable ? Color.green.opacity(0.85) : Color.white.opacity(0.12)))
                        .foregroundStyle(.white)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Join the call")
            }
            if event.isNow {
                Text("NOW")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(event.color.opacity(0.3)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look.theme.surface))
    }
}

// MARK: Clipboard

struct ClipboardView: View {
    @ObservedObject var history: ClipboardHistory
    @ObservedObject var settings: AppSettings
    var model: NotchModel?
    @Environment(\.look) private var look
    @StateObject private var query = ViewState("")
    @StateObject private var kind = ViewState<Kind>(.all)

    /// What the history can be narrowed to.
    enum Kind: String, CaseIterable {
        case all, text, links, images, files
        var symbol: String {
            switch self {
            case .all: "square.stack"
            case .text: "text.alignleft"
            case .links: "link"
            case .images: "photo"
            case .files: "doc"
            }
        }
        var title: String { rawValue.capitalized }

        func matches(_ content: ClipboardHistory.Item.Content) -> Bool {
            switch (self, content) {
            case (.all, _), (.images, .image), (.files, .file): return true
            case (.text, .text(let t)): return !Self.isLink(t)
            case (.links, .text(let t)): return Self.isLink(t)
            default: return false
            }
        }

        static func isLink(_ text: String) -> Bool {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.contains(" ") && (t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("www."))
        }
    }

    private var shown: [ClipboardHistory.Item] {
        let q = query.value.trimmingCharacters(in: .whitespaces).lowercased()
        return history.sortedItems.filter { item in
            guard kind.value.matches(item.content) else { return false }
            guard !q.isEmpty else { return true }
            switch item.content {
            case .text(let t): return t.lowercased().contains(q)
            case .file(let url): return url.lastPathComponent.lowercased().contains(q)
            case .image: return false
            }
        }
    }

    var body: some View {
        if !settings.clipboardEnabled {
            empty(symbol: "doc.on.clipboard", title: "Clipboard history is off",
                  detail: "Turn it on in Settings → Tray & Clipboard.")
        } else if history.items.isEmpty {
            empty(symbol: "doc.on.clipboard", title: "Copy something",
                  detail: "Your last \(settings.clipboardLimit) copies land here. Click one to copy it again.")
        } else {
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if shown.isEmpty {
                            VStack(spacing: 4) {
                                Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(look.accent)
                                Text("Nothing matches").font(.system(size: 12, weight: .semibold))
                            }
                            .frame(width: 300, height: 128)
                        }
                        ForEach(shown) { item in
                            ClipCard(item: item, copied: history.lastCopiedID == item.id,
                                     onPin: { history.togglePin(item) }) { history.copy(item) }
                                .contextMenu {
                                    Button("Copy") { history.copy(item) }
                                    Button(item.pinned ? "Unpin" : "Pin") { history.togglePin(item) }
                                    Button("Remove") { history.remove(item) }
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
                VStack(spacing: 7) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                        TextField("Search", text: $query.value)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .simultaneousGesture(TapGesture().onEnded { model?.requestKeyboard() })
                        if !query.value.isEmpty {
                            Button { query.value = "" } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    HStack(spacing: 2) {
                        ForEach(Kind.allCases, id: \.self) { k in
                            Button { kind.value = k } label: {
                                Image(systemName: k.symbol)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(kind.value == k ? look.accent.opacity(0.4) : .clear))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(k.title)
                        }
                    }
                    Text(shown.count == history.items.count ? "\(history.items.count) items" : "\(shown.count) of \(history.items.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(look.theme.secondaryText)
                    Button { history.clear() } label: { Label("Clear", systemImage: "trash") }
                        .buttonStyle(PillButtonStyle())
                        .help("Clears everything except pinned items")
                    if settings.clipboardPersist {
                        Label("Saved", systemImage: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(look.theme.secondaryText)
                            .help("History is kept, encrypted, across restarts")
                    }
                }
                .frame(width: 118)
            }
        }
    }

    private func empty(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(look.accent)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(look.theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClipCard: View {
    let item: ClipboardHistory.Item
    let copied: Bool
    let onPin: () -> Void
    let action: () -> Void
    @StateObject private var hovering = ViewState<Bool>(false)
    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark.circle.fill" : kindSymbol)
                        .foregroundStyle(copied ? .green : look.accent)
                    Text(copied ? "Copied" : item.date.formatted(.relative(presentation: .numeric)))
                        .lineLimit(1)
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            }
            .padding(10)
            .frame(width: 150, height: 128)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(hovering.value ? Color.white.opacity(0.14) : look.theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(copied ? Color.green.opacity(0.7) : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if item.pinned || hovering.value {
                Button(action: onPin) {
                    Image(systemName: item.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(item.pinned ? look.accent : .white.opacity(0.6))
                        .rotationEffect(.degrees(45))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .padding(5)
                .help(item.pinned ? "Unpin" : "Pin to keep it at the front")
            }
        }
        .onHover { hovering.value = $0 }
        .animation(.easeOut(duration: 0.15), value: copied)
    }

    private var kindSymbol: String {
        switch item.content {
        case .text: "text.alignleft"
        case .image: "photo"
        case .file: "doc"
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.content {
        case .text(let text):
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 11))
                .lineLimit(5)
                .multilineTextAlignment(.leading)
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .file(let url):
            VStack(alignment: .leading, spacing: 4) {
                Image(nsImage: IconCache.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 40, height: 40)
                Text(url.lastPathComponent)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(2)
            }
        }
    }
}

// MARK: Mirror

struct MirrorView: View {
    @ObservedObject var camera: CameraMirror
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(look.theme.surface)
                switch camera.authorization {
                case .authorized:
                    CameraPreview(session: camera.session)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                case .denied, .restricted:
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash.fill").font(.system(size: 22))
                        Text("Camera access is off").font(.system(size: 12, weight: .semibold))
                        Button("Open Settings") { camera.openPrivacySettings() }
                            .buttonStyle(PillButtonStyle())
                    }
                default:
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.system(size: 22)).foregroundStyle(look.accent)
                        Text("Starting camera…").font(.system(size: 12, weight: .medium))
                    }
                }
            }
            .frame(width: 290)
            VStack(alignment: .leading, spacing: 6) {
                Text("Mirror")
                    .font(.system(size: 18, weight: .semibold))
                Text("A quick look before you join a call. The camera turns off as soon as you leave this tab.")
                    .font(.system(size: 11))
                    .foregroundStyle(look.theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Circle().fill(camera.isRunning ? Color.green : Color.gray).frame(width: 7, height: 7)
                    Text(camera.isRunning ? "Camera on" : "Camera off")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}
