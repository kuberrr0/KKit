import KKitCore

enum PowerSettings {
    /// What "Toggle Keep Awake" does: 0 = indefinitely, otherwise minutes.
    static let defaultMinutes = SettingKey("defaultMinutes", default: 0)
    /// Keep the display on too, not just the system.
    static let keepDisplayAwake = SettingKey("keepDisplayAwake", default: true)
    static let showInIsland = SettingKey("showInIsland", default: true)
    /// Stop keeping awake when on battery below this percentage. 0 = off.
    static let batteryCutoff = SettingKey("batteryCutoff", default: 0)
    // Automatic rules
    static let awakeOnPowerAdapter = SettingKey("awakeOnPowerAdapter", default: false)
    static let awakeWithExternalDisplay = SettingKey("awakeWithExternalDisplay", default: false)
    /// Bundle ids: stay awake while any of them is running.
    static let awakeWhileApps = SettingKey("awakeWhileApps", default: [String]())
}
