import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureStats

struct StatsAlertTests {
    @Test func batteryAlertFiresOnceAndRearms() {
        var state = StatsAlertState()
        let low = PowerSourceInfo(hasBattery: true, isOnAC: false, batteryLevel: 0.14)
        let result1 = state.check(power: low, thresholdPercent: 15)
        #expect(result1 == .batteryLow(percent: 14))
        let result2 = state.check(power: low, thresholdPercent: 15)
        #expect(result2 == nil)

        // Hovering just above the threshold doesn't re-arm…
        let hovering = PowerSourceInfo(hasBattery: true, isOnAC: false, batteryLevel: 0.17)
        let result3 = state.check(power: hovering, thresholdPercent: 15)
        #expect(result3 == nil)
        let result4 = state.check(power: low, thresholdPercent: 15)
        #expect(result4 == nil)

        // …plugging in does.
        let charging = PowerSourceInfo(hasBattery: true, isOnAC: true, batteryLevel: 0.14)
        let result5 = state.check(power: charging, thresholdPercent: 15)
        #expect(result5 == nil)
        let result6 = state.check(power: low, thresholdPercent: 15)
        #expect(result6 == .batteryLow(percent: 14))
    }

    @Test func batteryAlertOffAtZero() {
        var state = StatsAlertState()
        let low = PowerSourceInfo(hasBattery: true, isOnAC: false, batteryLevel: 0.05)
        let result7 = state.check(power: low, thresholdPercent: 0)
        #expect(result7 == nil)
    }

    @Test func memoryPressureAlert() {
        var state = StatsAlertState()
        let result8 = state.check(pressure: .normal, enabled: true)
        #expect(result8 == nil)
        let result9 = state.check(pressure: .warning, enabled: true)
        #expect(result9 == .memoryPressure(.warning))
        let result10 = state.check(pressure: .critical, enabled: true)
        #expect(result10 == nil)
        let result11 = state.check(pressure: .normal, enabled: true)
        #expect(result11 == nil)
        let result12 = state.check(pressure: .critical, enabled: true)
        #expect(result12 == .memoryPressure(.critical))
        let result13 = state.check(pressure: .critical, enabled: false)
        #expect(result13 == nil)
    }

    @Test func diskAlert() {
        var state = StatsAlertState()
        let low = DiskSample(name: "Macintosh HD", totalBytes: 500_000_000_000, availableBytes: 8_000_000_000)
        let result14 = state.check(disk: low, thresholdGB: 10)
        #expect(result14 == .diskLow(availableBytes: 8_000_000_000))
        let result15 = state.check(disk: low, thresholdGB: 10)
        #expect(result15 == nil)
        let fine = DiskSample(name: "Macintosh HD", totalBytes: 500_000_000_000, availableBytes: 50_000_000_000)
        let result16 = state.check(disk: fine, thresholdGB: 10)
        #expect(result16 == nil)
        let result17 = state.check(disk: low, thresholdGB: 10)
        #expect(result17 != nil)
    }
}

@MainActor
struct StatsModelTests {
    @Test func historyIsCapped() {
        var history: [Double] = []
        for value in 0..<100 {
            history = StatsModel.append(Double(value), to: history)
        }
        #expect(history.count == StatsModel.historyLength)
        #expect(history.last == 99)
    }

    @Test func normalizesAgainstThePeak() {
        #expect(StatsModel.normalized([1, 2, 4]) == [0.25, 0.5, 1])
        #expect(StatsModel.normalized([0, 0]) == [0, 0])
    }

    @Test func samplesOnlyWhileSomethingWatches() async {
        let env = TestEnvironment()
        let model = StatsModel(systemInfo: env.systemInfo, power: env.power, settings: FeatureSettings(featureID: "stats", store: env.settings))
        #expect(!model.isSampling)

        model.acquire()
        await env.settle()
        #expect(model.isSampling)
        env.systemInfo.send(SystemSample(cpu: CPUSample(total: 0.42)))
        await env.settle()
        #expect(model.latest?.cpu.total == 0.42)

        model.release()
        await env.settle()
        #expect(!model.isSampling)
    }
}
