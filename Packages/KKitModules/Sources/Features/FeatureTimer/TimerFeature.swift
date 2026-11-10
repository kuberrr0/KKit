import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI
import os

/// Countdown timers and a stopwatch, in the Island. DESIGN.md §3.16.
@MainActor
public final class TimerFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "timer",
        name: String(localized: "Timer"),
        symbol: "timer",
        summary: String(localized: "Countdowns and a stopwatch, in the Island."),
        category: .productivity,
        optionalPermissions: [.notifications],
        enabledByDefault: true
    )

    static let stateFile = "state.json"

    private let context: FeatureContext
    let model: TimerModel
    let controller: TimerController
    private var deadlineTask: Task<Void, Never>?
    private var tasks: [Task<Void, Never>] = []
    private var activities: [String: any IslandHandle] = [:]
    private var isRunning = false

    public init(context: FeatureContext) {
        self.context = context
        let model = TimerModel()
        self.model = model
        self.controller = TimerController(model: model, settings: context.settings)
    }

    public func start() async throws {
        isRunning = true
        if let saved = try? context.storage.read(TimerSnapshot.self, named: Self.stateFile) {
            model.restore(saved)
        }
        model.onChange = { [weak self] snapshot in
            self?.save(snapshot)
        }
        let showInIsland = context.settings.changes(of: TimerSettings.showInIsland)
        tasks.append(Task { [weak self] in
            for await _ in showInIsland {
                self?.syncIsland()
            }
        })
        // Timers that ended while KKit wasn't running.
        handleDeadline()
        observeModel()
    }

    public func stop() async {
        isRunning = false
        tasks.forEach { $0.cancel() }
        tasks = []
        deadlineTask?.cancel()
        deadlineTask = nil
        model.onChange = nil
        activities.values.forEach { $0.dismiss() }
        activities = [:]
    }

    // MARK: Contributions

    public var commands: [Command] {
        [
            Command(
                id: "timer.start",
                title: String(localized: "Start Timer…"),
                symbol: "timer",
                keywords: ["countdown", "alarm", "minutes"],
                parameter: .duration(default: .seconds(300))
            ) { [weak self] invocation in
                let seconds = invocation.duration.map { Double($0.components.seconds) }
                self?.controller.start(seconds)
            },
            Command(
                id: "timer.startLabeled",
                title: String(localized: "Start Labeled Timer…"),
                subtitle: String(localized: "Like “10m tea” or “1h30m laundry”"),
                symbol: "timer",
                keywords: ["countdown", "alarm"],
                parameter: .text(placeholder: "10m tea")
            ) { [weak self] invocation in
                guard let parsed = invocation.text.flatMap(TimerInputParser.parse) else {
                    throw TimerError.badDuration
                }
                self?.controller.start(parsed.seconds, label: parsed.label)
            },
            Command(
                id: "timer.cancelAll",
                title: String(localized: "Cancel All Timers"),
                symbol: "xmark.circle",
                keywords: ["countdown", "stop"],
                isEnabled: { [weak self] in self?.model.countdowns.isEmpty == false }
            ) { [weak self] _ in
                self?.controller.cancelAll()
            },
            Command(
                id: "timer.stopwatch",
                title: String(localized: "Start or Pause Stopwatch"),
                symbol: "stopwatch",
                keywords: ["stopwatch", "elapsed"],
                state: { [weak self] in self?.model.stopwatch.isRunning == true ? .on : .off }
            ) { [weak self] _ in
                self?.controller.toggleStopwatch()
            },
            Command(
                id: "timer.lap",
                title: String(localized: "Stopwatch Lap"),
                symbol: "flag",
                keywords: ["stopwatch", "split"],
                isEnabled: { [weak self] in self?.model.stopwatch.isActive == true }
            ) { [weak self] _ in
                self?.controller.lap()
            },
            Command(
                id: "timer.resetStopwatch",
                title: String(localized: "Reset Stopwatch"),
                symbol: "arrow.counterclockwise",
                keywords: ["stopwatch"],
                isEnabled: { [weak self] in self?.model.stopwatch.isActive == true }
            ) { [weak self] _ in
                self?.controller.resetStopwatch()
            },
        ]
    }

    public var islandPages: [IslandPage] {
        [IslandPage(id: "timer", title: String(localized: "Timer"), symbol: "timer") { [controller] in
            TimerIslandPage(controller: controller)
        }]
    }

    public var settingsPane: SettingsPane? {
        SettingsPane {
            TimerSettingsView()
        }
    }

    // MARK: Private

    private func observeModel() {
        withObservationTracking {
            _ = model.snapshot
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.observeModel()
            }
        }
        syncIsland()
        scheduleDeadline()
    }

    private func scheduleDeadline() {
        deadlineTask?.cancel()
        guard let deadline = model.nextDeadline else {
            deadlineTask = nil
            return
        }
        let delay = max(0, deadline.timeIntervalSinceNow)
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.handleDeadline()
        }
    }

    private func handleDeadline() {
        let events = controller.collectFinished()
        events.forEach(announce)
        if !events.isEmpty {
            scheduleDeadline()
        }
    }

    private func announce(_ event: TimerEvent) {
        let title: String
        let body: String?
        let symbol: String
        switch event {
        case .countdownFinished(let countdown):
            title = countdown.label.map { String(localized: "\($0) is done") } ?? String(localized: "Timer done")
            body = KKFormat.shortDuration(countdown.duration)
            symbol = "bell.fill"
        }
        context.island.showHUD(IslandHUD(id: "timer.done", symbol: symbol, title: title, detail: body, tint: .accent, duration: 5))
        let sound = context.settings[TimerSettings.sound]
        if !sound.isEmpty {
            NSSound(named: NSSound.Name(sound))?.play()
        }
        if context.settings[TimerSettings.notify] {
            context.notifications.deliver(id: "timer.\(UUID().uuidString)", title: title, body: body)
        }
    }

    private func save(_ snapshot: TimerSnapshot) {
        do {
            try context.storage.write(snapshot, named: Self.stateFile)
        } catch {
            context.log.error("Couldn't save timers: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One Island activity per countdown and one for the stopwatch.
    private func syncIsland() {
        var wanted: [String: IslandActivity] = [:]
        if context.settings[TimerSettings.showInIsland] {
            for countdown in model.countdowns {
                wanted["countdown.\(countdown.id.uuidString)"] = countdownActivity(countdown)
            }
            if model.stopwatch.isActive {
                wanted["stopwatch"] = stopwatchActivity()
            }
        }
        for (id, handle) in activities where wanted[id] == nil || !handle.isActive {
            handle.dismiss()
            activities[id] = nil
        }
        for (id, activity) in wanted {
            if let handle = activities[id] {
                handle.update(activity)
            } else {
                activities[id] = context.island.present(activity)
            }
        }
    }

    private func countdownActivity(_ countdown: Countdown) -> IslandActivity {
        let id = countdown.id
        return IslandActivity(
            id: "countdown.\(id.uuidString)",
            title: countdown.title,
            symbol: "timer",
            priority: .normal,
            compactLeading: AnyView(TimerRing(model: model, kind: .countdown(id))),
            compactTrailing: AnyView(TimerClock(model: model, kind: .countdown(id))),
            expanded: AnyView(CountdownIslandView(controller: controller, id: id))
        )
    }

    private func stopwatchActivity() -> IslandActivity {
        IslandActivity(
            id: "stopwatch",
            title: String(localized: "Stopwatch"),
            symbol: "stopwatch",
            priority: .normal,
            compactLeading: AnyView(Image(systemName: "stopwatch.fill").foregroundStyle(.orange)),
            compactTrailing: AnyView(TimerClock(model: model, kind: .stopwatch)),
            expanded: AnyView(StopwatchIslandView(controller: controller))
        )
    }
}

enum TimerError: LocalizedError {
    case badDuration

    var errorDescription: String? {
        switch self {
        case .badDuration: String(localized: "Type a duration like 10m, 1h30m or 90s, then an optional label.")
        }
    }
}
