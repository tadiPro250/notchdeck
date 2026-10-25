import SwiftUI

private let overdueRed = Color(red: 1, green: 0.32, blue: 0.32)

/// The Tasks tab: today at a glance and the task you're on (left), what's next by deadline and
/// what got done (right). One task opens at a time to edit its deadline and steps.
struct TasksView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var tasks: TaskStore
    @ObservedObject var pomodoro: PomodoroTimer
    @StateObject private var expanded = ViewState<UUID?>(nil)
    @StateObject private var showFinished = ViewState<Bool>(true)
    @Environment(\.look) private var look

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    TodayHeader(tasks: tasks, pomodoro: pomodoro, openSettings: model.openSettings)
                    ScrollView(.vertical, showsIndicators: false) {
                        if let current = tasks.current {
                            TaskCard(task: current, tasks: tasks, model: model, now: context.date, isCurrent: true,
                                     expanded: $expanded.value)
                        } else {
                            EmptyCurrent()
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    NewTaskField(model: model, tasks: tasks)
                }
                .frame(width: 300)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SectionLabel(text: "Up next")
                            Spacer()
                            Text("by deadline").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                        }
                        if tasks.upNext.isEmpty {
                            Text(tasks.current == nil ? "Add a task with a deadline below." : "Nothing else queued.")
                                .font(.system(size: 11))
                                .foregroundStyle(look.theme.secondaryText)
                                .padding(.vertical, 6)
                        }
                        ForEach(tasks.upNext) { task in
                            TaskCard(task: task, tasks: tasks, model: model, now: context.date, isCurrent: false,
                                     expanded: $expanded.value)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        let finished = tasks.finishedToday
                        if !finished.isEmpty {
                            Button { showFinished.value.toggle() } label: {
                                HStack(spacing: 4) {
                                    SectionLabel(text: "Finished today")
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                        .rotationEffect(.degrees(showFinished.value ? 0 : -90))
                                        .foregroundStyle(.white.opacity(0.5))
                                    Spacer()
                                    Text("\(finished.count) done").font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
                            if showFinished.value {
                                ForEach(finished) { task in FinishedRow(task: task, tasks: tasks) }
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: tasks.tasks)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: expanded.value)
    }
}

private struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(.white.opacity(0.55))
    }
}

/// "Saturday, 24 Oct", "1 of 4 done · 6h 22m focused", progress, streak and settings.
private struct TodayHeader: View {
    @ObservedObject var tasks: TaskStore
    @ObservedObject var pomodoro: PomodoroTimer
    let openSettings: () -> Void

    var body: some View {
        let count = tasks.todayCount
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                if tasks.streak > 0 {
                    Label("\(tasks.streak)", systemImage: "flame.fill")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(Capsule().fill(Color.orange.opacity(0.16)))
                        .help("\(tasks.streak)-day streak of finishing something")
                }
                IconButton(symbol: "gearshape.fill", help: "Task settings", action: openSettings)
            }
            Text([ "\(count.done) of \(count.total) done", "\(TaskStore.duration(tasks.focusedToday)) focused",
                   pomodoro.completedToday > 0 ? "\(pomodoro.completedToday) 🍅" : nil ].compactMap { $0 }
                .joined(separator: " · "))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(Color.green)
                        .frame(width: count.total > 0 ? max(geo.size.width * Double(count.done) / Double(count.total), 4) : 0)
                }
            }
            .frame(height: 4)
        }
    }
}

private struct EmptyCurrent: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 20)).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("All clear").font(.system(size: 13, weight: .semibold))
                Text("Add what you're working on and when it's due.")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassTile(corner: 16))
    }
}

/// A task: the current one large (red once overdue), the rest as rows. Click the title to open
/// its deadline and steps.
private struct TaskCard: View {
    let task: TaskItem
    let tasks: TaskStore
    let model: NotchModel
    let now: Date
    let isCurrent: Bool
    @Binding var expanded: UUID?

