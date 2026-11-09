import KKitCore

/// What shows the hidden icons besides a click on the chevron.
enum RevealTrigger: String, Codable, CaseIterable, Sendable {
    case click
    case hover

    var title: String {
        switch self {
        case .click: String(localized: "Clicking the chevron")
        case .hover: String(localized: "Pointing at the chevron")
        }
    }
}

/// Where hidden icons appear.
enum OpenStyle: String, Codable, CaseIterable, Sendable {
    /// The drop-down bar on screens with a notch (icons would hide behind it), in the
    /// menu bar otherwise.
    case automatic
    case dropDownBar
    case inPlace

    var title: String {
        switch self {
        case .automatic: String(localized: "Drop-down bar on screens with a notch")
        case .dropDownBar: String(localized: "Always in the drop-down bar")
        case .inPlace: String(localized: "Always in the menu bar")
        }
    }
}

enum MenuBarManagerSettings {
    static let revealOn = SettingKey("revealOn", default: RevealTrigger.click)
    static let openStyle = SettingKey("openStyle", default: OpenStyle.automatic)
    /// Seconds until hidden icons hide again; 0 keeps them until the chevron is clicked.
    static let autoHideDelay = SettingKey("autoHideDelay", default: 10)
    /// Holding ⌘ with the pointer on the menu bar shows every icon, to ⌘-drag them.
    static let showAllWithCommand = SettingKey("showAllWithCommand", default: true)
    static let alwaysHiddenSection = SettingKey("alwaysHiddenSection", default: true)
    /// Pictures of the icons in the drop-down bar (needs Screen Recording); app icons otherwise.
    static let showsIconImages = SettingKey("showsIconImages", default: true)

    static let autoHideChoices = [0, 5, 10, 15, 30, 60]
}
