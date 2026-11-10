import Foundation
import Observation

/// Countdowns and the stopwatch. Time is passed in, so tests can
/// drive it; the feature owns the clock and the alerts.
@MainActor
@Observable
final class TimerModel {
    private(set) var snapshot: TimerSnapshot

    /// Called after every change, to save.
    @ObservationIgnored var onChange: (@MainActor (TimerSnapshot) -> Void)?

    init(snapshot: TimerSnapshot = TimerSnapshot()) {
        self.snapshot = snapshot
    }

    var countdowns: [Countdown] { snapshot.countdowns }
    var stopwatch: Stopwatch { snapshot.stopwatch }

    /// The next moment something ends.
    var nextDeadline: Date? {
        snapshot.countdowns.compactMap(\.endDate).min()
    }

    // MARK: Countdowns

    @discardableResult
    func startCountdown(_ seconds: TimeInterval, label: String? = nil, at date: Date) -> Countdown {
        let countdown = Countdown(duration: max(1, seconds), label: label, start: date)
        mutate { $0.countdowns.append(countdown) }
        return countdown
    }

    func togglePause(_ id: Countdown.ID, at date: Date) {
        mutateCountdown(id) { countdown in
            if countdown.isRunning {
                countdown.pause(at: date)
            } else {
                countdown.resume(at: date)
            }
        }
    }

    func add(_ seconds: TimeInterval, to id: Countdown.ID, at date: Date) {
        mutateCountdown(id) { $0.add(seconds, at: date) }
    }

    func cancel(_ id: Countdown.ID) {
        mutate { $0.countdowns.removeAll { $0.id == id } }
    }

    func cancelAllCountdowns() {
        mutate { $0.countdowns = [] }
    }

    // MARK: Stopwatch

    func toggleStopwatch(at date: Date) {
        mutate { snapshot in
            if snapshot.stopwatch.isRunning {
                snapshot.stopwatch.pause(at: date)
            } else {
                snapshot.stopwatch.start(at: date)
            }
        }
    }

    func lap(at date: Date) {
        mutate { $0.stopwatch.lap(at: date) }
    }

    func resetStopwatch() {
        mutate { $0.stopwatch.reset() }
    }

    // MARK: Ending

    /// Removes finished countdowns. Returns what ended, to announce.
    func collectFinished(at date: Date) -> [TimerEvent] {
        let finished = snapshot.countdowns.filter { $0.isFinished(at: date) }
        guard !finished.isEmpty else { return [] }
        let finishedIDs = Set(finished.map(\.id))
        mutate { $0.countdowns.removeAll { finishedIDs.contains($0.id) } }
        return finished.map(TimerEvent.countdownFinished)
    }

    // MARK: Private

    private func mutateCountdown(_ id: Countdown.ID, _ change: (inout Countdown) -> Void) {
        mutate { snapshot in
            guard let index = snapshot.countdowns.firstIndex(where: { $0.id == id }) else { return }
            change(&snapshot.countdowns[index])
        }
    }

    private func mutate(_ change: (inout TimerSnapshot) -> Void) {
        var copy = snapshot
        change(&copy)
        guard copy != snapshot else { return }
        snapshot = copy
        onChange?(copy)
    }
}

extension TimerModel {
    /// Loads saved state without announcing a change.
    func restore(_ saved: TimerSnapshot) {
        snapshot = saved
    }
}
