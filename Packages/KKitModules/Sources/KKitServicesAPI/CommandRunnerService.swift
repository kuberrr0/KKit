import KKitCore

/// A command, as a picker lists it.
public struct CommandSummary: Hashable, Sendable, Identifiable {
    public var id: CommandID
    public var title: String
    public var symbol: String
    public var takesValue: Bool

    public init(id: CommandID, title: String, symbol: String, takesValue: Bool) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.takesValue = takesValue
    }
}

/// Runs any KKit command by id, with an optional typed value ("30", "25m"). For
/// features that let the user bind keys to commands (Keyboard's leader sequences).
@MainActor
public protocol CommandRunnerService: AnyObject, Sendable {
    /// Every command of KKit and its running features, by title.
    var commandList: [CommandSummary] { get }
    func run(_ id: CommandID, value: String?) async throws
}
