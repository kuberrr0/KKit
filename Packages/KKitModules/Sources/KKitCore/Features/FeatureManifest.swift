import Foundation

/// Where a feature is grouped in Settings and onboarding.
public enum FeatureCategory: String, Sendable, Codable, CaseIterable {
    case system
    case display
    case audio
    case capture
    case productivity
    case input
    case windows

    public var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .display: String(localized: "Display")
        case .audio: String(localized: "Audio")
        case .capture: String(localized: "Capture")
        case .productivity: String(localized: "Productivity")
        case .input: String(localized: "Input")
        case .windows: String(localized: "Windows")
        }
    }
}

/// Static metadata about a feature, readable without starting it.
public struct FeatureManifest: Sendable, Identifiable {
    public var id: FeatureID
    /// "Night Shift"
    public var name: String
    /// SF Symbol used everywhere for this feature: "moon.stars".
    public var symbol: String
    /// One sentence for onboarding and Settings.
    public var summary: String
    public var category: FeatureCategory
    /// The feature can't run without these.
    public var requiredPermissions: Set<Permission>
    /// These unlock extra abilities; the feature runs without them.
    public var optionalPermissions: Set<Permission>
    public var enabledByDefault: Bool
    public var minimumOS: OperatingSystemVersion?

    public init(
        id: FeatureID,
        name: String,
        symbol: String,
        summary: String,
        category: FeatureCategory,
        requiredPermissions: Set<Permission> = [],
        optionalPermissions: Set<Permission> = [],
        enabledByDefault: Bool = false,
        minimumOS: OperatingSystemVersion? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.summary = summary
        self.category = category
        self.requiredPermissions = requiredPermissions
        self.optionalPermissions = optionalPermissions
        self.enabledByDefault = enabledByDefault
        self.minimumOS = minimumOS
    }

    /// Whether this Mac's macOS is new enough.
    public var isSupportedOnThisOS: Bool {
        guard let minimumOS else { return true }
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumOS)
    }
}
