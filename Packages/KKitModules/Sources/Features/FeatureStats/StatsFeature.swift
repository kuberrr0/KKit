import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// CPU, memory, disk, network, battery and thermal stats: menu bar items, a strip in
/// the KKit menu, an Island page, and Island alerts. DESIGN.md §3.3.
@MainActor
public final class StatsFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "stats",
        name: String(localized: "Stats"),
        symbol: "chart.xyaxis.line",
        summary: String(localized: "CPU, memory, disk, network and battery at a glance, with alerts."),
        category: .system,
        enabledByDefault: true
    )

    private let context: FeatureContext
    let model: StatsModel
    private var alerts = StatsAlertState()
    private var tasks: [Task<Void, Never>] = []

    public init(context: FeatureContext) {
        self.context = context
        self.model = StatsModel(systemInfo: context.systemInfo, power: context.power, settings: context.settings)
    }

    public func start() async throws {
        let settings = context.settings

        let metrics = settings.changes(of: StatsSettings.menuBarMetrics)
        tasks.append(Task { [weak self] in
            for await metrics in metrics {
                self?.model.setPersistentDemand(!metrics.isEmpty)
            }
        })
        let interval = settings.changes(of: StatsSettings.sampleSeconds)
        tasks.append(Task { [weak self] in
            for await _ in interval {
                self?.model.updateSampling()
            }
        })

        // Alerts: battery and memory pressure are events; disk is checked twice an hour.
        let power = context.power.powerSourceUpdates()
        tasks.append(Task { [weak self] in
            for await source in power {
                guard let self else { return }
                self.model.record(source)
                let alert = self.alerts.check(power: source, thresholdPercent: settings[StatsSettings.batteryAlert])
                self.show(alert)
            }
        })
        let pressure = context.systemInfo.memoryPressureUpdates()
        tasks.append(Task { [weak self] in
            for await level in pressure {
                guard let self else { return }
                let alert = self.alerts.check(pressure: level, enabled: settings[StatsSettings.memoryPressureAlert])
                self.show(alert)
            }
        })
        let disk = context.systemInfo.samples(every: .seconds(30 * 60), includeProcesses: false)
        tasks.append(Task { [weak self] in
            for await sample in disk {
                guard let self else { return }
                let alert = self.alerts.check(disk: sample.disk, thresholdGB: settings[StatsSettings.diskAlertGB])
                self.show(alert)
            }
        })
    }

    public func stop() async {
        tasks.forEach { $0.cancel() }
        tasks = []
        model.stop()
    }

    // MARK: Contributions

    public var commands: [Command] {
        [
            Command(
                id: "stats.copySummary",
                title: String(localized: "Copy System Stats"),
                subtitle: String(localized: "CPU, memory, disk and battery as text"),
                symbol: "doc.on.doc",
                keywords: ["cpu", "memory", "disk", "battery", "stats"]
            ) { [weak self] _ in
                guard let self else { return }
                self.model.acquire()
                defer { self.model.release() }
                // Give the sampler a moment for a first reading.
                for _ in 0..<20 where self.model.latest == nil {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(StatsText.summary(self.model), forType: .string)
            },
        ]
    }

    public var menuBarSections: [MenuBarSection] {
        guard context.settings[StatsSettings.showInMenu] else { return [] }
        return [MenuBarSection(id: "strip", order: 900) { [model] in
            StatsStripView(model: model)
        }]
    }

    public var menuBarItems: [MenuBarItem] {
        let settings = context.settings
        return StatsMetric.allCases.map { metric in
            MenuBarItem(
                id: metric.rawValue,
                title: metric.title,
                isVisible: { settings[StatsSettings.menuBarMetrics].contains(metric) },
                label: { [model] in StatsMenuBarLabel(metric: metric, model: model) },
                popover: { [model] in StatsDetailView(model: model) }
            )
        }
    }

    public var islandPages: [IslandPage] {
        [IslandPage(id: "stats", title: String(localized: "Stats"), symbol: "chart.xyaxis.line") { [model] in
            StatsIslandView(model: model)
        }]
    }

    public var settingsPane: SettingsPane? {
        SettingsPane { StatsSettingsView() }
    }

    // MARK: Alerts

    private func show(_ alert: StatsAlertState.Alert?) {
        guard let alert else { return }
        let hud: IslandHUD
        switch alert {
        case .batteryLow(let percent):
            hud = IslandHUD(id: "stats.battery", symbol: "battery.25percent", title: String(localized: "Battery \(percent)%"),
                            tint: .warning, duration: 5)
        case .memoryPressure(let level):
            hud = IslandHUD(id: "stats.memory", symbol: "memorychip",
                            title: level == .critical ? String(localized: "Memory pressure critical") : String(localized: "Memory pressure high"),
                            tint: level == .critical ? .critical : .warning, duration: 5)
        case .diskLow(let available):
            hud = IslandHUD(id: "stats.disk", symbol: "internaldrive",
                            title: String(localized: "Disk almost full: \(KKFormat.bytes(available)) free"),
                            tint: .warning, duration: 6)
        }
        context.island.showHUD(hud)
    }
}

/// Plain-text stats, for "Copy System Stats".
enum StatsText {
    @MainActor
    static func summary(_ model: StatsModel) -> String {
        var lines: [String] = []
        if let sample = model.latest {
            lines.append("CPU: \(KKFormat.percent(sample.cpu.total))")
            lines.append("Memory: \(KKFormat.bytes(Int64(sample.memory.used))) of \(KKFormat.bytes(Int64(sample.memory.total))) (\(KKFormat.percent(sample.memory.usedFraction)))")
            lines.append("Disk: \(KKFormat.bytes(sample.disk.availableBytes)) free of \(KKFormat.bytes(sample.disk.totalBytes))")
            lines.append("Network: ↓ \(KKFormat.rate(sample.network.bytesInPerSecond)) ↑ \(KKFormat.rate(sample.network.bytesOutPerSecond))")
        }
        if model.power.hasBattery, let level = model.power.batteryLevel {
            lines.append("Battery: \(KKFormat.percent(level))\(model.power.isCharging ? " (charging)" : "")")
        }
        return lines.joined(separator: "\n")
    }
}
