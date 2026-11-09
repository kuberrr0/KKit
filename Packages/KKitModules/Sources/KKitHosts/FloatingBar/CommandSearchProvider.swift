import Foundation
import KKitCore

/// Every running feature's commands, under `>` and in root search. A command with a
/// parameter also matches with its argument typed after it: `night 150`, `awake 2h`,
/// `vol 30`, `timer 25m`.
@MainActor
public final class CommandSearchProvider: SearchProvider {
    public let id = "commands"
    public let displayName = String(localized: "Commands")
    public let symbol = "command"
    public let prefix: String? = ">"

    private let commands: CommandRegistry
    private let shortcutText: @MainActor (CommandID) -> String?
    private let ownerName: @MainActor (FeatureID) -> String
    /// Commands that make no sense from the bar (opening the bar itself).
    var hiddenCommands: Set<CommandID> = [FloatingBarCommandID.toggle]

    public init(
        commands: CommandRegistry,
        shortcutText: @escaping @MainActor (CommandID) -> String?,
        ownerName: @escaping @MainActor (FeatureID) -> String
    ) {
        self.commands = commands
        self.shortcutText = shortcutText
        self.ownerName = ownerName
    }

    public func results(for query: SearchQuery) -> AsyncStream<[SearchResult]> {
        .single(search(query))
    }

    public func search(_ query: SearchQuery) -> [SearchResult] {
        let text = query.trimmed
        let available = commands.allCommands.filter { !hiddenCommands.contains($0.id) && $0.isEnabled() }
        guard !text.isEmpty else {
            return query.isScoped ? available.map { result(for: $0, argument: nil, score: 0.5) } : []
        }
        var results: [SearchResult] = []
        for command in available {
            let keywords = command.keywords + [ownerName(command.id.featureID)]
            if let score = FuzzyMatch.score(text, title: command.title, keywords: keywords) {
                results.append(result(for: command, argument: nil, score: score))
            }
            if let parameter = command.parameter,
               let match = Self.argumentMatch(text, title: command.title, keywords: keywords, parameter: parameter) {
                results.append(result(for: command, argument: match.argument, score: match.score))
            }
        }
        return results
    }

    /// A result for `command`, with its live state or shortcut on the right.
    public func result(for command: Command, argument: CommandArgument?, score: Double) -> SearchResult {
        let title: String
        if let argument {
            title = "\(Self.trimmingEllipsis(command.title)) \(CommandArgumentParser.display(argument))"
        } else {
            title = command.title
        }
        let needsValue = command.parameter != nil && argument == nil
        return SearchResult(
            id: Self.resultID(command.id, argument: argument),
            title: title,
            subtitle: command.subtitle ?? ownerName(command.id.featureID),
            icon: .symbol(command.symbol),
            score: score,
            kind: .command(command.id, argument: argument),
            accessory: accessory(for: command),
            actionTitle: needsValue ? String(localized: "Enter Value") : String(localized: "Run")
        )
    }

    /// The same command again, by id (Favourites and Recent), with fresh state.
    public func result(id: CommandID, argument: CommandArgument?, score: Double = 1) -> SearchResult? {
        guard let command = commands.command(id) else { return nil }
        return result(for: command, argument: argument, score: score)
    }

    static func resultID(_ id: CommandID, argument: CommandArgument?) -> String {
        guard let argument else { return "command:\(id.rawValue)" }
        return "command:\(id.rawValue)=\(CommandArgumentParser.display(argument))"
    }

    /// Splits "night shift 150" into a head that names the command and a tail that
    /// parses as its argument. Structured arguments (percent, duration, choice) rank a
    /// little above free text.
    static func argumentMatch(
        _ text: String,
        title: String,
        keywords: [String],
        parameter: CommandParameter
    ) -> (argument: CommandArgument, score: Double)? {
        let words = text.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }
        var best: (argument: CommandArgument, score: Double)?
        for split in 1..<words.count {
            let head = words[..<split].joined(separator: " ")
            let tail = words[split...].joined(separator: " ")
            guard let argument = CommandArgumentParser.parse(tail, for: parameter),
                  let score = FuzzyMatch.score(head, title: title, keywords: keywords),
                  score >= 0.6
            else { continue }
            var weighted = score
            if case .text = parameter {
                weighted *= 0.9
            } else {
                weighted *= 0.97
            }
            if weighted > (best?.score ?? 0) {
                best = (argument, weighted)
            }
            // Free text: the shortest head that names the command wins.
            if case .text = parameter {
                break
            }
        }
        return best
    }

    static func trimmingEllipsis(_ title: String) -> String {
        var trimmed = title
        while trimmed.hasSuffix("…") || trimmed.hasSuffix(".") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func accessory(for command: Command) -> String? {
        if let state = command.state?() {
            switch state {
            case .on: return String(localized: "On")
            case .value(let text): return text
            case .off: break
            }
        }
        return shortcutText(command.id)
    }
}
