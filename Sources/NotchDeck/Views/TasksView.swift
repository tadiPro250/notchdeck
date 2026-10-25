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

/// The deadline (any amount of time, or an exact date) and the steps checklist.
private struct TaskDetail: View {
    let task: TaskItem
    let tasks: TaskStore
    let model: NotchModel
    let now: Date
    @StateObject private var step = ViewState<String>("")

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            DeadlinePicker(model: model, current: task.due) { tasks.setDue(task.id, $0) }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(0.3)))

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
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(0.3)))
        }
    }
}

/// Any amount of time: "in" days, hours and minutes on scroll drums, or "on" an exact date and
/// time, with quick picks, and a live preview of when that lands.
struct DeadlinePicker: View {
    enum Mode { case relative, exact }

    let model: NotchModel
    /// The deadline being edited, if there is one.
    let current: Date?
    var actionTitle = "Set"
    let onSet: (Date?) -> Void

    @StateObject private var mode = ViewState<Mode>(.relative)
    @StateObject private var days = ViewState<Int>(0)
    @StateObject private var hours = ViewState<Int>(1)
    @StateObject private var minutes = ViewState<Int>(0)
    @StateObject private var exact = ViewState<Date>(Date().addingTimeInterval(3600))
    @StateObject private var primed = ViewState<Bool>(false)

    private let blue = Color(red: 0.4, green: 0.7, blue: 1)