    var body: some View {
        let overdue = task.isOverdue(at: now)
        let open = expanded == task.id
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if isCurrent {
                    ZStack {
                        Circle().stroke(overdue ? overdueRed : Color.white.opacity(0.6), lineWidth: 2.5)
                        if overdue {
                            Text("!").font(.system(size: 14, weight: .heavy)).foregroundStyle(overdueRed)
                        } else {
                            Circle().fill(Color.white.opacity(0.6)).frame(width: 6, height: 6)
                        }
                    }
                    .frame(width: 30, height: 30)
                } else {
                    Circle()
                        .strokeBorder(overdue ? overdueRed : Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                        .frame(width: 16, height: 16)
                }
                Button { expanded = open ? nil : task.id } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(task.title)
                                .font(.system(size: isCurrent ? 13.5 : 12, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .rotationEffect(.degrees(open ? 180 : 0))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        HStack(spacing: 6) {
                            if let due = TaskStore.dueText(task, at: now) {
                                Text(due)
                                    .foregroundStyle(overdue ? overdueRed : .white.opacity(0.55))
                                    .lineLimit(isCurrent ? 2 : 1)
                            } else {
                                Text("No deadline").foregroundStyle(.white.opacity(0.4))
                            }
                            if let steps = task.stepsText {
                                Label(steps, systemImage: "list.bullet.indent")
                                    .foregroundStyle(.white.opacity(0.55))
                                    .labelStyle(CompactLabelStyle())
                            }
                        }
                        .font(.system(size: 10, weight: overdue ? .semibold : .medium).monospacedDigit())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack(spacing: 5) {
                    if !isCurrent {
                        RoundAction(symbol: "arrow.up", hover: .blue, help: "Work on this now") { tasks.makeCurrent(task.id) }
                    }
                    RoundAction(symbol: "xmark", hover: .red, help: "Drop this task") { tasks.remove(task.id) }
                    RoundAction(symbol: "checkmark", hover: .green, help: "Done") { tasks.complete(task.id) }
                }
            }
            if open {
                TaskDetail(task: task, tasks: tasks, model: model, now: now)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .padding(.horizontal, isCurrent ? 12 : 10)
        .padding(.vertical, isCurrent ? 11 : 7)
        .background {
            if isCurrent {
                // A dark base first, so the red reads over photo backgrounds too.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(overdue ? overdueRed.opacity(0.2) : Color.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(overdue ? overdueRed.opacity(0.45) : Color.white.opacity(0.12), lineWidth: 1))
            } else if open {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06))
            }
        }
        .contextMenu {
            Button("Work on This Now") { tasks.makeCurrent(task.id) }
            Button("Remove Deadline") { tasks.setDue(task.id, nil) }
            Button("Mark Done") { tasks.complete(task.id) }
            Button("Drop Task", role: .destructive) { tasks.remove(task.id) }
        }
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.font(.system(size: 8))
            configuration.title
        }
    }
}

/// Grey until hovered, then blue (↑), red (×) or green (✓).
private struct RoundAction: View {
    let symbol: String
    let hover: Color
    let help: String
    let action: () -> Void
    @StateObject private var hovering = ViewState<Bool>(false)

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .frame(width: 22, height: 22)
                .foregroundStyle(.white.opacity(hovering.value ? 1 : 0.7))
                .background(Circle().fill(hovering.value ? hover : Color.white.opacity(0.1)))
                .scaleEffect(hovering.value ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering.value = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: hovering.value)
    }
}

/// Deadline (how long from now, on which day) and the steps checklist.
private struct TaskDetail: View {
    let task: TaskItem
    let tasks: TaskStore
    let model: NotchModel
    let now: Date
    @StateObject private var minutes = ViewState<Int>(30)
    @StateObject private var days = ViewState<Int>(0)
    @StateObject private var step = ViewState<String>("")

