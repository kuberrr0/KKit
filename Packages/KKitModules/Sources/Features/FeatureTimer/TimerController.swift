import Foundation
import KKitCore

/// The model plus the clock and the settings: what the views and commands call.
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

    var defaultSeconds: TimeInterval { max(1, settings[TimerSettings.defaultMinutes]) * 60 }

    func start(_ seconds: TimeInterval? = nil, label: String? = nil) {
        model.startCountdown(seconds ?? defaultSeconds, label: label, at: now())
    }

    func togglePause(_ id: Countdown.ID) { model.togglePause(id, at: now()) }
    func addMinute(to id: Countdown.ID) { model.add(60, to: id, at: now()) }
    func cancel(_ id: Countdown.ID) { model.cancel(id) }
    func cancelAll() { model.cancelAllCountdowns() }

    func toggleStopwatch() { model.toggleStopwatch(at: now()) }
    func lap() { model.lap(at: now()) }
    func resetStopwatch() { model.resetStopwatch() }

    func collectFinished() -> [TimerEvent] {
        model.collectFinished(at: now())
    }

    var currentDate: Date { now() }
}
