import KKitCore
import SwiftUI

/// Global keyboard shortcuts for commands.
///
/// It watches the `CommandRegistry`: when a command is registered its shortcut (the
/// user's, or the command's default) becomes active; when its feature stops, it's
/// released. Features never register hotkeys themselves.
@MainActor
public protocol HotkeyService: AnyObject {
    func shortcut(for command: CommandID) -> Shortcut?
    func setShortcut(_ shortcut: Shortcut?, for command: CommandID)
    /// Back to the command's default shortcut (or none).
    func resetShortcut(for command: CommandID)
    /// Other commands bound to the same shortcut.
    func conflicts(for command: CommandID) -> [CommandID]
    /// "⌥Space"
    func displayString(for shortcut: Shortcut) -> String
    /// A shortcut recorder control for Settings.
    func recorder(for command: CommandID) -> AnyView
}
