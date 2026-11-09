import Foundation

/// A macOS privacy permission a feature may need.
public enum Permission: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case accessibility
    case inputMonitoring
    case screenRecording
    case microphone
    case automation
    case notifications
    case location

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .accessibility: String(localized: "Accessibility")
        case .inputMonitoring: String(localized: "Input Monitoring")
        case .screenRecording: String(localized: "Screen Recording")
        case .microphone: String(localized: "Microphone")
        case .automation: String(localized: "Automation")
        case .notifications: String(localized: "Notifications")
        case .location: String(localized: "Location")
        }
    }

    /// One sentence on why KKit might ask for it.
    public var explanation: String {
        switch self {
        case .accessibility:
            String(localized: "Lets KKit move windows, paste for you and read app menus.")
        case .inputMonitoring:
            String(localized: "Lets KKit see key presses for the Hyper key, media keys and Clean Mode.")
        case .screenRecording:
            String(localized: "Lets KKit take screenshots, recordings and read text on screen.")
        case .microphone:
            String(localized: "Lets KKit record your voice with screen recordings.")
        case .automation:
            String(localized: "Lets KKit control other apps, such as Finder or Music, when you ask.")
        case .notifications:
            String(localized: "Lets KKit alert you when the Island isn't visible.")
        case .location:
            String(localized: "Lets KKit work out sunset and sunrise times for your city.")
        }
    }

    public var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .inputMonitoring: "keyboard"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .microphone: "mic"
        case .automation: "gearshape.2"
        case .notifications: "bell.badge"
        case .location: "location"
        }
    }
}

/// Whether a permission is granted.
public enum PermissionStatus: Sendable, Hashable {
    case granted
    case denied
    case notDetermined
    /// macOS doesn't report a global status (e.g. Automation is per target app).
    case unknown

    public var isGranted: Bool { self == .granted }
}

/// Reads permission status. `FeatureManager` uses it to decide which features may run;
/// the full `PermissionsService` (in KKitServicesAPI) refines it with requests.
@MainActor
public protocol PermissionStatusProviding: AnyObject {
    func status(of permission: Permission) -> PermissionStatus
    /// Re-read every status from the system.
    func refresh()
}
