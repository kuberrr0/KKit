import KKitCore

/// Where the Floating Bar opens.
public enum FloatingBarPlacement: String, Codable, Sendable, CaseIterable {
    /// Upper middle of the screen with the pointer.
    case center
    /// Just below the menu bar.
    case top
}

/// The Floating Bar host's settings, stored as `floatingBar.<name>`.
public enum FloatingBarSettings {
    static let owner: FeatureID = "floatingBar"

    public static let placement = SettingKey("placement", default: FloatingBarPlacement.center)
    /// Reopening within 30 s brings back the last query.
    public static let rememberQuery = SettingKey("rememberQuery", default: true)
    public static let showRecents = SettingKey("showRecents", default: true)
    /// Provider keys ("<owner>.<id>") the user switched off.
    public static let disabledProviders = SettingKey("disabledProviders", default: [String]())
}

/// The Floating Bar's own command ids.
public enum FloatingBarCommandID {
    public static let toggle: CommandID = "floatingBar.toggle"
    public static let searchCommands: CommandID = "floatingBar.searchCommands"
}
