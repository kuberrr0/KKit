import AppIntents
import KKitCore
import KKitHosts

/// A KKit command, as Shortcuts shows it.
struct KKitCommandEntity: AppEntity, Sendable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "KKit Command")
    }

    static let defaultQuery = KKitCommandQuery()

    let id: String
    let title: String
    let subtitle: String?

    var displayRepresentation: DisplayRepresentation {
        if let subtitle {
            return DisplayRepresentation(
                title: LocalizedStringResource(stringLiteral: title),
                subtitle: LocalizedStringResource(stringLiteral: subtitle)
            )
        }
        return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: title))
    }

    init(_ command: Command) {
        id = command.id.rawValue
        title = command.title
        subtitle = command.subtitle
    }
}

/// Every registered command, searchable by title.
struct KKitCommandQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [KKitCommandEntity] {
        await MainActor.run {
            let commands = ExternalCommandRunner.shared?.availableCommands ?? []
            return commands.filter { identifiers.contains($0.id.rawValue) }.map { KKitCommandEntity($0) }
        }
    }

    func entities(matching string: String) async throws -> [KKitCommandEntity] {
        await MainActor.run {
            let commands = ExternalCommandRunner.shared?.availableCommands ?? []
            return commands
                .filter { FuzzyMatch.score(string, title: $0.title, keywords: $0.keywords) != nil }
                .map { KKitCommandEntity($0) }
        }
    }

    func suggestedEntities() async throws -> [KKitCommandEntity] {
        await MainActor.run {
            (ExternalCommandRunner.shared?.availableCommands ?? []).map { KKitCommandEntity($0) }
        }
    }
}

/// *Run KKit Command*: runs any command, with an optional value parsed like typed text
/// ("30%", "25m", a choice). ARCHITECTURE.md §5.
struct RunKKitCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run KKit Command"

    static var description: IntentDescription {
        IntentDescription("Runs a KKit command, like turning on Night Shift or starting a 25-minute timer.")
    }

    static let openAppWhenRun = false

    @Parameter(title: "Command")
    var command: KKitCommandEntity

    @Parameter(title: "Value", description: "For commands that take one: a percentage, a duration like 25m, a choice or text.")
    var value: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$command)") {
            \.$value
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let runner = ExternalCommandRunner.shared else {
            throw ExternalCommandRunner.RunError.unknownCommand(command.id)
        }
        await runner.waitUntilReady()
        try await runner.run(CommandID(command.id), value: value, source: .intent)
        return .result()
    }
}