    static let amounts = [15, 30, 45, 60, 90, 120, 180, 240, 360]
    static let dayChoices: [(Int, String)] = [(0, "Today"), (1, "Tomorrow"), (2, "In 2 days"), (7, "Next week")]

    private var proposed: Date {
        now.addingTimeInterval(Double(days.value) * 86400 + Double(minutes.value) * 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Deadline", systemImage: "flag.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text("→ " + Self.describe(proposed))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1))
                }
                HStack(spacing: 6) {
                    Menu {
                        ForEach(Self.amounts, id: \.self) { amount in
                            Button(TaskStore.duration(Double(amount) * 60)) { minutes.value = amount }
                        }
                    } label: {
                        Label(TaskStore.duration(Double(minutes.value) * 60), systemImage: "clock")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.blue.opacity(0.25)))
                    Menu {
                        ForEach(Self.dayChoices, id: \.0) { choice in
                            Button(choice.1) { days.value = choice.0 }
                        }
                    } label: {
                        Label(Self.dayChoices.first { $0.0 == days.value }?.1 ?? "Day", systemImage: "calendar")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                    Button("Set") { tasks.setDue(task.id, proposed) }
                        .buttonStyle(SetButtonStyle())
                }
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(0.25)))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Steps").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    if let text = task.stepsText {
                        Text(text).font(.system(size: 9.5, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                    }
                }
                ForEach(task.steps) { item in
                    HStack(spacing: 7) {
                        Button { tasks.toggleStep(task.id, item.id) } label: {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(item.done ? .green : .white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium))
                            .strikethrough(item.done)
                            .foregroundStyle(.white.opacity(item.done ? 0.45 : 0.9))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button { tasks.removeStep(task.id, item.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                    TextField("Add a step and press Return", text: $step.value)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .onSubmit {
                            tasks.addStep(task.id, step.value)
                            step.value = ""
                        }
                        .simultaneousGesture(TapGesture().onEnded { model.requestKeyboard() })
                }
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(0.25)))
        }
    }

    static func describe(_ date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(date) ? "today" : calendar.isDateInTomorrow(date) ? "tomorrow"
            : date.formatted(.dateTime.weekday(.abbreviated).day())
        return day + " " + date.formatted(date: .omitted, time: .shortened)
    }
}

private struct SetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 22)
            .background(Capsule().fill(Color.blue.opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Capsule())
    }
}

private struct FinishedRow: View {
    let task: TaskItem
    let tasks: TaskStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(.green)
            Text(task.title)
                .font(.system(size: 11.5, weight: .medium))
                .strikethrough()
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Spacer(minLength: 0)
            if task.spent >= 60 {
                Text(TaskStore.duration(task.spent))
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
                    .help("Time spent on it")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contextMenu {
            Button("Not Done After All") { tasks.reopen(task.id) }
            Button("Remove", role: .destructive) { tasks.remove(task.id) }
        }
    }
}

/// A title and a deadline, then Return.
private struct NewTaskField: View {
    let model: NotchModel
    @ObservedObject var tasks: TaskStore
    @StateObject private var title = ViewState<String>("")
    @StateObject private var minutes = ViewState<Int?>(60)
    @Environment(\.look) private var look

    private static let quick: [(Int?, String)] = [(30, "30m"), (60, "1h"), (180, "3h"), (nil, "None")]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(look.accent == .white ? Color.blue : look.accent)
                TextField("New task, then Return", text: $title.value)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .onSubmit(add)
                    .simultaneousGesture(TapGesture().onEnded { model.requestKeyboard() })
            }
            HStack(spacing: 4) {
                Text("Due in").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                ForEach(Self.quick, id: \.1) { choice in
                    Button(choice.1) { minutes.value = choice.0 }
                        .buttonStyle(ChipStyle(selected: minutes.value == choice.0))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(GlassTile(corner: 14))
    }

    private func add() {
        tasks.add(title.value, due: minutes.value.map { Date().addingTimeInterval(Double($0) * 60) })
        title.value = ""
    }
}
