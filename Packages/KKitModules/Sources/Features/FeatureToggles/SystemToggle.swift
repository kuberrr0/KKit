import KKitCore

/// One of the Quick Toggles. Switches have an on/off state; actions just run.
enum SystemToggle: String, CaseIterable, Codable, Sendable, Identifiable {
    case darkMode
    case hideDesktopIcons
    case hiddenFiles
    case wifi
    case dockAutohide
    case menuBarAutohide
    case ejectDisks
    case emptyTrash
    case lockScreen
    case sleepDisplays
    case screenSaver

    var id: String { rawValue }

    var commandID: CommandID { CommandID("quickToggles.\(rawValue)") }

    var isSwitch: Bool {
        switch self {
        case .darkMode, .hideDesktopIcons, .hiddenFiles, .wifi, .dockAutohide, .menuBarAutohide: true
        case .ejectDisks, .emptyTrash, .lockScreen, .sleepDisplays, .screenSaver: false
        }
    }

    /// Tile title.
    var title: String {
        switch self {
        case .darkMode: String(localized: "Dark Mode")
        case .hideDesktopIcons: String(localized: "Hide Desktop")
        case .hiddenFiles: String(localized: "Hidden Files")
        case .wifi: String(localized: "Wi-Fi")
        case .dockAutohide: String(localized: "Hide Dock")
        case .menuBarAutohide: String(localized: "Hide Menu Bar")
        case .ejectDisks: String(localized: "Eject All")
        case .emptyTrash: String(localized: "Empty Trash")
        case .lockScreen: String(localized: "Lock Screen")
        case .sleepDisplays: String(localized: "Sleep Displays")
        case .screenSaver: String(localized: "Screen Saver")
        }
    }

    /// Command title, in the Floating Bar.
    var commandTitle: String {
        switch self {
        case .darkMode: String(localized: "Toggle Dark Mode")
        case .hideDesktopIcons: String(localized: "Toggle Desktop Icons")
        case .hiddenFiles: String(localized: "Toggle Hidden Files in Finder")
        case .wifi: String(localized: "Toggle Wi-Fi")
        case .dockAutohide: String(localized: "Toggle Dock Auto-Hide")
        case .menuBarAutohide: String(localized: "Toggle Menu Bar Auto-Hide")
        case .ejectDisks: String(localized: "Eject All Disks")
        case .emptyTrash: String(localized: "Empty Trash")
        case .lockScreen: String(localized: "Lock Screen")
        case .sleepDisplays: String(localized: "Sleep Displays")
        case .screenSaver: String(localized: "Start Screen Saver")
        }
    }

    var symbol: String {
        switch self {
        case .darkMode: "circle.lefthalf.filled"
        case .hideDesktopIcons: "menubar.dock.rectangle"
        case .hiddenFiles: "eye"
        case .wifi: "wifi"
        case .dockAutohide: "dock.rectangle"
        case .menuBarAutohide: "menubar.rectangle"
        case .ejectDisks: "eject"
        case .emptyTrash: "trash"
        case .lockScreen: "lock"
        case .sleepDisplays: "display"
        case .screenSaver: "sparkles.tv"
        }
    }

    var keywords: [String] {
        switch self {
        case .darkMode: ["dark", "light", "appearance", "theme"]
        case .hideDesktopIcons: ["desktop", "icons", "clean", "presentation"]
        case .hiddenFiles: ["finder", "dotfiles", "invisible"]
        case .wifi: ["wifi", "wireless", "network", "airport"]
        case .dockAutohide: ["dock", "autohide"]
        case .menuBarAutohide: ["menu bar", "autohide"]
        case .ejectDisks: ["eject", "unmount", "drives", "usb"]
        case .emptyTrash: ["trash", "bin", "delete"]
        case .lockScreen: ["lock", "away"]
        case .sleepDisplays: ["sleep", "display", "monitor", "screen off"]
        case .screenSaver: ["screensaver"]
        }
    }

    /// Notes shown in Settings next to toggles that need more than a click.
    var note: String? {
        switch self {
        case .darkMode, .dockAutohide, .menuBarAutohide, .emptyTrash:
            String(localized: "Asks for Automation permission the first time.")
        case .hiddenFiles:
            String(localized: "Relaunches Finder.")
        default:
            nil
        }
    }
}

enum ToggleSettings {
    /// Which toggles appear in the menu bar grid, in order.
    static let tiles = SettingKey("tiles", default: [SystemToggle.darkMode, .hideDesktopIcons, .wifi, .lockScreen])
}
