import KKitCore

enum TimerSettings {
    /// "Start Timer" without a duration, and the tile.
    static let defaultMinutes = SettingKey("defaultMinutes", default: 5.0)
    // Pomodoro
    static let workMinutes = SettingKey("workMinutes", default: 25.0)
    static let shortBreakMinutes = SettingKey("shortBreakMinutes", default: 5.0)
    static let longBreakMinutes = SettingKey("longBreakMinutes", default: 15.0)
    /// A long break after this many work intervals.
    static let longBreakEvery = SettingKey("longBreakEvery", default: 4)
    /// Start the next Pomodoro interval automatically.
    static let autoStartNext = SettingKey("autoStartNext", default: true)
    // Alerts
    /// A system sound name ("Glass"); empty for none.
    static let sound = SettingKey("sound", default: "Glass")
    /// Also post a system notification when a timer ends.
    static let notify = SettingKey("notify", default: false)
    static let showInIsland = SettingKey("showInIsland", default: true)
}
