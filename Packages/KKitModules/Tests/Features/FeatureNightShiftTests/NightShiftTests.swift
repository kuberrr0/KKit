import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureNightShift

struct NightShiftColorTests {
    @Test func zeroIntensityIsNeutral() {
        let adjustment = NightShiftColor.adjustment(mode: .warm, intensity: 0, extraDim: 0)
        #expect(abs(adjustment.red - 1) < 0.01)
        #expect(abs(adjustment.green - 1) < 0.02)
        #expect(abs(adjustment.blue - 1) < 0.02)
    }

    @Test func warmerCutsBlueMoreThanRed() {
        let half = NightShiftColor.adjustment(mode: .warm, intensity: 0.5, extraDim: 0)
        let full = NightShiftColor.adjustment(mode: .warm, intensity: 1, extraDim: 0)
        let double = NightShiftColor.adjustment(mode: .warm, intensity: 2, extraDim: 0)
        #expect(half.blue > full.blue)
        #expect(full.blue > double.blue)
        #expect(full.red >= full.green && full.green >= full.blue)
    }

    @Test func kelvinMapping() {
        #expect(NightShiftColor.kelvin(forIntensity: 0) == 6500)
        #expect(abs(NightShiftColor.kelvin(forIntensity: 2) - 1200) < 0.001)
        let atOne = NightShiftColor.kelvin(forIntensity: 1)
        #expect(atOne > 2500 && atOne < 3000)
    }

    @Test func darkroomIsRedOnly() {
        let adjustment = NightShiftColor.adjustment(mode: .darkroom, intensity: 1, extraDim: 0)
        #expect(adjustment.red == 1)
        #expect(adjustment.green == 0)
        #expect(adjustment.blue == 0)
    }

    @Test func extraDimScalesEverything() {
        let adjustment = NightShiftColor.adjustment(mode: .warm, intensity: 0, extraDim: 0.5)
        #expect(abs(adjustment.red - 0.5) < 0.01)
        // Capped at 0.8 dim.
        let capped = NightShiftColor.adjustment(mode: .darkroom, intensity: 0, extraDim: 1)
        #expect(abs(capped.red - 0.2) < 0.001)
    }

    @Test func blendFromIdentity() {
        let target = ColorAdjustment(red: 1, green: 0.5, blue: 0)
        #expect(NightShiftColor.blend(target, progress: 0) == .identity)
        #expect(NightShiftColor.blend(target, progress: 1) == target)
        #expect(NightShiftColor.blend(target, progress: 0.5) == ColorAdjustment(red: 1, green: 0.75, blue: 0.5))
    }
}

struct NightShiftScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func wrapsPastMidnight() {
        #expect(NightShiftSchedule.isWithin(minutes: 23 * 60, start: 22 * 60, end: 7 * 60))
        #expect(NightShiftSchedule.isWithin(minutes: 6 * 60, start: 22 * 60, end: 7 * 60))
        #expect(!NightShiftSchedule.isWithin(minutes: 12 * 60, start: 22 * 60, end: 7 * 60))
        #expect(NightShiftSchedule.isWithin(minutes: 14 * 60, start: 13 * 60, end: 15 * 60))
        #expect(!NightShiftSchedule.isWithin(minutes: 14 * 60, start: 14 * 60, end: 14 * 60))
    }

    @Test func customSchedule() {
        let schedule = NightShiftSchedule(kind: .custom, startMinutes: 22 * 60, endMinutes: 7 * 60, coordinate: nil)
        #expect(schedule.isActive(at: date(6, 1, 23), calendar: calendar) == true)
        #expect(schedule.isActive(at: date(6, 1, 12), calendar: calendar) == false)
        #expect(schedule.nextChange(after: date(6, 1, 12), calendar: calendar) == date(6, 1, 22))
        #expect(schedule.nextChange(after: date(6, 1, 23), calendar: calendar) == date(6, 2, 7))
    }

    @Test func manualScheduleHasNoOpinion() {
        let schedule = NightShiftSchedule(kind: .manual, startMinutes: 0, endMinutes: 0, coordinate: nil)
        #expect(schedule.isActive(at: date(6, 1, 23), calendar: calendar) == nil)
        #expect(schedule.nextChange(after: date(6, 1, 23), calendar: calendar) == nil)
    }

    @Test func sunsetScheduleInLondon() {
        let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
        let schedule = NightShiftSchedule(kind: .sunset, startMinutes: 0, endMinutes: 0, coordinate: london)
        #expect(schedule.isActive(at: date(6, 21, 13), calendar: calendar) == false)
        #expect(schedule.isActive(at: date(6, 21, 23), calendar: calendar) == true)
        #expect(schedule.isActive(at: date(12, 21, 17), calendar: calendar) == true)
    }
}

