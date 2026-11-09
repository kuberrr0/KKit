import AppKit
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Left ear: mic (orange, or red and struck through when muted) and camera (green).
struct PrivacyCompactLeading: View {
    let indicator: PrivacyIndicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(indicator.symbols, id: \.self) { symbol in
                Image(systemName: symbol)
                    .foregroundStyle(color(for: symbol))
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private func color(for symbol: String) -> Color {
        switch symbol {
        case "mic.slash.fill": .red
        case "mic.fill": .orange
        default: .green
        }
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if indicator.micInUse {
            parts.append(indicator.micMuted ? String(localized: "Microphone in use, muted") : String(localized: "Microphone in use"))
        }
        if indicator.cameraInUse {
            parts.append(String(localized: "Camera in use"))
        }
        return parts.joined(separator: ", ")
    }
}

/// Right ear: the app's name, "Muted", or "Camera".
struct PrivacyCompactTrailing: View {
    let indicator: PrivacyIndicator

    var body: some View {
        Text(indicator.label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(indicator.micMuted ? Color.red : Color.white.opacity(0.85))
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// The expanded page: which apps are using the mic, the camera, and a mute button.
struct PrivacyIslandView: View {
    let model: PrivacyModel
    let toggleMute: () -> Void

    var body: some View {
        let usage = model.usage
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            if usage.micInUse {
                HStack {
                    Label {
                        model.inputMuted ? Text("Microphone in use, muted") : Text("Microphone in use")
                    } icon: {
                        Image(systemName: model.inputMuted ? "mic.slash.fill" : "mic.fill")
                            .foregroundStyle(model.inputMuted ? Color.red : Color.orange)
                    }
                    .font(.callout.weight(.semibold))
                    Spacer()
                    Button(model.inputMuted ? String(localized: "Unmute") : String(localized: "Mute")) {
                        toggleMute()
                    }
                    .controlSize(.small)
                }
                if usage.micUsers.isEmpty {
                    Text("macOS doesn't say which app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(usage.micUsers) { user in
                        HStack(spacing: KKSpacing.s) {
                            AppIcon(pid: user.pid)
                            Text(user.name)
                                .font(.callout)
                        }
                    }
                }
                if let device = model.inputDeviceName {
                    Text(device)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if usage.cameraInUse {
                Label {
                    Text("Camera in use")
                } icon: {
                    Image(systemName: "video.fill")
                        .foregroundStyle(.green)
                }
                .font(.callout.weight(.semibold))
            }
            if !usage.micInUse && !usage.cameraInUse {
                Text("Nothing is using the microphone or camera.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppIcon: View {
    let pid: Int32

    var body: some View {
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app")
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        }
    }
}

/// Settings › Privacy Indicator.
struct PrivacySettingsView: View {
    let model: PrivacyModel
    let clearLog: () -> Void

    @Setting(PrivacySettings.showMic) private var showMic
    @Setting(PrivacySettings.showCamera) private var showCamera
    @Setting(PrivacySettings.showAppNames) private var showAppNames
    @Setting(PrivacySettings.clickTogglesMute) private var clickTogglesMute
    @Setting(PrivacySettings.keepLog) private var keepLog

    var body: some View {
        Group {
            KKSection(
                String(localized: "Show in the Island"),
                footer: String(localized: "macOS doesn't say which app is using a camera, so KKit shows “Camera” without a name.")
            ) {
                Toggle(String(localized: "When the microphone is in use"), isOn: $showMic)
                Toggle(String(localized: "When a camera is in use"), isOn: $showCamera)
                Toggle(String(localized: "Show app names"), isOn: $showAppNames)
                Toggle(String(localized: "Click to mute or unmute the microphone"), isOn: $clickTogglesMute)
            }
            KKSection(
                String(localized: "Log"),
                footer: String(localized: "Stored only on this Mac and deleted after 7 days. Turning the log off deletes it.")
            ) {
                Toggle(String(localized: "Keep a 7-day log of microphone and camera use"), isOn: $keepLog)
                if keepLog {
                    let entries = Array(model.log.entries.reversed().prefix(50))
                    if entries.isEmpty {
                        Text("Nothing logged yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            UsageLogRow(entry: entry)
                        }
                        Button(String(localized: "Clear Log"), role: .destructive) {
                            clearLog()
                        }
                    }
                }
            }
        }
    }
}

struct UsageLogRow: View {
    let entry: UsageLogEntry

    var body: some View {
        HStack(spacing: KKSpacing.s) {
            Image(systemName: entry.device.symbol)
                .foregroundStyle(entry.device == .microphone ? Color.orange : Color.green)
                .frame(width: 20)
                .accessibilityLabel(Text(entry.device.title))
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.apps.isEmpty ? entry.device.title : entry.apps.joined(separator: ", "))
                Text(entry.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let duration = entry.duration {
                Text(KKFormat.shortDuration(duration))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                KKStatusBadge(String(localized: "Now"), tone: .warning)
            }
        }
    }
}
