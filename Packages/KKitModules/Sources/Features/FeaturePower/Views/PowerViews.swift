import AppKit
import KKitCore
import KKitUI
import SwiftUI

/// Right ear: the countdown, ∞ or "Auto".
struct PowerCompactTrailing: View {
    let controller: PowerController

    var body: some View {
        if let end = controller.session?.endDate, end > Date() {
            Text(timerInterval: Date()...end, countsDown: true)
                .multilineTextAlignment(.trailing)
        } else if controller.session != nil {
            Image(systemName: "infinity")
        } else {
            Text("Auto")
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// The Power page in the expanded Island.
struct PowerIslandView: View {
    let controller: PowerController

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.m) {
            HStack(spacing: KKSpacing.m) {
                Image(systemName: controller.isAwake ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.title2)
                    .foregroundStyle(controller.isAwake ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.isAwake ? "Keeping your Mac awake" : "Your Mac can sleep normally")
                        .font(.headline)
                    PowerStatusLine(controller: controller)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.session != nil {
                    Button("Allow Sleep") { controller.allowSleep() }
                        .controlSize(.small)
                }
            }
            PowerDurationButtons(controller: controller)
        }
    }
}

/// "Until 17:30", "Indefinitely", "Because the power adapter is connected".
struct PowerStatusLine: View {
    let controller: PowerController

    var body: some View {
        if let end = controller.session?.endDate {
            Text("Until \(end.formatted(date: .omitted, time: .shortened))")
        } else if controller.session != nil {
            Text("Indefinitely")
        } else if !controller.ruleReasons.isEmpty {
            Text(Self.describe(controller.ruleReasons))
        } else if controller.stoppedForBattery {
            Text("Stopped because the battery is low")
        } else {
            Text("Pick a duration below")
        }
    }

    static func describe(_ reasons: Set<AwakeReason>) -> String {
        var parts: [String] = []
        if reasons.contains(.powerAdapter) {
            parts.append(String(localized: "the power adapter is connected"))
        }
        if reasons.contains(.externalDisplay) {
            parts.append(String(localized: "an external display is connected"))
        }
        let apps = reasons.compactMap { reason -> String? in
            guard case .app(let bundleID) = reason else { return nil }
            return AppName.of(bundleID)
        }.sorted()
        if !apps.isEmpty {
            parts.append(String(localized: "\(apps.formatted(.list(type: .and))) is running"))
        }
        return String(localized: "Because \(parts.formatted(.list(type: .and)))")
    }
}

struct PowerDurationButtons: View {
    let controller: PowerController

    private struct Preset: Identifiable {
        let label: String
        let seconds: TimeInterval?
        var id: String { label }
    }

    private static let presets: [Preset] = [
        Preset(label: "15m", seconds: 15 * 60),
        Preset(label: "1h", seconds: 3600),
        Preset(label: "2h", seconds: 7200),
        Preset(label: "4h", seconds: 4 * 3600),
        Preset(label: "∞", seconds: nil),
    ]

    var body: some View {
        HStack(spacing: KKSpacing.s) {
            ForEach(Self.presets) { preset in
                Button(preset.label) {
                    controller.keepAwake(for: preset.seconds)
                }
                .controlSize(.small)
                .accessibilityLabel(preset.seconds == nil ? Text("Keep awake indefinitely") : Text("Keep awake for \(preset.label)"))
            }
            if controller.session?.endDate != nil {
                Button("+15m") { controller.extend(by: 15 * 60) }
                    .controlSize(.small)
            }
        }
    }
}

/// Settings › Power.
struct PowerSettingsView: View {
    let controller: PowerController

    @Setting(PowerSettings.defaultMinutes) private var defaultMinutes
    @Setting(PowerSettings.keepDisplayAwake) private var keepDisplayAwake
    @Setting(PowerSettings.showInIsland) private var showInIsland
    @Setting(PowerSettings.batteryCutoff) private var batteryCutoff
    @Setting(PowerSettings.awakeOnPowerAdapter) private var awakeOnPowerAdapter
    @Setting(PowerSettings.awakeWithExternalDisplay) private var awakeWithExternalDisplay
    @Setting(PowerSettings.awakeWhileApps) private var awakeWhileApps

    var body: some View {
        Group {
            general
            rules
        }
    }

    @ViewBuilder
    private var general: some View {
        KKRow(
            controller.isAwake ? String(localized: "Keeping your Mac awake") : String(localized: "Not keeping awake"),
            symbol: "cup.and.saucer"
        ) {
            if controller.session != nil {
                Button(String(localized: "Allow Sleep")) { controller.allowSleep() }
            }
        }
        PowerDurationButtons(controller: controller)
        Picker(String(localized: "“Toggle Keep Awake” lasts"), selection: $defaultMinutes) {
            Text("Until turned off").tag(0)
            Text("15 minutes").tag(15)
            Text("30 minutes").tag(30)
            Text("1 hour").tag(60)
            Text("2 hours").tag(120)
            Text("4 hours").tag(240)
        }
        Toggle(String(localized: "Keep the display on too"), isOn: $keepDisplayAwake)
        Toggle(String(localized: "Show in the Island"), isOn: $showInIsland)
        Picker(String(localized: "Stop on battery below"), selection: $batteryCutoff) {
            Text("Never").tag(0)
            Text("10%").tag(10)
            Text("20%").tag(20)
            Text("30%").tag(30)
            Text("50%").tag(50)
        }
    }

    @ViewBuilder
    private var rules: some View {
        Text("Stay awake automatically")
            .font(.headline)
            .padding(.top, KKSpacing.s)
        Toggle(String(localized: "While the power adapter is connected"), isOn: $awakeOnPowerAdapter)
        Toggle(String(localized: "While an external display is connected"), isOn: $awakeWithExternalDisplay)
        ForEach(awakeWhileApps, id: \.self) { bundleID in
            KKRow(String(localized: "While \(AppName.of(bundleID)) is running"), symbol: "app") {
                Button {
                    awakeWhileApps.removeAll { $0 == bundleID }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove \(AppName.of(bundleID))"))
            }
        }
        Menu(String(localized: "Add App…")) {
            ForEach(AppName.runningApps().filter { !awakeWhileApps.contains($0.bundleID) }) { app in
                Button(app.name) { awakeWhileApps.append(app.bundleID) }
            }
        }
        .fixedSize()
    }
}

/// App names and the list of running apps, for the "while app is running" rule.
enum AppName {
    @MainActor
    static func of(_ bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    struct RunningApp: Identifiable {
        let name: String
        let bundleID: String
        var id: String { bundleID }
    }

    @MainActor
    static func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
                return RunningApp(name: app.localizedName ?? id, bundleID: id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
