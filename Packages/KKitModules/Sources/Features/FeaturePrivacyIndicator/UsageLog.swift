import Foundation
import KKitServicesAPI

enum PrivacyDevice: String, Codable, Sendable, CaseIterable {
    case microphone
    case camera

    var symbol: String {
        switch self {
        case .microphone: "mic.fill"
        case .camera: "video.fill"
        }
    }

    var title: String {
        switch self {
        case .microphone: String(localized: "Microphone")
        case .camera: String(localized: "Camera")
        }
    }
}

/// One period of a device being in use.
struct UsageLogEntry: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    var device: PrivacyDevice
    /// App names seen using the device during the period (mic only; camera use isn't attributed).
    var apps: [String]
    var start: Date
    var end: Date?

    var duration: TimeInterval? { end.map { $0.timeIntervalSince(start) } }
}

/// The 7-day log of mic and camera use. Pure: `record` turns usage changes into entries.
struct UsageLog: Codable, Sendable, Equatable {
    static let retention: TimeInterval = 7 * 24 * 3600

    /// Oldest first.
    private(set) var entries: [UsageLogEntry] = []

    init(entries: [UsageLogEntry] = []) {
        self.entries = entries
    }

    /// Applies the current usage: opens an entry when a device starts being used,
    /// adds new app names, and closes it when the device stops.
    /// Returns `true` when an entry was closed (a good moment to save).
    @discardableResult
    mutating func record(_ usage: DeviceUsage, at date: Date) -> Bool {
        var closed = false
        for device in PrivacyDevice.allCases {
            let inUse = device == .microphone ? usage.micInUse : usage.cameraInUse
            let openIndex = entries.lastIndex { $0.device == device && $0.end == nil }
            switch (inUse, openIndex) {
            case (true, nil):
                entries.append(UsageLogEntry(device: device, apps: apps(for: device, usage), start: date))
            case (true, let index?):
                for name in apps(for: device, usage) where !entries[index].apps.contains(name) {
                    entries[index].apps.append(name)
                }
            case (false, let index?):
                entries[index].end = date
                closed = true
            case (false, nil):
                break
            }
        }
        return closed
    }

    /// Drops entries that ended more than 7 days before `date`.
    mutating func prune(now date: Date) {
        let cutoff = date.addingTimeInterval(-Self.retention)
        entries.removeAll { ($0.end ?? date) < cutoff }
    }

    /// Closes open entries, e.g. at quit.
    mutating func closeAll(at date: Date) {
        for index in entries.indices where entries[index].end == nil {
            entries[index].end = date
        }
    }

    mutating func clear() {
        entries = []
    }

    private func apps(for device: PrivacyDevice, _ usage: DeviceUsage) -> [String] {
        device == .microphone ? usage.micUsers.map(\.name) : []
    }
}
