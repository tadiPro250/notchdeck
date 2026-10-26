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
    /// The video-call link in the event (Zoom, Meet, Teams, Webex, FaceTime…), if there is one.
    var joinURL: URL? = nil
    /// EventKit's identifier, to open the event itself in Calendar.
    var eventIdentifier: String? = nil

    var isNow: Bool { start <= Date() && end > Date() }
    /// Starts within ten minutes, or is on now: time to join.
    var isJoinable: Bool { joinURL != nil && start.timeIntervalSinceNow < 10 * 60 && end > Date() }

    /// Hosts that run video calls, matched on the link's own host (or a subdomain of it), with
    /// the path a meeting link has there, if it needs one.
    private static let meetingHosts: [(host: String, path: String?)] = [
        ("zoom.us", nil), ("meet.google.com", nil), ("teams.microsoft.com", "/l/meetup-join"),
        ("teams.live.com", "/meet"), ("webex.com", nil), ("facetime.apple.com", "/join"), ("whereby.com", nil),
        ("around.co", nil), ("meet.jit.si", nil), ("chime.aws", nil),
    ]

    /// The first meeting link in any of these texts. Every link is checked by its host, so a
    /// page that merely mentions "zoom.us/j/" in its address isn't taken for a call.
    static func meetingLink(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for case let text? in texts {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
                      let host = url.host?.lowercased() else { continue }
                for entry in meetingHosts where host == entry.host || host.hasSuffix("." + entry.host) {
                    if let path = entry.path, !url.path.lowercased().hasPrefix(path) { continue }
                    if entry.host == "zoom.us", !["/j/", "/my/", "/w/", "/s/"].contains(where: url.path.lowercased().hasPrefix) {
                        continue
                    }
                    return secure(url)
                }
            }
        }
        return nil
    }

    /// Meeting links carry IDs and passcodes: an http:// one is opened over https:// instead, so
    /// they never travel in the clear (every one of these services serves https).
    private static func secure(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        parts.scheme = "https"
        return parts.url ?? url
    }
}

/// A day in the week strip: how many events it has and the colours of the first few.
struct CalendarDay: Identifiable, Equatable {
    let date: Date
    let count: Int
    let colors: [Color]
    var id: Date { date }
}

/// Today's and tomorrow's events from every calendar the user has in Calendar.app.
final class CalendarService: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var events: [CalendarEvent] = []
    /// Today and the six days after it.
    @Published private(set) var week: [CalendarDay] = []
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

    /// Opens the event itself in Calendar, or just Calendar when it can't be found.
    func open(_ event: CalendarEvent) {
        guard let id = event.eventIdentifier?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "ical://ekevent/\(id)?method=show&options=more") else { return openCalendarApp() }
        if !NSWorkspace.shared.open(url) { openCalendarApp() }
    }

    func join(_ event: CalendarEvent) {
        guard let url = event.joinURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    func showPreview(_ events: [CalendarEvent]) {
        access = .granted
        self.events = events
        let today = Calendar.current.startOfDay(for: Date())
        week = (0..<7).map { offset in
            let day = Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
            let count = [2, 1, 0, 3, 0, 0, 1][offset]
            return CalendarDay(date: day, count: count, colors: Array(repeating: Color.blue, count: min(count, 3)))
        }
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
        guard let end = Calendar.current.date(byAdding: .day, value: 2, to: startOfToday),
              let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: startOfToday) else { return }
        let all = store.events(matching: store.predicateForEvents(withStart: startOfToday, end: weekEnd, calendars: nil))
        week = (0..<7).compactMap { offset in
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: startOfToday),
                  let next = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return nil }
            let onDay = all.filter { $0.startDate < next && $0.endDate > day }.sorted { $0.startDate < $1.startDate }
            return CalendarDay(date: day, count: onDay.count,
                               colors: onDay.prefix(3).map { Color(nsColor: $0.calendar?.color ?? .systemBlue) })
        }
        events = all
            .filter { $0.startDate < end && $0.endDate > now }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .prefix(12)
            .map { event in
                CalendarEvent(id: event.calendarItemIdentifier + "\(event.startDate.timeIntervalSince1970)",
                              title: event.title ?? "Untitled", start: event.startDate, end: event.endDate,
                              isAllDay: event.isAllDay,
                              color: Color(nsColor: event.calendar?.color ?? .systemBlue),
                              location: event.location?.isEmpty == false ? event.location : nil,
                              joinURL: CalendarEvent.meetingLink(in: [event.url?.absoluteString, event.location, event.notes]),
                              eventIdentifier: event.eventIdentifier)
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
