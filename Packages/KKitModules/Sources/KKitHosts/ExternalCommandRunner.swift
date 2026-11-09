import Foundation
import KKitCore
import KKitServicesAPI

/// Runs commands that come from outside KKit: `kkit://` links and the *Run KKit
/// Command* App Intent (ARCHITECTURE.md §5). A value is parsed the same way as typed
/// text in the Floating Bar ("30", "25m", a choice).
@MainActor
public final class ExternalCommandRunner: CommandRunnerService {
    public enum RunError: LocalizedError, Equatable {
        case notALink
        case linksTurnedOff
        case unknownCommand(String)
        case unavailable(String)
        case badValue(String, hint: String)

        public var errorDescription: String? {
            switch self {
            case .notALink:
                String(localized: "That isn't a KKit link.")
            case .linksTurnedOff:
                String(localized: "Links can't run commands. Turn this on in Settings › General.")
            case .unknownCommand(let id):
                String(localized: "There's no KKit command “\(id)”. Its feature may be off.")
            case .unavailable(let title):
                String(localized: "“\(title)” can't run right now.")
            case .badValue(let value, let hint):
                String(localized: "“\(value)” isn't a valid value. Type \(hint).")
            }
        }
    }

    /// Set by the app at launch, for the App Intent.
    public static var shared: ExternalCommandRunner?

    private let commands: CommandRegistry
    private let settings: SettingsStore
    private let floatingBar: (any FloatingBarService)?
    private var isReady = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(commands: CommandRegistry, settings: SettingsStore, floatingBar: (any FloatingBarService)?) {
        self.commands = commands
        self.settings = settings
        self.floatingBar = floatingBar
    }

    /// Call once the enabled features have started (and registered their commands).
    public func markReady() {
        isReady = true
        let waiting = waiters
        waiters = []
        waiting.forEach { $0.resume() }
    }

    /// Returns once features have started, so a link that launched KKit finds its command.
    public func waitUntilReady() async {
        guard !isReady else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Commands that can be run from Shortcuts, by title.
    public var availableCommands: [Command] {
        commands.allCommands.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    // MARK: CommandRunnerService (for features, e.g. Keyboard's leader sequences)

    public var commandList: [CommandSummary] {
        availableCommands.map {
            CommandSummary(id: $0.id, title: $0.title, symbol: $0.symbol, takesValue: $0.parameter != nil)
        }
    }

    public func run(_ id: CommandID, value: String?) async throws {
        try await run(id, value: value, source: .hotkey)
    }

    public func handle(_ url: URL) async throws {
        guard let link = KKitLink(url) else { throw RunError.notALink }
        await waitUntilReady()
        switch link {
        case .run(let id, let value):
            guard settings.value(for: AppSettingKeys.allowLinkCommands, default: true) else {
                throw RunError.linksTurnedOff
            }
            try await run(id, value: value, source: .url)
        case .search(let query):
            floatingBar?.show(query: query)
        }
    }

    public func run(_ id: CommandID, value: String?, source: CommandSource) async throws {
        guard let command = commands.command(id) else { throw RunError.unknownCommand(id.rawValue) }
        guard command.isEnabled() else { throw RunError.unavailable(command.title) }
        var argument: CommandArgument?
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, let parameter = command.parameter {
            guard let parsed = CommandArgumentParser.parse(trimmed, for: parameter) else {
                throw RunError.badValue(trimmed, hint: CommandArgumentParser.hint(for: parameter))
            }
            argument = parsed
        }
        try await commands.perform(id, CommandInvocation(argument: argument, source: source))
    }
}
