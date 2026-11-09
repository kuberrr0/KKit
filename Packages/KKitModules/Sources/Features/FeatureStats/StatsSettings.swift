import KKitCore

/// A metric that can have its own menu bar item.
enum StatsMetric: String, Codable, Sendable, CaseIterable, Identifiable {
    case cpu, memory, network, disk, battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: String(localized: "CPU")
        case .memory: String(localized: "Memory")
        case .network: String(localized: "Network")
        case .disk: String(localized: "Disk")
        case .battery: String(localized: "Battery")
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        }
    }
}

enum StatsSettings {
    /// Seconds between samples while something is showing stats.
    static let sampleSeconds = SettingKey("sampleSeconds", default: 2)
    /// Metrics with their own menu bar item.
    static let menuBarMetrics = SettingKey("menuBarMetrics", default: [StatsMetric]())
    /// The stats strip in the KKit menu.
    static let showInMenu = SettingKey("showInMenu", default: true)
    /// Battery alert threshold in percent; 0 = off.
    static let batteryAlert = SettingKey("batteryAlert", default: 15)
    static let memoryPressureAlert = SettingKey("memoryPressureAlert", default: true)
    /// Free-space alert threshold in GB; 0 = off.
    static let diskAlertGB = SettingKey("diskAlertGB", default: 10)
}
