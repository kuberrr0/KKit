import Foundation

/// What kind of argument a command takes, typed inline in the Floating Bar
/// (`night 150`) or passed by URL (`?value=150`).
public enum CommandParameter: Sendable, Hashable {
    case percent(default: Double)
    case duration(default: Duration)
    case text(placeholder: String)
    case choice([String])
}

/// A parsed argument. `CommandArgumentParser` turns typed text into one.
public enum CommandArgument: Sendable, Hashable, Codable {
    case percent(Double)
    case duration(Duration)
    case text(String)
    case choice(String)
}

/// Where a command was run from.
public enum CommandSource: Sendable, Hashable {
    case hotkey
    case menuBar
    case floatingBar
    case settings
    case url
    case intent
    case other
}

public struct CommandInvocation: Sendable {
    public var argument: CommandArgument?
    public var source: CommandSource

    public init(argument: CommandArgument? = nil, source: CommandSource = .other) {
        self.argument = argument
        self.source = source
    }

    public var percent: Double? {
        if case .percent(let value) = argument { value } else { nil }
    }

    public var duration: Duration? {
        if case .duration(let value) = argument { value } else { nil }
    }

    public var text: String? {
        switch argument {
        case .text(let value), .choice(let value): value
        default: nil
        }
    }
}

/// Live state shown on toggle tiles and Floating Bar results.
public enum CommandState: Sendable, Hashable {
    case on
    case off
    /// On, with a short detail: "1h 20m", "70%".
    case value(String)

    public var isOn: Bool { self != .off }
}

/// One user action. Defined once by a feature; the hosts turn it into a Floating Bar
/// result, a bindable hotkey, a URL (`kkit://run/<id>`) and a Shortcuts.app action.
public struct Command: Identifiable, Sendable {
    public typealias Perform = @MainActor @Sendable (CommandInvocation) async throws -> Void

    public let id: CommandID
    public var title: String
    public var subtitle: String?
    public var symbol: String
    /// Extra search terms.
    public var keywords: [String]
    /// `nil` means unbound until the user records a shortcut.
    public var defaultShortcut: Shortcut?
    public var parameter: CommandParameter?
    public var isEnabled: @MainActor @Sendable () -> Bool
    public var state: (@MainActor @Sendable () -> CommandState)?
    public var perform: Perform

    public init(
        id: CommandID,
        title: String,
        subtitle: String? = nil,
        symbol: String,
        keywords: [String] = [],
        defaultShortcut: Shortcut? = nil,
        parameter: CommandParameter? = nil,
        isEnabled: @escaping @MainActor @Sendable () -> Bool = { true },
        state: (@MainActor @Sendable () -> CommandState)? = nil,
        perform: @escaping Perform
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.keywords = keywords
        self.defaultShortcut = defaultShortcut
        self.parameter = parameter
        self.isEnabled = isEnabled
        self.state = state
        self.perform = perform
    }
}
