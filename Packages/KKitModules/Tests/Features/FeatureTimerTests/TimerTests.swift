import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureTimer

struct TimerInputParserTests {
    @Test func parsesDurationsAndLabels() {
        #expect(TimerInputParser.parse("10m tea") == .init(seconds: 600, label: "tea"))
        #expect(TimerInputParser.parse("1h30m laundry day") == .init(seconds: 5400, label: "laundry day"))
        #expect(TimerInputParser.parse("90s") == .init(seconds: 90, label: nil))
        #expect(TimerInputParser.parse("25") == .init(seconds: 1500, label: nil))
        #expect(TimerInputParser.parse("25 min focus") == .init(seconds: 1500, label: "focus"))
        #expect(TimerInputParser.parse("1:30") == .init(seconds: 90, label: nil))
        #expect(TimerInputParser.parse("2hours") == .init(seconds: 7200, label: nil))
        #expect(TimerInputParser.parse("1h 15m") == .init(seconds: 4500, label: nil))
    }

    @Test func rejectsTextWithoutADuration() {
        #expect(TimerInputParser.parse("tea") == nil)
        #expect(TimerInputParser.parse("") == nil)
        #expect(TimerInputParser.parse("0m") == nil)
    }
}

struct CountdownTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func pauseAndResumeKeepTheRemainingTime() {
        var countdown = Countdown(duration: 300, start: start)
        #expect(countdown.remaining(at: start.addingTimeInterval(100)) == 200)
        countdown.pause(at: start.addingTimeInterval(100))
        #expect(!countdown.isRunning)
        #expect(countdown.remaining(at: start.addingTimeInterval(1000)) == 200)
        countdown.resume(at: start.addingTimeInterval(1000))
        #expect(countdown.endDate == start.addingTimeInterval(1200))
        #expect(abs(countdown.progress(at: start.addingTimeInterval(1100)) - 2.0 / 3.0) < 1e-9)
    }

    @Test func addingTime() {
        var countdown = Countdown(duration: 60, start: start)
        countdown.add(60, at: start.addingTimeInterval(30))
        #expect(countdown.remaining(at: start.addingTimeInterval(30)) == 90)
        #expect(countdown.duration == 120)
    }
}

struct PomodoroTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let lengths = PomodoroLengths(work: 25 * 60, shortBreak: 5 * 60, longBreak: 15 * 60, longBreakEvery: 2)

    @Test func cyclesWithALongBreak() {
        var pomodoro = Pomodoro.start(lengths, at: start)
        var phases: [PomodoroPhase] = [pomodoro.phase]
        for _ in 0..<4 {
            pomodoro.advance(lengths, autoStart: true, at: start)
            phases.append(pomodoro.phase)
        }
        #expect(phases == [.work, .shortBreak, .work, .longBreak, .work])
        #expect(pomodoro.completedWork == 2)
    }

    @Test func waitsWhenNotAutoStarting() {
        var pomodoro = Pomodoro.start(lengths, at: start)
        pomodoro.advance(lengths, autoStart: false, at: start)
        #expect(!pomodoro.isRunning)
        #expect(pomodoro.remaining(at: start.addingTimeInterval(9999)) == 5 * 60)
    }
}

struct StopwatchTests {
    @Test func lapsAndPauses() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var stopwatch = Stopwatch()
        #expect(!stopwatch.isActive)
        stopwatch.start(at: start)
        stopwatch.lap(at: start.addingTimeInterval(10))
        stopwatch.lap(at: start.addingTimeInterval(25))
        stopwatch.pause(at: start.addingTimeInterval(30))
        #expect(stopwatch.elapsed(at: start.addingTimeInterval(100)) == 30)
        #expect(stopwatch.lapDurations == [10, 15])
        stopwatch.start(at: start.addingTimeInterval(100))
        #expect(stopwatch.elapsed(at: start.addingTimeInterval(105)) == 35)
        stopwatch.reset()
        #expect(stopwatch == Stopwatch())
    }
}

@MainActor
struct TimerModelTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func collectsFinishedCountdowns() {
        let model = TimerModel()
        var saved = 0
        model.onChange = { _ in saved += 1 }
        model.startCountdown(60, label: "tea", at: start)
        model.startCountdown(300, at: start)
        #expect(model.nextDeadline == start.addingTimeInterval(60))

        let events = model.collectFinished(at: start.addingTimeInterval(61), lengths: .standard, autoStart: true)
        #expect(events.count == 1)
        if case .countdownFinished(let countdown) = events.first {
            #expect(countdown.label == "tea")
        } else {
            Issue.record("expected a finished countdown")
        }
        #expect(model.countdowns.count == 1)
        #expect(saved == 3)
        #expect(model.collectFinished(at: start.addingTimeInterval(62), lengths: .standard, autoStart: true).isEmpty)
    }

    @Test func advancesThePomodoro() {
        let model = TimerModel()
        model.startPomodoro(.standard, at: start)
        let events = model.collectFinished(at: start.addingTimeInterval(25 * 60), lengths: .standard, autoStart: true)
        #expect(events == [.pomodoroPhaseEnded(finished: .work, next: .shortBreak)])
        #expect(model.pomodoro?.phase == .shortBreak)
        #expect(model.nextDeadline == start.addingTimeInterval(30 * 60))
    }

    @Test func featureAnnouncesAndShowsActivities() async throws {
        let env = TestEnvironment()
        let context = env.makeContext(for: "timer")
        context.settings[TimerSettings.sound] = ""
        context.settings[TimerSettings.notify] = true
        let feature = TimerFeature(context: context)
        try await feature.start()

        feature.controller.start(0.05, label: "eggs")
        feature.controller.toggleStopwatch()
        await env.settle()
        #expect(env.island.activityIDs.contains("stopwatch"))
        let hasCountdown = env.island.activityIDs.contains { $0.hasPrefix("countdown.") }
        #expect(hasCountdown)

        // The countdown clamps to at least 1 s; wait for it.
        try await Task.sleep(for: .milliseconds(1300))
        await env.settle()
        #expect(env.island.huds.last?.title == "eggs is done")
        #expect(env.notifications.delivered.count == 1)
        let stillHasCountdown = env.island.activityIDs.contains { $0.hasPrefix("countdown.") }
        #expect(!stillHasCountdown)

        let saved = try env.storage.readJSON(TimerSnapshot.self, named: TimerFeature.stateFile, for: "timer")
        #expect(saved?.stopwatch.isRunning == true)
        await feature.stop()
        #expect(env.island.activityIDs.isEmpty)
    }
}
