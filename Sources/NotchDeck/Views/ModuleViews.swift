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
                    Spacer(minLength: 0)
                    Button { calendar.openCalendarApp() } label: {
                        Label("Open Calendar", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }
            .frame(width: 130, alignment: .leading)

            Group {
                switch calendar.access {
                case .granted:
                    if calendar.events.isEmpty {
                        placeholder(symbol: "checkmark.circle", title: "Nothing left today or tomorrow",
                                    detail: "Enjoy the free time.")
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 6) {
                                ForEach(calendar.events) { event in EventRow(event: event) }
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

private struct EventRow: View {
    let event: CalendarEvent
    @Environment(\.look) private var look

    var body: some View {
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
    @Environment(\.look) private var look

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
                        ForEach(history.sortedItems) { item in
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
                VStack(spacing: 8) {
                    Text("\(history.items.count)")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("items")
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
                .frame(width: 80)
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
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
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
