import Foundation
import KKitServicesAPI

/// Decides when to alert. Each alert fires once, then re-arms when the condition clears
/// (with a little hysteresis so a value hovering at the threshold doesn't repeat).
struct StatsAlertState: Equatable, Sendable {
    var batteryAlerted = false
    var memoryAlerted = false
    var diskAlerted = false

    enum Alert: Equatable, Sendable {
        case batteryLow(percent: Int)
        case memoryPressure(MemoryPressure)
        case diskLow(availableBytes: Int64)
    }

    /// `thresholdPercent` 0 = off.
    mutating func check(power: PowerSourceInfo, thresholdPercent: Int) -> Alert? {
        guard thresholdPercent > 0, power.hasBattery, let level = power.batteryLevel else { return nil }
        let percent = Int((level * 100).rounded())
        if power.isOnAC || percent > thresholdPercent + 5 {
            batteryAlerted = false
            return nil
        }
        guard percent <= thresholdPercent, !batteryAlerted else { return nil }
        batteryAlerted = true
        return .batteryLow(percent: percent)
    }

    mutating func check(pressure: MemoryPressure, enabled: Bool) -> Alert? {
        guard enabled else { return nil }
        if pressure == .normal {
            memoryAlerted = false
            return nil
        }
        guard !memoryAlerted else { return nil }
        memoryAlerted = true
        return .memoryPressure(pressure)
    }

    /// `thresholdGB` 0 = off.
    mutating func check(disk: DiskSample, thresholdGB: Int) -> Alert? {
        guard thresholdGB > 0, disk.totalBytes > 0 else { return nil }
        let threshold = Int64(thresholdGB) * 1_000_000_000
        if disk.availableBytes > threshold + 2_000_000_000 {
            diskAlerted = false
            return nil
        }
        guard disk.availableBytes <= threshold, !diskAlerted else { return nil }
        diskAlerted = true
        return .diskLow(availableBytes: disk.availableBytes)
    }
}
