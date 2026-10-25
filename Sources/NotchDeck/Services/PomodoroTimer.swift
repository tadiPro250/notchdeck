import AppKit

/// Work and break cycles: work, short break, work, … and a long break after the last round of a
/// set. While it runs the closed notch shows the ring and the time left; each change of phase
/// drops a card and plays a sound.
final class PomodoroTimer: ObservableObject {
    enum Phase: String, Codable {
        case work, shortBreak, longBreak

        var title: String {
            switch self {
            case .work: "Focus"
            case .shortBreak: "Short break"
            case .longBreak: "Long break"
            }
        }

        var symbol: String { self == .work ? "brain.head.profile" : "cup.and.saucer.fill" }
        var isBreak: Bool { self != .work }
    }

    @Published private(set) var phase: Phase = .work
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var duration: TimeInterval = 0
    /// 1-based round within the set.
    @Published private(set) var round = 1
    @Published private(set) var completedToday = 0

    /// The phase that just ended and the one that comes next.
    var onPhaseChange: ((Phase, Phase) -> Void)?

    private let settings: AppSettings
    private var ticker: Timer?
    private let defaults: UserDefaults

    init(settings: AppSettings, live: Bool = true) {
        self.settings = settings
        defaults = live ? .standard : UserDefaults(suiteName: "com.premprateek.notchdeck.previews") ?? .standard
        if defaults.string(forKey: "pomodoro.day") == TaskStore.dayKey(Date()) {
            completedToday = defaults.integer(forKey: "pomodoro.count")
        }
    }

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isRunning: Bool { endDate != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var rounds: Int { max(settings.pomodoroRounds, 1) }

    func length(of phase: Phase) -> TimeInterval {
        switch phase {
        case .work: Double(settings.pomodoroWork) * 60
        case .shortBreak: Double(settings.pomodoroShortBreak) * 60
        case .longBreak: Double(settings.pomodoroLongBreak) * 60
        }
    }

    func remaining(at date: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return length(of: phase) }
        return max(endDate.timeIntervalSince(date), 0)
    }

    func progress(at date: Date = Date()) -> Double {
        duration > 0 ? 1 - remaining(at: date) / duration : 0
    }

    func start() {
        guard !isActive else { return }
        begin(phase)
    }

    func togglePause() {
        if let pausedRemaining {
            endDate = Date().addingTimeInterval(pausedRemaining)
            self.pausedRemaining = nil
            startTicker()
        } else if endDate != nil {
            pausedRemaining = remaining()
            endDate = nil
            ticker?.invalidate()
        } else {
            start()
        }
    }

    /// Ends this phase now and moves on (a skipped work phase doesn't count).
    func skip() {
        guard isActive else {
            advance(counting: false)
            return
        }
        finish(counting: false)
    }

    func reset() {
        ticker?.invalidate()
        endDate = nil
        pausedRemaining = nil
        phase = .work
        round = 1
    }

    func showPreview(phase: Phase, remaining: TimeInterval, round: Int) {
        self.phase = phase
        self.round = round
        duration = length(of: phase)
        endDate = Date().addingTimeInterval(remaining)
        completedToday = 3
    }

    private func begin(_ phase: Phase) {
        self.phase = phase
        duration = length(of: phase)
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(duration)
        startTicker()
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let end = self.endDate, Date() >= end else { return }
            self.finish(counting: true)
        }
    }

    private func finish(counting: Bool) {
        ticker?.invalidate()
        endDate = nil
        pausedRemaining = nil
        let ended = phase
        advance(counting: counting)
        onPhaseChange?(ended, phase)
        if settings.pomodoroAutoStart { begin(phase) }
    }

    /// Picks the next phase (and round) without starting it.
    private func advance(counting: Bool) {
        switch phase {
        case .work:
            if counting { countRound() }
            phase = round >= rounds ? .longBreak : .shortBreak
        case .shortBreak:
            round += 1
            phase = .work
        case .longBreak:
            round = 1
            phase = .work
        }
        duration = length(of: phase)
    }

    private func countRound() {
        let today = TaskStore.dayKey(Date())
        if defaults.string(forKey: "pomodoro.day") != today { completedToday = 0 }
        completedToday += 1
        defaults.set(today, forKey: "pomodoro.day")
        defaults.set(completedToday, forKey: "pomodoro.count")
    }
}
