import CoreGraphics
import KKitCore

/// The modifier held with Tab to open the switcher.
enum SwitcherModifier: String, Codable, CaseIterable, Sendable {
    /// ⌘Tab, replacing macOS's app switcher.
    case command
    case option
    case control

    var modifiers: Shortcut.Modifiers {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        }
    }

    var title: String {
        switch self {
        case .command: String(localized: "⌘ Tab (replaces the app switcher)")
        case .option: String(localized: "⌥ Tab")
        case .control: String(localized: "⌃ Tab")
        }
    }
}

/// How big the window previews are.
enum PreviewSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large

    /// A tile's width in points, before it's shrunk to fit many windows on screen.
    var tileWidth: CGFloat {
        switch self {
        case .small: 170
        case .medium: 230
        case .large: 310
        }
    }

    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }
}

enum WindowSwitcherSettings {
    /// Modifier + Tab opens the switcher. Off: only the `windowSwitcher.show` command does.
    static let takeOverShortcut = SettingKey("takeOverShortcut", default: true)
    static let modifier = SettingKey("modifier", default: SwitcherModifier.command)
    static let includeMinimized = SettingKey("includeMinimized", default: true)
    static let includeHiddenApps = SettingKey("includeHiddenApps", default: true)
    /// Apps that are running with no window on this Space (like ⌘Tab shows them).
    static let includeAppsWithoutWindows = SettingKey("includeAppsWithoutWindows", default: true)
    /// Live pictures of the windows (needs Screen Recording); app icons otherwise.
    static let showPreviews = SettingKey("showPreviews", default: true)
    static let previewSize = SettingKey("previewSize", default: PreviewSize.medium)
}
