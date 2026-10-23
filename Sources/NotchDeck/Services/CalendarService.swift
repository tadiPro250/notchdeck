import AppKit
import EventKit
import SwiftUI

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let location: String?

    var isNow: Bool { start <= Date() && end > Date() }
}

/// Today's and tomorrow's events from every calendar the user has in Calendar.app.
final class CalendarService: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var access: Access = .unknown

    /// Fired once per event, about five minutes before it starts.
    var onUpcoming: ((CalendarEvent) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private var notified = Set<String>()
    private var changeObserver: NSObjectProtocol?

    init(live: Bool = true) {
        guard live else { return }
        updateAccess()
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store,
                                                                queue: .main) { [weak self] _ in self?.reload() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.reload()
        }
        reload()
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateAccess()
                self?.reload()
            }
        }
    }

    func openCalendarApp() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Calendar.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    func showPreview(_ events: [CalendarEvent]) {
        access = .granted
        self.events = events
    }

    private func updateAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .unknown
        default: access = .denied
        }
    }

    func reload() {
        guard access == .granted else { return }
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        guard let end = Calendar.current.date(byAdding: .day, value: 2, to: startOfToday) else { return }
        let predicate = store.predicateForEvents(withStart: startOfToday, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .prefix(12)
            .map { event in
                CalendarEvent(id: event.calendarItemIdentifier + "\(event.startDate.timeIntervalSince1970)",
                              title: event.title ?? "Untitled", start: event.startDate, end: event.endDate,
                              isAllDay: event.isAllDay,
                              color: Color(nsColor: event.calendar?.color ?? .systemBlue),
                              location: event.location?.isEmpty == false ? event.location : nil)
            }
        for event in events where !event.isAllDay && !notified.contains(event.id) {
            let lead = event.start.timeIntervalSince(now)
            if lead > 0, lead <= 5 * 60 {
                notified.insert(event.id)
                onUpcoming?(event)
            }
        }
    }

    /// The next timed event that hasn't ended yet.
    var nextEvent: CalendarEvent? { events.first { !$0.isAllDay } ?? events.first }
}
