import AppKit

/// A countdown that lives in the notch: the collapsed notch shows the time left, and it rings
/// through `ClockCenter` when it runs out.
final class FocusTimer: ObservableObject {
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var duration: TimeInterval = 0

    var onFinish: (() -> Void)?

    private var ticker: Timer?

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at date: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(endDate.timeIntervalSince(date), 0)
    }

    func progress(at date: Date = Date()) -> Double {
        duration > 0 ? 1 - remaining(at: date) / duration : 0
    }

    func start(minutes: Double) {
        duration = minutes * 60
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(duration)
        startTicker()
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
        }
    }

    func cancel() {
        ticker?.invalidate()
        endDate = nil
        pausedRemaining = nil
    }

    func showPreview(remaining: TimeInterval, of total: TimeInterval) {
        duration = total
        endDate = Date().addingTimeInterval(remaining)
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let end = self.endDate, Date() >= end else { return }
            self.cancel()
            self.onFinish?()
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
