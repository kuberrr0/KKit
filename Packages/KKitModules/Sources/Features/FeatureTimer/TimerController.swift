import Foundation
import KKitCore

/// The model plus the clock and the Pomodoro settings: what the views and commands call.
@MainActor
final class TimerController {
    let model: TimerModel
    private let settings: FeatureSettings
    private let now: () -> Date

    init(model: TimerModel, settings: FeatureSettings, now: @escaping () -> Date = { Date() }) {
        self.model = model
        self.settings = settings
        self.now = now
    }

    var lengths: PomodoroLengths {
        PomodoroLengths(
            work: max(1, settings[TimerSettings.workMinutes]) * 60,
            shortBreak: max(1, settings[TimerSettings.shortBreakMinutes]) * 60,
            longBreak: max(1, settings[TimerSettings.longBreakMinutes]) * 60,
            longBreakEvery: max(1, settings[TimerSettings.longBreakEvery])
        )
    }

    var defaultSeconds: TimeInterval { max(1, settings[TimerSettings.defaultMinutes]) * 60 }

    func start(_ seconds: TimeInterval? = nil, label: String? = nil) {
        model.startCountdown(seconds ?? defaultSeconds, label: label, at: now())
    }

    func togglePause(_ id: Countdown.ID) { model.togglePause(id, at: now()) }
    func addMinute(to id: Countdown.ID) { model.add(60, to: id, at: now()) }
    func cancel(_ id: Countdown.ID) { model.cancel(id) }
    func cancelAll() { model.cancelAllCountdowns() }

    func togglePomodoro() {
        if model.pomodoro == nil {
            model.startPomodoro(lengths, at: now())
        } else {
            model.stopPomodoro()
        }
    }

    func togglePausePomodoro() { model.togglePausePomodoro(at: now()) }
    func skipPomodoroPhase() { model.skipPomodoroPhase(lengths, at: now()) }
    func stopPomodoro() { model.stopPomodoro() }

    func toggleStopwatch() { model.toggleStopwatch(at: now()) }
    func lap() { model.lap(at: now()) }
    func resetStopwatch() { model.resetStopwatch() }

    func collectFinished() -> [TimerEvent] {
        model.collectFinished(at: now(), lengths: lengths, autoStart: settings[TimerSettings.autoStartNext])
    }

    var currentDate: Date { now() }
}
