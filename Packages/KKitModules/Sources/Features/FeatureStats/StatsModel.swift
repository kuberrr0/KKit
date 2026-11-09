import Foundation
import KKitCore
import KKitServicesAPI
import Observation

/// Live system stats for the views. Samples only while something that shows stats is
/// visible (menu bar items, the popover strip, the Island page, a details popover).
@MainActor
@Observable
final class StatsModel {
    static let historyLength = 40

    private(set) var latest: SystemSample?
    private(set) var cpuHistory: [Double] = []
    private(set) var networkInHistory: [Double] = []
    private(set) var networkOutHistory: [Double] = []
    private(set) var power: PowerSourceInfo
    private(set) var batteryHealth: BatteryHealth?

    private let systemInfo: any SystemInfoService
    private let powerService: any PowerService
    private let settings: FeatureSettings
    @ObservationIgnored private var demand = 0
    @ObservationIgnored private var processDemand = 0
    @ObservationIgnored private var persistentDemand = false
    @ObservationIgnored private var sampling: Task<Void, Never>?
    @ObservationIgnored private var samplingConfiguration: (seconds: Int, processes: Bool)?

    init(systemInfo: any SystemInfoService, power: any PowerService, settings: FeatureSettings) {
        self.systemInfo = systemInfo
        self.powerService = power
        self.settings = settings
        self.power = power.powerSource
    }

    // MARK: Demand

    /// A view that shows stats calls this on appear…
    func acquire(processes: Bool = false) {
        demand += 1
        if processes { processDemand += 1 }
        updateSampling()
        if processes {
            Task { [weak self] in
                guard let self else { return }
                let health = await self.powerService.batteryHealth()
                self.batteryHealth = health
            }
        }
    }

    /// …and this on disappear.
    func release(processes: Bool = false) {
        demand = max(0, demand - 1)
        if processes { processDemand = max(0, processDemand - 1) }
        updateSampling()
    }

    /// Menu bar items are always visible, so they keep sampling on.
    func setPersistentDemand(_ on: Bool) {
        persistentDemand = on
        updateSampling()
    }

    var isSampling: Bool { sampling != nil }

    func updateSampling() {
        let wanted = demand > 0 || persistentDemand
        guard wanted else {
            sampling?.cancel()
            sampling = nil
            samplingConfiguration = nil
            return
        }
        let seconds = max(1, settings[StatsSettings.sampleSeconds])
        let processes = processDemand > 0
        if let current = samplingConfiguration, current.seconds == seconds, current.processes == processes {
            return
        }
        samplingConfiguration = (seconds, processes)
        sampling?.cancel()
        let stream = systemInfo.samples(every: .seconds(seconds), includeProcesses: processes)
        sampling = Task { [weak self] in
            for await sample in stream {
                self?.record(sample)
            }
        }
    }

    func stop() {
        sampling?.cancel()
        sampling = nil
        samplingConfiguration = nil
        demand = 0
        processDemand = 0
        persistentDemand = false
    }

    // MARK: Updates

    func record(_ sample: SystemSample) {
        latest = sample
        cpuHistory = Self.append(sample.cpu.total, to: cpuHistory)
        networkInHistory = Self.append(sample.network.bytesInPerSecond, to: networkInHistory)
        networkOutHistory = Self.append(sample.network.bytesOutPerSecond, to: networkOutHistory)
    }

    func record(_ power: PowerSourceInfo) {
        self.power = power
    }

    static func append(_ value: Double, to history: [Double]) -> [Double] {
        var history = history
        history.append(value)
        if history.count > historyLength {
            history.removeFirst(history.count - historyLength)
        }
        return history
    }

    /// Network history scaled to 0…1 against its own peak, for sparklines.
    static func normalized(_ values: [Double]) -> [Double] {
        guard let peak = values.max(), peak > 0 else { return values.map { _ in 0 } }
        return values.map { $0 / peak }
    }
}