struct SolarCalculatorTests {
    @Test func londonMidsummer() throws {
        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(identifier: "Europe/London")!
        calendar.timeZone = zone
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let sun = try #require(SolarCalculator.sunTimes(on: day, latitude: 51.5074, longitude: -0.1278, timeZone: zone))
        // Published times: sunrise ≈ 04:43, sunset ≈ 21:21 BST.
        let rise = calendar.dateComponents([.hour, .minute], from: sun.sunrise)
        let set = calendar.dateComponents([.hour, .minute], from: sun.sunset)
        let riseMinutes = rise.hour! * 60 + rise.minute!
        let setMinutes = set.hour! * 60 + set.minute!
        #expect(abs(riseMinutes - (4 * 60 + 43)) <= 5)
        #expect(abs(setMinutes - (21 * 60 + 21)) <= 5)
    }

    @Test func polarNight() {
        let zone = TimeZone(identifier: "Europe/Oslo")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = calendar.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 12))!
        // Longyearbyen, Svalbard.
        #expect(SolarCalculator.sunTimes(on: day, latitude: 78.22, longitude: 15.65, timeZone: zone) == nil)
    }
}

@MainActor
struct NightShiftControllerTests {
    private func makeController(_ env: TestEnvironment) -> (NightShiftController, FeatureSettings) {
        let settings = FeatureSettings(featureID: "nightShift", store: env.settings)
        settings[NightShiftSettings.transitionSeconds] = 0
        return (NightShiftController(display: env.display, settings: settings), settings)
    }

    @Test func turningOnTintsEveryDisplay() throws {
        let env = TestEnvironment()
        let (controller, _) = makeController(env)
        controller.setOn(true)
        #expect(controller.isActive)
        let id = try #require(env.display.displays.first?.id)
        let adjustment = try #require(env.display.adjustments[id])
        #expect(adjustment.blue < 1)

        controller.setOn(false)
        #expect(env.display.adjustments[id] == nil)
    }

    @Test func intensityTurnsItOn() {
        let env = TestEnvironment()
        let (controller, settings) = makeController(env)
        controller.setIntensity(1.5)
        #expect(controller.isActive)
        #expect(settings[NightShiftSettings.intensity] == 1.5)
        controller.setIntensity(5)
        #expect(settings[NightShiftSettings.intensity] == 2)
    }

    @Test func excludedAppsLiftTheTint() {
        let env = TestEnvironment()
        let (controller, settings) = makeController(env)
        settings[NightShiftSettings.disabledApps] = ["com.adobe.Photoshop"]
        controller.setOn(true)
        controller.frontmostAppChanged("com.adobe.Photoshop")
        #expect(controller.isOn)
        #expect(!controller.isActive)
        controller.frontmostAppChanged("com.apple.Safari")
        #expect(controller.isActive)
    }

    @Test func pauseAndShutdown() {
        let env = TestEnvironment()
        let (controller, _) = makeController(env)
        controller.setOn(true)
        controller.pause(for: 3600)
        #expect(controller.isPaused)
        #expect(!controller.isActive)
        controller.resume()
        #expect(controller.isActive)
        controller.shutdown()
        #expect(env.display.adjustments.isEmpty)
    }
}
