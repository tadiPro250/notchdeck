import AppKit
import SwiftUI

struct Alarm: Codable, Identifiable, Equatable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var label: String
    /// Weekdays it repeats on, 1 = Sunday … 7 = Saturday. Empty: rings once.
    var repeatDays: Set<Int> = []
    var enabled = true
    var snoozedUntil: Date?

    var timeText: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    var repeatText: String {
        if repeatDays.isEmpty { return "Once" }
        if repeatDays.count == 7 { return "Every day" }
        if repeatDays == [2, 3, 4, 5, 6] { return "Weekdays" }
        if repeatDays == [1, 7] { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return repeatDays.sorted().map { symbols[$0 - 1] }.joined(separator: " ")
    }

    /// The next moment this alarm rings, after `date`.
    func nextFire(after date: Date) -> Date? {
        guard enabled else { return nil }
        if let snoozedUntil, snoozedUntil > date { return snoozedUntil }
        let calendar = Calendar.current
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fire > date else { continue }
            if repeatDays.isEmpty || repeatDays.contains(calendar.component(.weekday, from: fire)) { return fire }
        }
        return nil
    }
}

/// Something ringing right now: an alarm, or a timer that ran out.
struct Ringing: Equatable {
    enum Kind: Equatable {
        case alarm(Alarm)
        case timer
    }

    var kind: Kind
    var startedAt = Date()

    var title: String {
        switch kind {
        case .alarm(let alarm): alarm.label.isEmpty ? "Alarm" : alarm.label
        case .timer: "Timer done"
        }
    }

    var detail: String {
        switch kind {
        case .alarm(let alarm): alarm.timeText
        case .timer: "Time's up"
        }
    }

    var symbol: String {
        switch kind {
        case .alarm: "alarm.fill"
        case .timer: "timer"
        }
    }
}

/// Alarms, the countdown timer and the stopwatch. Everything here shows in the notch.
final class ClockCenter: ObservableObject {
    @Published var alarms: [Alarm] { didSet { saveAlarms() } }
    @Published private(set) var ringing: Ringing?

    // Stopwatch
    @Published private(set) var stopwatchStart: Date?
    @Published private(set) var stopwatchAccumulated: TimeInterval = 0
    @Published private(set) var laps: [TimeInterval] = []

    let timer: FocusTimer
    private let settings: AppSettings
    private var ticker: Timer?
    private var sound: NSSound?
    private var autoStop: DispatchWorkItem?
    private let defaultsKey = "clock.alarms"
    private let persists: Bool

    init(timer: FocusTimer, settings: AppSettings, live: Bool = true) {
        self.timer = timer
        self.settings = settings
        self.persists = live
        if live, let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([Alarm].self, from: data) {
            alarms = saved
        } else {
            alarms = []
        }
        guard live else { return }
        timer.onFinish = { [weak self] in self?.ring(.timer) }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    // MARK: Alarms

    func addAlarm(hour: Int, minute: Int, label: String, repeatDays: Set<Int>) {
        alarms.append(Alarm(hour: hour, minute: minute, label: label, repeatDays: repeatDays))
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    func toggle(_ alarm: Alarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index].enabled.toggle()
        alarms[index].snoozedUntil = nil
    }

    func delete(_ alarm: Alarm) {
        alarms.removeAll { $0.id == alarm.id }
    }

    var nextAlarm: (alarm: Alarm, date: Date)? {
        let now = Date()
        return alarms.compactMap { alarm in alarm.nextFire(after: now).map { (alarm, $0) } }
            .min { $0.1 < $1.1 }
    }

    // MARK: Ringing

    func ring(_ kind: Ringing.Kind) {
        ringing = Ringing(kind: kind)
        sound?.stop()
        let name = settings.alarmSound
        sound = NSSound(named: NSSound.Name(name)) ?? NSSound(named: "Glass")
        sound?.loops = true
        sound?.play()
        // Don't ring forever if nobody is at the Mac.
        autoStop?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stopRinging() }
        autoStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5 * 60, execute: work)
    }

    func snooze() {
        guard let ringing else { return }
        if case .alarm(let alarm) = ringing.kind, let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index].snoozedUntil = Date().addingTimeInterval(Double(settings.snoozeMinutes) * 60)
        } else if case .timer = ringing.kind {
            timer.start(minutes: Double(settings.snoozeMinutes))
        }
        silence()
    }

    func stopRinging() {
        guard let ringing else { return }
        if case .alarm(let alarm) = ringing.kind, let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index].snoozedUntil = nil
            if alarms[index].repeatDays.isEmpty { alarms[index].enabled = false }
        }
        silence()
    }

    private func silence() {
        sound?.stop()
        sound = nil
        autoStop?.cancel()
        ringing = nil
    }

    private var lastCheckedMinute: Int?

    private func tick() {
        let now = Date()
        let calendar = Calendar.current
        let minuteStamp = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        guard ringing == nil else { return }

        for (index, alarm) in alarms.enumerated() where alarm.enabled {
            if let snoozedUntil = alarm.snoozedUntil {
                if snoozedUntil <= now {
                    alarms[index].snoozedUntil = nil
                    ring(.alarm(alarms[index]))
                    return
                }
                continue
            }
            guard minuteStamp != lastCheckedMinute,
                  alarm.hour * 60 + alarm.minute == minuteStamp,
                  alarm.repeatDays.isEmpty || alarm.repeatDays.contains(calendar.component(.weekday, from: now))
            else { continue }
            lastCheckedMinute = minuteStamp
            ring(.alarm(alarm))
            return
        }
    }

    // MARK: Stopwatch

    var stopwatchRunning: Bool { stopwatchStart != nil }
    var stopwatchActive: Bool { stopwatchStart != nil || stopwatchAccumulated > 0 }

    func stopwatchElapsed(at date: Date = Date()) -> TimeInterval {
        stopwatchAccumulated + (stopwatchStart.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggleStopwatch() {
        if let start = stopwatchStart {
            stopwatchAccumulated += Date().timeIntervalSince(start)
            stopwatchStart = nil
        } else {
            stopwatchStart = Date()
        }
    }

    func lap() {
        guard stopwatchRunning else { return }
        laps.insert(stopwatchElapsed(), at: 0)
    }

    func resetStopwatch() {
        stopwatchStart = nil
        stopwatchAccumulated = 0
        laps = []
    }

    func showPreview(stopwatch: TimeInterval) {
        stopwatchStart = Date().addingTimeInterval(-stopwatch)
    }

    func showPreview(ringing: Ringing) {
        self.ringing = ringing
    }

    static func stopwatchText(_ seconds: TimeInterval, hundredths: Bool = true) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        let cs = Int((seconds - Double(total)) * 100)
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return hundredths ? String(format: "%02d:%02d.%02d", m, s, cs) : String(format: "%d:%02d", m, s)
    }

    private func saveAlarms() {
        guard persists, let data = try? JSONEncoder().encode(alarms) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