    private var proposed: Date {
        switch mode.value {
        case .relative:
            return Date().addingTimeInterval(Double(days.value) * 86400 + Double(hours.value) * 3600 + Double(minutes.value) * 60)
        case .exact:
            return exact.value
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Deadline", systemImage: "flag.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                HStack(spacing: 2) {
                    segment("In", .relative)
                    segment("On", .exact)
                }
                .padding(2)
                .background(Capsule().fill(Color.white.opacity(0.07)))
            }

            if mode.value == .relative {
                HStack(spacing: 2) {
                    wheel($days.value, 0...365, "days", help: "Scroll to set days") { delta, _ in step(days: delta) }
                    colon
                    wheel($hours.value, 0...23, "hours", help: "Scroll to set hours (carries into days)") { delta, _ in step(hours: delta) }
                    colon
                    wheel($minutes.value, 0...59, "min", help: "Scroll to set minutes; hold ⌥ for 1-minute steps") { delta, fine in
                        step(minutes: fine ? delta : delta * 5)
                    }
                }
                .frame(height: 104)
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 8) {
                    DatePicker("", selection: $exact.value, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.stepperField)
                        .simultaneousGesture(TapGesture().onEnded { model.requestKeyboard() })
                    Spacer(minLength: 0)
                }
                .frame(height: 30)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Self.presets, id: \.title) { preset in
                        Button(preset.title) { apply(preset) }
                            .buttonStyle(ChipStyle())
                    }
                }
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("→ " + Self.describe(proposed))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(blue)
                    Text("in " + TaskStore.duration(max(proposed.timeIntervalSinceNow, 0) + 59))
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                if current != nil {
                    Button("Clear") { onSet(nil) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .help("No deadline")
                }
                Button(actionTitle) { onSet(proposed) }
                    .buttonStyle(SetButtonStyle())
                    .disabled(proposed <= Date())
            }
        }
        .onAppear(perform: prime)
    }

    private var colon: some View {
        Text(":")
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.4))
            .offset(y: -6)
    }

    private func wheel(_ value: Binding<Int>, _ range: ClosedRange<Int>, _ unit: String, help: String,
                       onStep: @escaping (Int, Bool) -> Void) -> some View {
        DrumWheel(value: value, range: range, unit: unit, help: help, onStep: onStep)
    }

    private func segment(_ title: String, _ value: Mode) -> some View {
        Button { mode.value = value } label: {
            Text(title)
                .font(.system(size: 9.5, weight: .bold))
                .frame(width: 30, height: 17)
                .foregroundStyle(mode.value == value ? .black : .white.opacity(0.6))
                .background(Capsule().fill(mode.value == value ? blue : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Starts from the task's deadline when it has one still ahead.
    private func prime() {
        guard !primed.value else { return }
        primed.value = true
        guard let current, current > Date() else { return }
        let total = Int(current.timeIntervalSinceNow / 60)
        days.value = min(total / 1440, 365)
        hours.value = total / 60 % 24
        minutes.value = total % 60
        exact.value = current
    }

    // Steps carry over: 59 minutes + 1 rolls into the next hour, and so on.
    private var totalMinutes: Int { days.value * 1440 + hours.value * 60 + minutes.value }

    private func setTotal(_ total: Int) {
        let clamped = min(max(total, 1), 365 * 1440 + 23 * 60 + 59)
        days.value = clamped / 1440
        hours.value = clamped / 60 % 24
        minutes.value = clamped % 60
    }

    private func step(days delta: Int) { setTotal(totalMinutes + delta * 1440) }
    private func step(hours delta: Int) { setTotal(totalMinutes + delta * 60) }
    private func step(minutes delta: Int) { setTotal(totalMinutes + delta) }

    struct Preset {
        let title: String
        /// Minutes from now, or a fixed moment.
        var minutes: Int?
        var date: (() -> Date)?
    }

    static let presets: [Preset] = [
        Preset(title: "1h", minutes: 60),
        Preset(title: "3h", minutes: 180),
        Preset(title: "Tonight", date: { at(hour: 21, daysAhead: 0) }),
        Preset(title: "Tomorrow 9am", date: { at(hour: 9, daysAhead: 1) }),
        Preset(title: "3 days", minutes: 3 * 1440),
        Preset(title: "1 week", minutes: 7 * 1440),
        Preset(title: "End of week", date: {
            let calendar = Calendar.current
            let friday = calendar.nextDate(after: Date(), matching: DateComponents(hour: 18, weekday: 6), matchingPolicy: .nextTime)
            return friday ?? Date().addingTimeInterval(3 * 86400)
        }),
        Preset(title: "End of month", date: {
            let calendar = Calendar.current
            let start = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
            let last = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? Date()
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: last) ?? last
        }),
    ]

    private func apply(_ preset: Preset) {
        if let minutes = preset.minutes {
            mode.value = .relative
            setTotal(minutes)
        } else if let date = preset.date?() {
            exact.value = date
            mode.value = .exact
        }
    }

    /// Today at `hour`, or tomorrow at it if that has passed.
    private static func at(hour: Int, daysAhead: Int) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: daysAhead, to: Date()) ?? Date()
        var date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
        if date <= Date() { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
        return date
    }

    static func describe(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "today " + time }
        if calendar.isDateInTomorrow(date) { return "tomorrow " + time }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", " + time
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
    /// A deadline from the custom picker, which wins over the quick choices.
    @StateObject private var custom = ViewState<Date?>(nil)
    @StateObject private var picking = ViewState<Bool>(false)
    @Environment(\.look) private var look

    private static let quick: [(Int?, String)] = [(30, "30m"), (60, "1h"), (180, "3h"), (1440, "1d"), (nil, "None")]

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
            if picking.value {
                DeadlinePicker(model: model, current: custom.value, actionTitle: "Use") { date in
                    custom.value = date
                    picking.value = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
            } else {
                HStack(spacing: 4) {
                    Text("Due").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                    if let date = custom.value {
                        Button(DeadlinePicker.describe(date)) { picking.value = true }
                            .buttonStyle(ChipStyle(selected: true))
                        Button { custom.value = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(ChipStyle())
                    } else {
                        ForEach(Self.quick, id: \.1) { choice in
                            Button(choice.1) { minutes.value = choice.0 }
                                .buttonStyle(ChipStyle(selected: minutes.value == choice.0))
                        }
                    }
                    Button { picking.value = true } label: { Image(systemName: "slider.horizontal.3") }
                        .buttonStyle(ChipStyle())
                        .help("Custom: any number of days, hours and minutes, or a date")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(GlassTile(corner: 14))
    }

    private func add() {
        tasks.add(title.value, due: custom.value ?? minutes.value.map { Date().addingTimeInterval(Double($0) * 60) })
        title.value = ""
        custom.value = nil
        picking.value = false
    }
}
