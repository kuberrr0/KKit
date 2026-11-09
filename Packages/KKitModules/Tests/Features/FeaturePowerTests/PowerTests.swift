import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeaturePower

@MainActor
struct AwakeRulesTests {
    private let conditions = AwakeConditions(
        isOnAC: true,
        batteryLevel: 0.5,
        hasExternalDisplay: true,
        runningBundleIDs: ["com.apple.Keynote"]
    )

    @Test func rulesGiveReasons() {
        let rules = AwakeRules(onPowerAdapter: true, withExternalDisplay: true, whileApps: ["com.apple.Keynote", "x.y"], batteryCutoff: 0)
        #expect(rules.reasons(for: conditions) == [.powerAdapter, .externalDisplay, .app("com.apple.Keynote")])
    }

    @Test func noRulesNoReasons() {
        let rules = AwakeRules(onPowerAdapter: false, withExternalDisplay: false, whileApps: [], batteryCutoff: 0)
        #expect(rules.reasons(for: conditions).isEmpty)
    }

    @Test func batteryCutoffOnlyAppliesOnBattery() {
        let rules = AwakeRules(onPowerAdapter: false, withExternalDisplay: true, whileApps: [], batteryCutoff: 60)
        var onBattery = conditions
        onBattery.isOnAC = false
        #expect(rules.isBelowCutoff(onBattery))
        #expect(rules.reasons(for: onBattery).isEmpty)
        #expect(!rules.isBelowCutoff(conditions))
        #expect(rules.reasons(for: conditions) == [.externalDisplay])
    }
}

struct ClockTimeParserTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: hour, minute: minute))!
    }

    @Test func parsesTwentyFourHourTimes() {
        let next = ClockTimeParser.nextDate(from: "17:30", after: date(9, 0), calendar: calendar)
        #expect(next == date(17, 30))
    }

    @Test func parsesTwelveHourTimes() {
        #expect(ClockTimeParser.nextDate(from: "5pm", after: date(9, 0), calendar: calendar) == date(17, 0))
        #expect(ClockTimeParser.nextDate(from: "12am", after: date(9, 0), calendar: calendar) == date(0, 0).addingTimeInterval(86400))
        #expect(ClockTimeParser.nextDate(from: "5:15 pm", after: date(9, 0), calendar: calendar) == date(17, 15))
    }

    @Test func rollsToTomorrow() {
        let next = ClockTimeParser.nextDate(from: "8:00", after: date(9, 0), calendar: calendar)
        #expect(next == date(8, 0).addingTimeInterval(86400))
    }

    @Test func rejectsNonsense() {
        #expect(ClockTimeParser.nextDate(from: "25:00", after: date(9, 0), calendar: calendar) == nil)
        #expect(ClockTimeParser.nextDate(from: "13pm", after: date(9, 0), calendar: calendar) == nil)
        #expect(ClockTimeParser.nextDate(from: "soon", after: date(9, 0), calendar: calendar) == nil)
    }
}

@MainActor
struct PowerControllerTests {
    @Test func holdsOneAssertionWhileAwake() {
        let env = TestEnvironment()
        let controller = PowerController(power: env.power, settings: FeatureSettings(featureID: "power", store: env.settings))

        controller.keepAwake(for: nil)
        #expect(controller.isAwake)
        #expect(env.power.heldAssertions.map(\.kind) == [.display])

        controller.allowSleep()
        #expect(!controller.isAwake)
        #expect(env.power.heldAssertions.isEmpty)
    }

    @Test func switchesAssertionKindWithTheDisplaySetting() {
        let env = TestEnvironment()
        let settings = FeatureSettings(featureID: "power", store: env.settings)
        let controller = PowerController(power: env.power, settings: settings)
        controller.keepAwake(for: 600)

        settings[PowerSettings.keepDisplayAwake] = false
        controller.reevaluate()
        #expect(env.power.heldAssertions.map(\.kind) == [.system])
    }

    @Test func timedSessionsExpire() {
        let env = TestEnvironment()
        var now = Date(timeIntervalSince1970: 1_000_000)
        let controller = PowerController(power: env.power, settings: FeatureSettings(featureID: "power", store: env.settings), now: { now })

        controller.keepAwake(for: 60)
        #expect(controller.statusText(at: now) != nil)
        now = now.addingTimeInterval(61)
        controller.checkExpiry()
        #expect(!controller.isAwake)
        #expect(env.power.heldAssertions.isEmpty)
    }

    @Test func rulesKeepTheMacAwake() {
        let env = TestEnvironment()
        let settings = FeatureSettings(featureID: "power", store: env.settings)
        settings[PowerSettings.awakeOnPowerAdapter] = true
        let controller = PowerController(power: env.power, settings: settings)

        controller.update(conditions: AwakeConditions(isOnAC: true, batteryLevel: 1, hasExternalDisplay: false, runningBundleIDs: []))
        #expect(controller.ruleReasons == [.powerAdapter])
        #expect(controller.statusText(at: Date()) == "Auto")
        #expect(env.power.heldAssertions.count == 1)

        controller.update(conditions: AwakeConditions(isOnAC: false, batteryLevel: 1, hasExternalDisplay: false, runningBundleIDs: []))
        #expect(!controller.isAwake)
        #expect(env.power.heldAssertions.isEmpty)
    }

    @Test func batteryCutoffEndsASession() {
        let env = TestEnvironment()
        let settings = FeatureSettings(featureID: "power", store: env.settings)
        settings[PowerSettings.batteryCutoff] = 20
        let controller = PowerController(power: env.power, settings: settings)
        controller.keepAwake(for: nil)

        controller.update(conditions: AwakeConditions(isOnAC: false, batteryLevel: 0.1, hasExternalDisplay: false, runningBundleIDs: []))
        #expect(!controller.isAwake)
        #expect(controller.stoppedForBattery)
    }

    @Test func featurePresentsTheIslandIndicator() async throws {
        let env = TestEnvironment()
        let feature = PowerFeature(context: env.makeContext(for: "power"))
        try await feature.start()
        feature.controller.keepAwake(for: nil)
        await env.settle()
        #expect(env.island.activityIDs == ["awake"])

        feature.controller.allowSleep()
        await env.settle()
        #expect(env.island.activityIDs.isEmpty)
        await feature.stop()
    }
}
