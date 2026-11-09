import Foundation
import KKitCore

/// macOS privacy permissions: status, requests, and the right System Settings pane.
///
/// Implementations are `@Observable`, so views reading `status(of:)` update when a
/// permission changes.
@MainActor
public protocol PermissionsService: PermissionStatusProviding {
    /// Shows the system prompt where macOS has one, otherwise opens System Settings.
    /// Returns the status afterwards (prompts that finish later report through
    /// `onChange`).
    @discardableResult
    func request(_ permission: Permission) async -> PermissionStatus

    /// Opens System Settings › Privacy & Security at the permission's pane.
    func openSystemSettings(for permission: Permission)

    /// Called after any status changes. The app uses it to start waiting features.
    var onChange: (@MainActor () -> Void)? { get set }

    /// True when this copy of KKit is signed ad-hoc (no team). macOS ties a grant to
    /// the exact build then, so every rebuild loses Accessibility, Input Monitoring
    /// and Screen Recording, and System Settings can show a switch that's on for an
    /// older build. Settings › Permissions warns about it.
    var isSignedAdHoc: Bool { get }
}

public extension PermissionsService {
    var isSignedAdHoc: Bool { false }
}
