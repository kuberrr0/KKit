import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// A feature's page: header with the on/off switch and state, the feature's own
/// settings pane, its shortcuts and its permissions.
struct FeatureSettingsView: View {
    let dependencies: HostDependencies
    let manifest: FeatureManifest

    private var features: FeatureManager { dependencies.features }
    private var state: FeatureState { features.state(of: manifest.id) }

    var body: some View {
        KKForm {
            KKSection {
                HStack(spacing: KKSpacing.m) {
                    KKFeatureIcon(manifest.symbol, size: 36)
                    VStack(alignment: .leading, spacing: KKSpacing.xxs) {
                        Text(manifest.name)
                            .font(.title3.weight(.semibold))
                        Text(manifest.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(String(localized: "Enabled"), isOn: isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                stateRow
            }

            if let feature = features.runningFeature(manifest.id), let pane = feature.settingsPane {
                KKSection {
                    pane.makeView()
                        .environment(\.featureSettings, features.settings(for: manifest.id))
                }
            }

            let commands = dependencies.commands.commands(owner: manifest.id)
            if !commands.isEmpty {
                KKSection(String(localized: "Shortcuts")) {
                    ForEach(commands) { command in
                        CommandShortcutRow(command: command, dependencies: dependencies)
                    }
                }
            }

            let permissions = manifest.requiredPermissions.union(manifest.optionalPermissions)
            KKSection(String(localized: "Permissions")) {
                if permissions.isEmpty {
                    Text("None needed")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Permission.allCases.filter { permissions.contains($0) }) { permission in
                        PermissionRow(
                            permission: permission,
                            status: dependencies.permissions.status(of: permission),
                            usedBy: [],
                            permissions: dependencies.permissions
                        )
                    }
                }
            }
        }
    }

    private var isEnabled: Binding<Bool> {
        let features = self.features
        let id = manifest.id
        return Binding(
            get: { features.isEnabled(id) },
            set: { enabled in
                Task { await features.setEnabled(enabled, for: id) }
            }
        )
    }

    @ViewBuilder
    private var stateRow: some View {
        switch state {
        case .disabled:
            EmptyView()
        case .unsupported:
            Label(String(localized: "Needs a newer version of macOS."), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        case .starting:
            HStack(spacing: KKSpacing.s) {
                ProgressView().controlSize(.small)
                Text("Starting…")
                    .foregroundStyle(.secondary)
            }
        case .running:
            Label(String(localized: "Running"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .waitingForPermissions(let missing):
            VStack(alignment: .leading, spacing: KKSpacing.s) {
                Label(
                    String(localized: "Waiting for \(Self.names(of: missing)). It starts as soon as you allow it."),
                    systemImage: "hand.raised"
                )
                .foregroundStyle(.orange)
                HStack {
                    ForEach(Permission.allCases.filter { missing.contains($0) }) { permission in
                        Button(String(localized: "Allow \(permission.displayName)…")) {
                            Task { await dependencies.permissions.request(permission) }
                        }
                    }
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: KKSpacing.s) {
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Button(String(localized: "Retry")) {
                    let features = self.features
                    let id = manifest.id
                    Task { await features.retry(id) }
                }
            }
        }
    }

    private static func names(of permissions: Set<Permission>) -> String {
        Permission.allCases.filter { permissions.contains($0) }.map(\.displayName).formatted(.list(type: .and))
    }
}
