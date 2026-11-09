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
        #expect(state.check(power: low, thresholdPercent: 15) == .batteryLow(percent: 14))
        #expect(state.check(power: low, thresholdPercent: 15) == nil)

        // Hovering just above the threshold doesn't re-arm…
        let hovering = PowerSourceInfo(hasBattery: true, isOnAC: false, batteryLevel: 0.17)
        #expect(state.check(power: hovering, thresholdPercent: 15) == nil)
        #expect(state.check(power: low, thresholdPercent: 15) == nil)

        // …plugging in does.
        let charging = PowerSourceInfo(hasBattery: true, isOnAC: true, batteryLevel: 0.14)
        #expect(state.check(power: charging, thresholdPercent: 15) == nil)
        #expect(state.check(power: low, thresholdPercent: 15) == .batteryLow(percent: 14))
    }

    @Test func batteryAlertOffAtZero() {
        var state = StatsAlertState()
        let low = PowerSourceInfo(hasBattery: true, isOnAC: false, batteryLevel: 0.05)
        #expect(state.check(power: low, thresholdPercent: 0) == nil)
    }

    @Test func memoryPressureAlert() {
        var state = StatsAlertState()
        #expect(state.check(pressure: .normal, enabled: true) == nil)
        #expect(state.check(pressure: .warning, enabled: true) == .memoryPressure(.warning))
        #expect(state.check(pressure: .critical, enabled: true) == nil)
        #expect(state.check(pressure: .normal, enabled: true) == nil)
        #expect(state.check(pressure: .critical, enabled: true) == .memoryPressure(.critical))
        #expect(state.check(pressure: .critical, enabled: false) == nil)
    }

    @Test func diskAlert() {
        var state = StatsAlertState()
        let low = DiskSample(name: "Macintosh HD", totalBytes: 500_000_000_000, availableBytes: 8_000_000_000)
        #expect(state.check(disk: low, thresholdGB: 10) == .diskLow(availableBytes: 8_000_000_000))
        #expect(state.check(disk: low, thresholdGB: 10) == nil)
        let fine = DiskSample(name: "Macintosh HD", totalBytes: 500_000_000_000, availableBytes: 50_000_000_000)
        #expect(state.check(disk: fine, thresholdGB: 10) == nil)
        #expect(state.check(disk: low, thresholdGB: 10) != nil)
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
