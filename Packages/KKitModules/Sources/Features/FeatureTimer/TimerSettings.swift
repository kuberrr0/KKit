import KKitCore

enum TimerSettings {
    /// "Start Timer" without a duration, and the tile.
    static let defaultMinutes = SettingKey("defaultMinutes", default: 5.0)
    // Alerts
    /// A system sound name ("Glass"); empty for none.
    static let sound = SettingKey("sound", default: "Glass")
    /// Also post a system notification when a timer ends.
    static let notify = SettingKey("notify", default: false)
    static let showInIsland = SettingKey("showInIsland", default: true)
}
