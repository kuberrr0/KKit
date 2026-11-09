import Foundation

/// A tile in the menu bar popover grid. A thin wrapper around a command with a state,
/// so the tile, the Floating Bar result and the hotkey all stay in sync.
public struct QuickToggle: Identifiable, Sendable {
    public var command: Command

    public init(_ command: Command) {
        self.command = command
    }

    public var id: CommandID { command.id }
    public var title: String { command.title }
    public var symbol: String { command.symbol }

    /// Reads the command's live state; `.off` if it has none.
    @MainActor
    public var state: CommandState { command.state?() ?? .off }
}
