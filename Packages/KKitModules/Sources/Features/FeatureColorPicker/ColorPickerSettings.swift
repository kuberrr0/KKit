import KKitCore

enum ColorPickerSettings {
    /// How a picked colour is copied.
    static let format = SettingKey("format", default: ColorFormat.hex)
    /// `#ff8800` instead of `#FF8800`.
    static let lowercaseHex = SettingKey("lowercaseHex", default: false)
    /// The picked colour shows in the Island for a moment.
    static let showInIsland = SettingKey("showInIsland", default: true)
    /// A Colours page in the expanded Island.
    static let showIslandPage = SettingKey("showIslandPage", default: true)
    /// Newest first, as `#RRGGBB` (or `#RRGGBBAA`).
    static let history = SettingKey("history", default: [String]())

    static let maxHistory = 24
}
