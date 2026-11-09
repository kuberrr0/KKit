import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Starts sampling while the view is on screen.
struct SamplesWhileVisible: ViewModifier {
    let model: StatsModel
    let processes: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { model.acquire(processes: processes) }
            .onDisappear { model.release(processes: processes) }
    }
}

extension View {
    func samplesStats(_ model: StatsModel, processes: Bool = false) -> some View {
        modifier(SamplesWhileVisible(model: model, processes: processes))
    }
}

// MARK: Menu bar

/// One metric's menu bar label.
struct StatsMenuBarLabel: View {
    let metric: StatsMetric
    let model: StatsModel

    var body: some View {
        HStack(spacing: 3) {
            switch metric {
            case .cpu:
                KKSparkline(model.cpuHistory)
                    .frame(width: 28, height: 14)
                Text(model.latest.map { KKFormat.percent($0.cpu.total) } ?? "–")
            case .memory:
                Image(systemName: metric.symbol)
                Text(model.latest.map { KKFormat.percent($0.memory.usedFraction) } ?? "–")
            case .network:
                VStack(alignment: .trailing, spacing: -2) {
                    Text("↑ " + (model.latest.map { KKFormat.rate($0.network.bytesOutPerSecond) } ?? "–"))
                    Text("↓ " + (model.latest.map { KKFormat.rate($0.network.bytesInPerSecond) } ?? "–"))
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
            case .disk:
                Image(systemName: metric.symbol)
                Text(model.latest.map { KKFormat.bytes($0.disk.availableBytes) } ?? "–")
            case .battery:
                Image(systemName: BatterySymbol.name(for: model.power))
                Text(model.power.batteryLevel.map(KKFormat.percent) ?? "–")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(metric.title))
    }
}

enum BatterySymbol {
    static func name(for power: PowerSourceInfo) -> String {
        if power.isCharging { return "battery.100percent.bolt" }
        let level = power.batteryLevel ?? 1
        switch level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// The strip in the KKit menu: "CPU 12% ▁▂▁▃  MEM 61%  SSD 214 GB free" and a battery line.
struct StatsStripView: View {
    let model: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.xs) {
            HStack(spacing: KKSpacing.m) {
                HStack(spacing: KKSpacing.xs) {
                    Text("CPU").foregroundStyle(.secondary)
                    Text(model.latest.map { KKFormat.percent($0.cpu.total) } ?? "–")
                    KKSparkline(model.cpuHistory).frame(width: 36, height: 12)
                }
                HStack(spacing: KKSpacing.xs) {
                    Text("MEM").foregroundStyle(.secondary)
                    Text(model.latest.map { KKFormat.percent($0.memory.usedFraction) } ?? "–")
                }
                HStack(spacing: KKSpacing.xs) {
                    Text("SSD").foregroundStyle(.secondary)
                    Text(model.latest.map { "\(KKFormat.bytes($0.disk.availableBytes)) free" } ?? "–")
                }
            }
            if model.power.hasBattery {
                BatteryLine(power: model.power, health: model.batteryHealth)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
        .samplesStats(model)
    }
}

/// "🔋 86% · 4h 10m left · Health 91%"
struct BatteryLine: View {
    let power: PowerSourceInfo
    let health: BatteryHealth?

    var body: some View {
        HStack(spacing: KKSpacing.xs) {
            Image(systemName: BatterySymbol.name(for: power))
            Text(Self.text(power: power, health: health))
        }
    }

    static func text(power: PowerSourceInfo, health: BatteryHealth?) -> String {
        var parts: [String] = []
        if let level = power.batteryLevel {
            parts.append(KKFormat.percent(level))
        }
        if power.isCharging, let minutes = power.minutesToFull {
            parts.append(String(localized: "\(KKFormat.shortDuration(Double(minutes * 60))) to full"))
        } else if !power.isOnAC, let minutes = power.minutesToEmpty {
            parts.append(String(localized: "\(KKFormat.shortDuration(Double(minutes * 60))) left"))
        } else if power.isOnAC {
            parts.append(power.isCharging ? String(localized: "Charging") : String(localized: "On power adapter"))
        }
        if let value = health?.health {
            parts.append(String(localized: "Health \(KKFormat.percent(min(value, 1)))"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: Island

/// The Stats page in the expanded Island.
struct StatsIslandView: View {
    let model: StatsModel

    var body: some View {
        let sample = model.latest
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            HStack(spacing: KKSpacing.s) {
                StatTile(title: "CPU", value: sample.map { KKFormat.percent($0.cpu.total) } ?? "–") {
                    KKSparkline(model.cpuHistory, tint: .green).frame(height: 22)
                }
                StatTile(title: "Memory", value: sample.map { KKFormat.percent($0.memory.usedFraction) } ?? "–") {
                    KKLevelBar(value: sample?.memory.usedFraction ?? 0, tint: Self.pressureColor(sample?.memory.pressure)).frame(height: 5)
                }
                StatTile(title: "Disk", value: sample.map { KKFormat.bytes($0.disk.availableBytes) } ?? "–") {
                    KKLevelBar(value: sample?.disk.usedFraction ?? 0, tint: .blue).frame(height: 5)
                }
                StatTile(title: "Network", value: sample.map { "↓ " + KKFormat.rate($0.network.bytesInPerSecond) } ?? "–") {
                    KKSparkline(StatsModel.normalized(model.networkInHistory), tint: .cyan).frame(height: 22)
                }
            }
            if model.power.hasBattery {
                BatteryLine(power: model.power, health: model.batteryHealth)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .samplesStats(model)
    }

    static func pressureColor(_ pressure: MemoryPressure?) -> Color {
        switch pressure {
        case .critical: .red
        case .warning: .orange
        default: .green
        }
    }
}

struct StatTile<Graph: View>: View {
    let title: String
    let value: String
    @ViewBuilder let graph: () -> Graph

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.xs) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            graph()
        }
        .padding(KKSpacing.s)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: KKRadius.row, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Details popover

/// Everything, for the menu bar items' popover.
struct StatsDetailView: View {
    let model: StatsModel

    var body: some View {
        let sample = model.latest
        VStack(alignment: .leading, spacing: KKSpacing.m) {
            section("CPU", symbol: "cpu") {
                HStack {
                    Text(sample.map { KKFormat.percent($0.cpu.total) } ?? "–").font(.title3.weight(.semibold).monospacedDigit())
                    Spacer()
                    if let cpu = sample?.cpu {
                        Text("User \(KKFormat.percent(cpu.user)) · System \(KKFormat.percent(cpu.system))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                KKSparkline(model.cpuHistory, tint: .green).frame(height: 28)
                if let cores = sample?.cpu.perCore, !cores.isEmpty {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(cores.enumerated()), id: \.offset) { _, value in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.green.opacity(0.35 + 0.65 * value))
                                .frame(height: max(2, 20 * value))
                        }
                    }
                    .frame(height: 20, alignment: .bottom)
                    .accessibilityHidden(true)
                }
                ForEach(sample?.topProcesses.prefix(5).map { $0 } ?? []) { process in
                    HStack {
                        Text(process.name).lineLimit(1)
                        Spacer()
                        Text("\(Int((process.cpu * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            section("Memory", symbol: "memorychip") {
                if let memory = sample?.memory {
                    HStack {
                        Text("\(KKFormat.bytes(Int64(memory.used))) of \(KKFormat.bytes(Int64(memory.total)))")
                        Spacer()
                        Text(Self.pressureName(memory.pressure)).foregroundStyle(StatsIslandView.pressureColor(memory.pressure))
                    }
                    KKLevelBar(value: memory.usedFraction, tint: StatsIslandView.pressureColor(memory.pressure)).frame(height: 5)
                    Text("App \(KKFormat.bytes(Int64(memory.app))) · Wired \(KKFormat.bytes(Int64(memory.wired))) · Compressed \(KKFormat.bytes(Int64(memory.compressed))) · Swap \(KKFormat.bytes(Int64(memory.swapUsed)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            section("Disk", symbol: "internaldrive") {
                if let disk = sample?.disk {
                    HStack {
                        Text(disk.name)
                        Spacer()
                        Text("\(KKFormat.bytes(disk.availableBytes)) free of \(KKFormat.bytes(disk.totalBytes))").foregroundStyle(.secondary)
                    }
                    KKLevelBar(value: disk.usedFraction, tint: .blue).frame(height: 5)
                }
            }
            section("Network", symbol: "network") {
                if let network = sample?.network {
                    HStack {
                        Text("↓ \(KKFormat.rate(network.bytesInPerSecond))")
                        Text("↑ \(KKFormat.rate(network.bytesOutPerSecond))")
                        Spacer()
                        if let ip = network.localIP {
                            Text(ip).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    .monospacedDigit()
                }
            }
            if model.power.hasBattery {
                section("Battery", symbol: "battery.75percent") {
                    BatteryLine(power: model.power, health: model.batteryHealth)
                    if let health = model.batteryHealth {
                        HStack(spacing: KKSpacing.m) {
                            if let cycles = health.cycleCount { Text("\(cycles) cycles") }
                            if let watts = health.powerWatts { Text(String(format: "%.1f W", abs(watts))) }
                            if let temperature = health.temperatureCelsius { Text(String(format: "%.0f °C", temperature)) }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let thermal = sample?.thermal, thermal != .nominal {
                Label(Self.thermalName(thermal), systemImage: "thermometer.high")
                    .foregroundStyle(thermal == .fair ? Color.secondary : Color.orange)
            }
        }
        .font(.callout)
        .padding(KKSpacing.m)
        .frame(width: 320)
        .samplesStats(model, processes: true)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: KKSpacing.xs) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    static func pressureName(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: String(localized: "Pressure normal")
        case .warning: String(localized: "Pressure high")
        case .critical: String(localized: "Pressure critical")
        }
    }

    static func thermalName(_ level: ThermalLevel) -> String {
        switch level {
        case .nominal: String(localized: "Thermals normal")
        case .fair: String(localized: "Warm")
        case .serious: String(localized: "Hot: performance may be reduced")
        case .critical: String(localized: "Very hot: performance reduced")
        }
    }
}

// MARK: Settings

struct StatsSettingsView: View {
    @Setting(StatsSettings.menuBarMetrics) private var menuBarMetrics
    @Setting(StatsSettings.showInMenu) private var showInMenu
    @Setting(StatsSettings.sampleSeconds) private var sampleSeconds
    @Setting(StatsSettings.batteryAlert) private var batteryAlert
    @Setting(StatsSettings.memoryPressureAlert) private var memoryPressureAlert
    @Setting(StatsSettings.diskAlertGB) private var diskAlertGB

    var body: some View {
        Group {
            Text("Menu bar items").font(.headline)
            ForEach(StatsMetric.allCases) { metric in
                Toggle(isOn: binding(for: metric)) {
                    Label(metric.title, systemImage: metric.symbol)
                }
            }
            Toggle(String(localized: "Show the stats strip in the KKit menu"), isOn: $showInMenu)
            Picker(String(localized: "Update every"), selection: $sampleSeconds) {
                Text("1 second").tag(1)
                Text("2 seconds").tag(2)
                Text("5 seconds").tag(5)
                Text("10 seconds").tag(10)
            }
        }
        Group {
            Text("Alerts in the Island").font(.headline).padding(.top, KKSpacing.s)
            Picker(String(localized: "Battery low"), selection: $batteryAlert) {
                Text("Off").tag(0)
                Text("10%").tag(10)
                Text("15%").tag(15)
                Text("20%").tag(20)
            }
            Toggle(String(localized: "Memory pressure high"), isOn: $memoryPressureAlert)
            Picker(String(localized: "Disk almost full"), selection: $diskAlertGB) {
                Text("Off").tag(0)
                Text("Below 5 GB").tag(5)
                Text("Below 10 GB").tag(10)
                Text("Below 20 GB").tag(20)
            }
        }
    }

    private func binding(for metric: StatsMetric) -> Binding<Bool> {
        let metrics = $menuBarMetrics
        return Binding(
            get: { metrics.wrappedValue.contains(metric) },
            set: { on in
                var updated = metrics.wrappedValue.filter { $0 != metric }
                if on { updated.append(metric) }
                // Keep a stable order in the menu bar.
                metrics.wrappedValue = StatsMetric.allCases.filter { updated.contains($0) }
            }
        )
    }
}
