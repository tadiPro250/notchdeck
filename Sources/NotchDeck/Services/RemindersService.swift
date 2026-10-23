import AppKit
import EventKit
import SwiftUI

struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let due: Date?
    let listName: String
    let color: Color
    let priority: Int

    var isOverdue: Bool { (due ?? .distantFuture) < Date() }
}

/// Apple Reminders: the open to-dos, checking them off, adding new ones, and an alert in the
/// notch when one comes due.
final class RemindersService: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var items: [ReminderItem] = []
    @Published private(set) var access: Access = .unknown

    var onDue: ((ReminderItem) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private var alerted = Set<String>()
    private var observer: NSObjectProtocol?
    private var byID: [String: EKReminder] = [:]

    init(live: Bool = true) {
        guard live else { return }
        updateAccess()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store,
                                                          queue: .main) { [weak self] _ in self?.reload() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.reload() }
        reload()
    }

    func requestAccess() {
        store.requestFullAccessToReminders { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateAccess()
                self?.reload()
            }
        }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
    }

    func openRemindersApp() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Reminders.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    func showPreview(_ items: [ReminderItem]) {
        access = .granted
        self.items = items
    }

    func complete(_ item: ReminderItem) {
        guard let reminder = byID[item.id] else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        items.removeAll { $0.id == item.id }
    }

    func add(_ title: String, due: Date? = nil) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard access == .granted, !text.isEmpty, let calendar = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = text
        reminder.calendar = calendar
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try? store.save(reminder, commit: true)
        reload()
    }

    private func updateAccess() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .unknown
        default: access = .denied
        }
    }

    func reload() {
        guard access == .granted else { return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let list = (reminders ?? []).map { reminder -> (ReminderItem, EKReminder) in
                let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                return (ReminderItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? "Untitled",
                                     due: due, listName: reminder.calendar?.title ?? "",
                                     color: Color(nsColor: reminder.calendar?.color ?? .systemOrange),
                                     priority: reminder.priority), reminder)
            }
            .sorted { ($0.0.due ?? .distantFuture, $0.0.title) < ($1.0.due ?? .distantFuture, $1.0.title) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.items = list.map(\.0)
                self.byID = Dictionary(list.map { ($0.0.id, $0.1) }, uniquingKeysWith: { a, _ in a })
                let now = Date()
                for item in self.items where !self.alerted.contains(item.id) {
                    // Due now (within the last 2 minutes) and has a time, not just a day.
                    if let due = item.due, due <= now, now.timeIntervalSince(due) < 120 {
                        self.alerted.insert(item.id)
                        self.onDue?(item)
                    }
                }
            }
        }
    }
}
