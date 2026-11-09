import KKitCore

/// Which displays show the Island.
public enum IslandDisplays: String, Codable, Sendable, CaseIterable {
    /// The built-in display (with the notch), or the main display if it's closed.
    case builtIn
    /// The display with the menu bar.
    case main
    case all
}

/// The Island host's settings, stored as `island.<name>`.
public enum IslandSettings {
    static let owner: FeatureID = "island"

    public static let enabled = SettingKey("enabled", default: true)
    public static let expandOnHover = SettingKey("expandOnHover", default: true)
    /// Seconds the pointer rests on the Island before it expands.
    public static let hoverDelay = SettingKey("hoverDelay", default: 0.3)
    public static let displays = SettingKey("displays", default: IslandDisplays.builtIn)
    public static let showInFullScreen = SettingKey("showInFullScreen", default: false)
}
