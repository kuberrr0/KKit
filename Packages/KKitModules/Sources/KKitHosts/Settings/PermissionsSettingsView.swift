import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Each macOS permission, its status, which features need it, and a button to grant it.
struct PermissionsSettingsView: View {
    let dependencies: HostDependencies

    var body: some View {
        KKForm {
            KKSection(
                footer: String(localized: "KKit only asks for a permission when you turn on a feature that needs it.")
            ) {
                ForEach(sortedPermissions) { permission in
                    PermissionRow(
                        permission: permission,
                        status: dependencies.permissions.status(of: permission),
                        usedBy: users(of: permission),
                        permissions: dependencies.permissions
                    )
                }
            }
        }
    }

    /// Permissions some feature uses come first.
    private var sortedPermissions: [Permission] {
        let used = Permission.allCases.filter { !users(of: $0).isEmpty }
        let unused = Permission.allCases.filter { users(of: $0).isEmpty }
        return used + unused
    }

    private func users(of permission: Permission) -> [String] {
        dependencies.features.manifests
            .filter { $0.requiredPermissions.contains(permission) || $0.optionalPermissions.contains(permission) }
            .map(\.name)
    }
}

struct PermissionRow: View {
    let permission: Permission
    let status: PermissionStatus
    let usedBy: [String]
    let permissions: any PermissionsService

    var body: some View {
        KKRow(permission.displayName, subtitle: subtitle, symbol: permission.symbol) {
            HStack(spacing: KKSpacing.s) {
                PermissionStatusBadge(status: status)
                if status == .granted || status == .unknown {
                    Button(String(localized: "Open Settings")) {
                        permissions.openSystemSettings(for: permission)
                    }
                } else {
                    Button(String(localized: "Allow…")) {
                        Task { await permissions.request(permission) }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let users = usedBy.isEmpty
            ? String(localized: "Not used by any feature yet.")
            : String(localized: "Used by \(usedBy.formatted(.list(type: .and))).")
        return "\(permission.explanation) \(users)"
    }
}

struct PermissionStatusBadge: View {
    let status: PermissionStatus

    var body: some View {
        switch status {
        case .granted: KKStatusBadge(String(localized: "Allowed"), tone: .positive)
        case .denied: KKStatusBadge(String(localized: "Not allowed"), tone: .warning)
        case .notDetermined: KKStatusBadge(String(localized: "Not asked"), tone: .neutral)
        case .unknown: KKStatusBadge(String(localized: "Per app"), tone: .neutral)
        }
    }
}
