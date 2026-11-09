import KKitCore

enum PrivacySettings {
    static let showMic = SettingKey("showMic", default: true)
    static let showCamera = SettingKey("showCamera", default: true)
    static let showAppNames = SettingKey("showAppNames", default: true)
    /// Clicking the compact Island while the mic is in use mutes or unmutes it.
    static let clickTogglesMute = SettingKey("clickTogglesMute", default: true)
    /// Keep a 7-day log of mic and camera use, on this Mac only.
    static let keepLog = SettingKey("keepLog", default: false)
}
