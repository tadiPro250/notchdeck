import AppKit
import Combine
import CoreGraphics

struct TaskStep: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var done = false
}

struct TaskItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var due: Date?
    var created = Date()
    var steps: [TaskStep] = []
    var doneAt: Date?
    /// Time spent with this as the current task, while you were at the Mac.
    var spent: TimeInterval = 0

    var isDone: Bool { doneAt != nil }

    func isOverdue(at date: Date = Date()) -> Bool {
        guard let due, !isDone else { return false }
        return due < date
    }

    var stepsText: String? {
        steps.isEmpty ? nil : "\(steps.filter(\.done).count)/\(steps.count)"
    }
}

/// The to-do list behind the Tasks tab: one current task, the rest up next by deadline, and what
/// got finished today. When the current task runs past its deadline the notch counts the overtime
/// and asks "Still on it?" every few minutes.
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    /// Picked with ↑. Without one, the open task with the earliest deadline is current.
    @Published private(set) var pinnedCurrent: UUID?
    /// The overdue task the notch is asking about right now.
    @Published private(set) var nudge: TaskItem?
    /// The current task, while it's past its deadline.
    @Published private(set) var overdue: TaskItem?
    /// Seconds focused per day ("yyyy-MM-dd").
    @Published private(set) var focusLog: [String: TimeInterval] = [:]

    /// Also counts as focus time (a Pomodoro work phase), even with no task.
    var isFocusing: () -> Bool = { false }

    private let settings: AppSettings
    private let file = AppSupport.folder.appendingPathComponent("tasks.json")
    private let persists: Bool
    private var ticker: Timer?
    private var lastTick = Date()
    private var lastNudge: [UUID: Date] = [:]
    private var nudgeHide: DispatchWorkItem?

    private struct Saved: Codable {
        var tasks: [TaskItem]
        var pinnedCurrent: UUID?
        var focusLog: [String: TimeInterval]
    }

    init(settings: AppSettings, live: Bool = true) {
        self.settings = settings
        persists = live
        guard live else { return }
        load()
        refreshOverdue()
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
    }

    // MARK: Reading

    var open: [TaskItem] {
        tasks.filter { !$0.isDone }.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.created < b.created
            }
        }
    }

    var current: TaskItem? {
        let open = open
        if let pinnedCurrent, let task = open.first(where: { $0.id == pinnedCurrent }) { return task }
        return open.first
    }

    var upNext: [TaskItem] {
        let currentID = current?.id
        return open.filter { $0.id != currentID }
    }

    var finishedToday: [TaskItem] {
        tasks.filter { $0.doneAt.map(Calendar.current.isDateInToday) ?? false }
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    /// Today's tasks: finished today, plus everything still open.
    var todayCount: (done: Int, total: Int) {
        let done = finishedToday.count
        return (done, done + open.count)
    }

    var focusedToday: TimeInterval { focusLog[Self.dayKey(Date())] ?? 0 }

    /// Days in a row, up to today, on which at least one task was finished. Today not counting
    /// yet doesn't break the streak.
    var streak: Int {
        let calendar = Calendar.current
        let days = Set(tasks.compactMap { $0.doneAt.map { calendar.startOfDay(for: $0) } })
        var day = calendar.startOfDay(for: Date())
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    // MARK: Changing

    func add(_ title: String, due: Date?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        accrue()
        tasks.append(TaskItem(title: trimmed, due: due))
        save()
    }

    func complete(_ id: UUID) {
        accrue()
        update(id) { $0.doneAt = Date() }
        if pinnedCurrent == id { pinnedCurrent = nil }
        clearNudge(id)
        NSSound(named: "Glass")?.play()
    }

    func reopen(_ id: UUID) {
        update(id) { $0.doneAt = nil }
    }

    func remove(_ id: UUID) {
        accrue()
        tasks.removeAll { $0.id == id }
        if pinnedCurrent == id { pinnedCurrent = nil }
        clearNudge(id)
        save()
    }

    /// ↑: work on this one now.
    func makeCurrent(_ id: UUID) {
        accrue()
        pinnedCurrent = id
        save()
    }

    /// "Not done": you've stopped on it for now. It stays on the list, deadline unchanged, and
    /// the next task becomes current.
    func setAside(_ id: UUID) {
        accrue()
        let next = open.first { $0.id != id }
        pinnedCurrent = next?.id
        clearNudge(id)
        lastNudge[id] = Date()
        save()
    }

    /// "+10 min": a little more time, counted from now (the old deadline has already passed).
    func extend(_ id: UUID, minutes: Double) {
        update(id) { task in
            let base = max(task.due ?? Date(), Date())
            task.due = base.addingTimeInterval(minutes * 60)
        }
        clearNudge(id)
    }

    func setDue(_ id: UUID, _ date: Date?) {
        update(id) { $0.due = date }
        lastNudge[id] = nil
    }

    func rename(_ id: UUID, _ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.title = trimmed }
    }

    func addStep(_ id: UUID, _ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.steps.append(TaskStep(title: trimmed)) }
    }

    func toggleStep(_ id: UUID, _ step: UUID) {
        update(id) { task in
            guard let index = task.steps.firstIndex(where: { $0.id == step }) else { return }
            task.steps[index].done.toggle()
        }
    }

    func removeStep(_ id: UUID, _ step: UUID) {
        update(id) { $0.steps.removeAll { $0.id == step } }
    }

    /// ×: hide the card; it asks again after the usual interval.
    func dismissNudge() {
        if let nudge { lastNudge[nudge.id] = Date() }
        nudge = nil
    }

    func showPreview(_ tasks: [TaskItem], focused: TimeInterval) {
        self.tasks = tasks
        focusLog[Self.dayKey(Date())] = focused
        refreshOverdue()
    }

    func previewNudge(_ task: TaskItem) { nudge = task }

    // MARK: Time and nudges

    private func tick() {
        accrue()
        refreshOverdue()
        checkNudge()
        // Keep finished tasks for two months, for the streak.
        let cutoff = Date().addingTimeInterval(-60 * 86400)
        if tasks.contains(where: { ($0.doneAt ?? .distantFuture) < cutoff }) {
            tasks.removeAll { ($0.doneAt ?? .distantFuture) < cutoff }
            save()
        }
    }

    /// Adds the time since the last tick to the current task and to today's focus, if you were
    /// at the Mac (any input in the last two minutes).
    private func accrue() {
        let now = Date()
        let elapsed = min(now.timeIntervalSince(lastTick), 30)
        lastTick = now
        guard elapsed > 0, Self.idleSeconds < 120 else { return }
        let task = current
        guard task != nil || isFocusing() else { return }
        if let task { update(task.id, saving: false) { $0.spent += elapsed } }
        focusLog[Self.dayKey(now), default: 0] += elapsed
        if Int(now.timeIntervalSince1970) % 60 < 5 { save() }
    }

    private func checkNudge() {
        guard settings.taskNudges, let task = current, task.isOverdue(), nudge?.id != task.id else { return }
        let interval = Double(settings.taskNudgeMinutes) * 60
        if let last = lastNudge[task.id], Date().timeIntervalSince(last) < interval { return }
        lastNudge[task.id] = Date()
        nudge = task
        NSSound(named: NSSound.Name(settings.alarmSound))?.play()
        // Folds back to the overtime count if you don't answer.
        nudgeHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if self?.nudge?.id == task.id { self?.nudge = nil }
        }
        nudgeHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }

    private func clearNudge(_ id: UUID) {
        if nudge?.id == id { nudge = nil }
    }

    private func update(_ id: UUID, saving: Bool = true, _ change: (inout TaskItem) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[index])
        if nudge?.id == id { nudge = tasks[index] }
        if saving { save() }
    }

    private func refreshOverdue() {
        let task = current.flatMap { $0.isOverdue() ? $0 : nil }
        if task != overdue { overdue = task }
    }

    private static var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Saving

    private func load() {
        guard let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        tasks = saved.tasks
        pinnedCurrent = saved.pinnedCurrent
        focusLog = saved.focusLog
    }

    private func save() {
        refreshOverdue()
        guard persists else { return }
        // Only the last month of focus totals.
        let cutoff = Self.dayKey(Date().addingTimeInterval(-31 * 86400))
        let log = focusLog.filter { $0.key >= cutoff }
        guard let data = try? JSONEncoder().encode(Saved(tasks: tasks, pinnedCurrent: pinnedCurrent, focusLog: log)) else { return }
        try? data.write(to: file, options: .atomic)
    }

    // MARK: Text

    /// "1:18:34" for overtime and countdowns.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "6h 22m", "41m", "2h".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(minutes, 0))m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// "Due today 2:07 PM · in 41m", "Over by 1:18:36 · was due today 12:08 PM".
    static func dueText(_ task: TaskItem, at now: Date = Date()) -> String? {
        guard let due = task.due else { return nil }
        let day: String
        let calendar = Calendar.current
        if calendar.isDateInToday(due) { day = "today" }
        else if calendar.isDateInTomorrow(due) { day = "tomorrow" }
        else if calendar.isDateInYesterday(due) { day = "yesterday" }
        else { day = due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
        let time = due.formatted(date: .omitted, time: .shortened)
        if due < now {
            return "Over by \(clock(now.timeIntervalSince(due))) · was due \(day) \(time)"
        }
        return "Due \(day) \(time) · in \(duration(due.timeIntervalSince(now) + 59))"
    }
}
