import SwiftUI

enum DeskSection: String, CaseIterable, Identifiable {
    case notes, todo, colors, shortcuts, script
    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: "Notes"
        case .todo: "To-do"
        case .colors: "Colours"
        case .shortcuts: "Shortcuts"
        case .script: "Script"
        }
    }

    var symbol: String {
        switch self {
        case .notes: "note.text"
        case .todo: "checklist"
        case .colors: "eyedropper.halffull"
        case .shortcuts: "square.stack.3d.up.fill"
        case .script: "terminal.fill"
        }
    }
}

/// Notes, Apple Reminders, Shortcuts and a shell-command widget.
struct DeskView: View {
    @ObservedObject var model: NotchModel
    let services: NotchServices
    @ObservedObject var settings: AppSettings
    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                ForEach(DeskSection.allCases) { item in
                    Button { model.deskSection = item } label: {
                        HStack(spacing: 7) {
                            Image(systemName: item.symbol).frame(width: 14)
                            Text(item.title)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(model.deskSection == item ? look.accent.opacity(0.2) : .clear))
                        .foregroundStyle(model.deskSection == item ? look.accent : .white.opacity(0.65))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 112)

            Group {
                switch model.deskSection {
                case .notes: NotesPane(model: model, notes: services.notes)
                case .todo: TodoPane(model: model, reminders: services.reminders)
                case .colors: ColoursPane(model: model, colors: services.colors)
                case .shortcuts: ShortcutsPane(shortcuts: services.shortcuts)
                case .script: ScriptPane(script: services.script, settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct NotesPane: View {
    let model: NotchModel
    @ObservedObject var notes: NotesStore
    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(look.theme.surface)
                TextEditor(text: $notes.text)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .simultaneousGesture(TapGesture().onEnded { model.requestKeyboard() })
                if notes.text.isEmpty {
                    Text("Jot something down… it saves as you type.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: 8) {
                Text("\(notes.wordCount) words")
                    .font(.system(size: 10))
                    .foregroundStyle(look.theme.secondaryText)
                Spacer()
                Button { notes.copyAll() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(PillButtonStyle())
                Button { notes.clear() } label: { Label("Clear", systemImage: "trash") }
                    .buttonStyle(PillButtonStyle())
            }
        }
    }
}

private struct TodoPane: View {
    let model: NotchModel
    @ObservedObject var reminders: RemindersService
    @StateObject private var draft = ViewState<String>("")
    @Environment(\.look) private var look

    var body: some View {
        switch reminders.access {
        case .granted:
            VStack(spacing: 6) {
                if reminders.items.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle").font(.system(size: 22)).foregroundStyle(look.accent)
                        Text("All done").font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(reminders.items) { item in ReminderRow(item: item, reminders: reminders) }
                        }
                    }
                }
                HStack(spacing: 6) {
                    TextField("New reminder — press Return", text: $draft.value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit {
                            reminders.add(draft.value)
                            draft.value = ""
                        }
                        .simultaneousGesture(TapGesture().onEnded { model.requestKeyboard() })
                    IconButton(symbol: "arrow.up.forward.app", help: "Open Reminders") { reminders.openRemindersApp() }
                }
            }
        case .unknown:
            DeskPlaceholder(symbol: "checklist", title: "Your Apple Reminders, here",
                            detail: "Tick things off and add new ones without leaving what you're doing.") {
                Button("Connect Reminders") { reminders.requestAccess() }.buttonStyle(PillButtonStyle())
            }
        case .denied:
            DeskPlaceholder(symbol: "checklist", title: "Reminders access is off",
                            detail: "Turn on NotchDeck in Privacy & Security → Reminders.") {
                Button("Open Settings") { reminders.openPrivacySettings() }.buttonStyle(PillButtonStyle())
            }
        }
    }
}

private struct ReminderRow: View {
    let item: ReminderItem
    let reminders: RemindersService
    @StateObject private var done = ViewState<Bool>(false)
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 9) {
            Button {
                done.value = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { reminders.complete(item) }
            } label: {
                Image(systemName: done.value ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(done.value ? look.accent : item.color)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .strikethrough(done.value)
                    .lineLimit(1)
                if let due = item.due {
                    Text(due.formatted(date: Calendar.current.isDateInToday(due) ? .omitted : .abbreviated, time: .shortened))
                        .font(.system(size: 9.5))
                        .foregroundStyle(item.isOverdue ? .red : look.theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
            if item.priority > 0 && item.priority <= 4 {
                Image(systemName: "exclamationmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(look.theme.surface))
    }
}

private struct ShortcutsPane: View {
    @ObservedObject var shortcuts: ShortcutsService
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if shortcuts.names.isEmpty {
                DeskPlaceholder(symbol: "square.stack.3d.up.fill", title: "No shortcuts yet",
                                detail: "Make some in the Shortcuts app and they appear here, one click to run.") {
                    Button("Open Shortcuts") { shortcuts.openShortcutsApp() }.buttonStyle(PillButtonStyle())
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(shortcuts.names, id: \.self) { name in
                            Button { shortcuts.run(name) } label: {
                                HStack(spacing: 6) {
                                    if shortcuts.running == name {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(systemName: shortcuts.lastResult?.name == name
                                              ? (shortcuts.lastResult?.ok == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                                              : "play.circle.fill")
                                            .foregroundStyle(look.accent)
                                    }
                                    Text(name).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 9)
                                .frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(look.theme.surface))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear { shortcuts.reload() }
    }
}

private struct ScriptPane: View {
    @ObservedObject var script: ScriptRunner
    @ObservedObject var settings: AppSettings
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill").foregroundStyle(look.accent)
                Text(settings.scriptCommand.isEmpty ? "No command set" : settings.scriptCommand)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let last = script.lastRun {
                    Text(last.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(look.theme.secondaryText)
                }
                IconButton(symbol: script.isRunning ? "hourglass" : "arrow.clockwise", help: "Run now") { script.run() }
            }
            ScrollView {
                Text(script.output.isEmpty ? "Set a command in Settings → Desk. It runs every \(settings.scriptInterval) s while this view is open."
                                           : script.output)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(script.failed ? Color.red.opacity(0.9) : .white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.35)))
        }
        .onAppear { script.startRefreshing() }
        .onDisappear { script.stopRefreshing() }
    }
}

struct DeskPlaceholder<Extra: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let extra: Extra
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(look.accent)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(look.theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            extra.padding(.top, 4)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The colour picker: the last colour large with its codes, and the saved palette.
private struct ColoursPane: View {
    let model: NotchModel
    @ObservedObject var colors: ColorDropper
    @StateObject private var copied = ViewState<String?>(nil)
    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if let hex = colors.last {
                    let formats = ColorDropper.formats(hex)
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: hex) ?? .white)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.25)))
                            .shadow(color: (Color(hex: hex) ?? .clear).opacity(0.5), radius: 12)
                            .frame(width: 84, height: 84)
                            .overlay(Text(copied.value == hex ? "Copied" : "")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(ColorDropper.ink(on: hex)))
                        VStack(alignment: .leading, spacing: 3) {
                            code(hex, big: true)
                            code(formats.rgb)
                            code(formats.hsl)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pick any colour on screen").font(.system(size: 13, weight: .semibold))
                        Text("The loupe zooms in; click to take the colour. Its hex is copied and saved here.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(look.theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(height: 84, alignment: .leading)
                }
                HStack(spacing: 6) {
                    Button { model.pickColor() } label: {
                        Label("Pick", systemImage: "eyedropper")
                    }
                    .buttonStyle(AccentPillStyle())
                    if let hex = colors.last {
                        Button { copy(hex) } label: { Label("Copy", systemImage: "doc.on.doc") }
                            .buttonStyle(PillButtonStyle())
                        if !colors.isSaved {
                            Button { colors.save(hex) } label: { Label("Save", systemImage: "plus") }
                                .buttonStyle(PillButtonStyle())
                        }
                    }
                }
                Text("Anywhere: \(AppSettings.shared.colorHotKey.title)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(width: 250, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("SAVED").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    if !colors.saved.isEmpty {
                        Button("Clear") { colors.clear() }
                            .buttonStyle(.plain)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                if colors.saved.isEmpty {
                    Text("Colours you pick land here.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(look.theme.secondaryText)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 34), spacing: 7)], spacing: 7) {
                            ForEach(colors.saved) { saved in
                                SwatchChip(saved: saved, selected: saved.hex == colors.last) {
                                    colors.select(saved.hex)
                                    flash(saved.hex)
                                }
                                .contextMenu {
                                    Button("Copy \(saved.hex)") { copy(saved.hex) }
                                    Button("Copy \(ColorDropper.formats(saved.hex).rgb)") { ColorDropper.copy(ColorDropper.formats(saved.hex).rgb) }
                                    Button("Remove", role: .destructive) { colors.remove(saved) }
                                }
                            }
                        }
                        .padding(3)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func code(_ text: String, big: Bool = false) -> some View {
        Button { copy(text) } label: {
            Text(text)
                .font(.system(size: big ? 18 : 10.5, weight: big ? .bold : .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(big ? 1 : 0.6))
        }
        .buttonStyle(.plain)
        .help("Copy")
    }

    private func copy(_ text: String) {
        ColorDropper.copy(text)
        flash(colors.last ?? text)
    }

    private func flash(_ hex: String) {
        copied.value = hex
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copied.value == hex { copied.value = nil } }
    }
}

private struct SwatchChip: View {
    let saved: SavedColor
    let selected: Bool
    let action: () -> Void
    @StateObject private var hovering = ViewState<Bool>(false)

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(saved.color)
                .frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.white : Color.white.opacity(0.18), lineWidth: selected ? 2 : 0.8))
                .scaleEffect(hovering.value ? 1.12 : 1)
                .shadow(color: saved.color.opacity(hovering.value ? 0.6 : 0), radius: 6)
        }
        .buttonStyle(.plain)
        .help(saved.hex)
        .onHover { hovering.value = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: hovering.value)
    }
}
