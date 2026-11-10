import Foundation
import KKitCore
import Observation

/// A provider the Floating Bar can ask.
public struct ProviderEntry {
    /// "<owner>.<provider id>", used for the on/off setting.
    public let key: String
    public let owner: FeatureID
    public let provider: any SearchProvider
    /// Root search weight (1 for most; files count less).
    public let weight: Double

    @MainActor
    public init(owner: FeatureID, provider: any SearchProvider, weight: Double = 1) {
        self.key = "\(owner.rawValue).\(provider.id)"
        self.owner = owner
        self.provider = provider
        self.weight = weight
    }
}

/// A feature's mode the Floating Bar can switch into.
public struct ModeEntry {
    public let key: String
    public let owner: FeatureID
    public let mode: FloatingBarMode

    public init(owner: FeatureID, mode: FloatingBarMode) {
        self.key = "\(owner.rawValue).\(mode.id)"
        self.owner = owner
        self.mode = mode
    }
}

/// What the running features contribute right now.
public struct FloatingBarSources {
    public var providers: [ProviderEntry]
    public var modes: [ModeEntry]

    public init(providers: [ProviderEntry] = [], modes: [ModeEntry] = []) {
        self.providers = providers
        self.modes = modes
    }
}

/// One row in the list.
public struct FloatingBarRow: Identifiable {
    public enum Section: String, Sendable {
        case favourites
        case recent

        public var title: String {
            switch self {
            case .favourites: String(localized: "Favourites")
            case .recent: String(localized: "Recent")
            }
        }
    }

    public let result: SearchResult
    public let section: Section?

    public var id: String {
        guard let section else { return result.id }
        return "\(section.rawValue):\(result.id)"
    }
}

/// A command waiting for its argument: the bar shows it as a chip and the field takes
/// the value.
public struct PendingArgument: Sendable, Equatable {
    public var commandID: CommandID
    public var title: String
    public var symbol: String
    public var parameter: CommandParameter

    public var hint: String { CommandArgumentParser.hint(for: parameter) }
}

/// A feature's mode filling the bar.
public struct ActiveMode: Identifiable {
    public let id = UUID()
    public let key: String
    public let owner: FeatureID
    public let mode: FloatingBarMode
    public let text: String
    /// Opened from search (a prefix, or a result run in the bar), so ⎋ goes back there.
    /// Opened straight from a hotkey or menu, ⎋ closes the bar.
    public let returnsToSearch: Bool
}

/// The Floating Bar's state and query engine, free of AppKit so it can be tested:
/// routing by prefix, fan-out to providers with a 50 ms first-paint deadline,
/// ranking, keyboard selection, the ⌘K action list, inline command arguments, modes,
/// Favourites and Recent.
@MainActor
@Observable
public final class FloatingBarModel {
    public var query = "" {
        didSet {
            if query != oldValue {
                queryChanged()
            }
        }
    }

    public private(set) var rows: [FloatingBarRow] = []
    public private(set) var selection = 0
    public private(set) var route: QueryRoute = .empty
    public private(set) var pending: PendingArgument?
    public private(set) var activeMode: ActiveMode?
    public private(set) var actionsShown = false
    public private(set) var currentActions: [ResultAction] = []
    public private(set) var actionSelection = 0
    public var showsPreview = false
    /// A hint or error shown above the results.
    public var message: String?
    /// Bumped when the search field should take focus again.
    public private(set) var focusToken = 0
    /// Whether a search is still waiting for slow providers.
    public private(set) var isSearching = false

    public var history = FloatingBarHistory() {
        didSet {
            guard history != oldValue else { return }
            onHistoryChange?(history)
            if isEmptyState {
                rows = emptyRows()
                clampSelection()
            }
        }
    }

    // ── Wiring (set by the host) ─────────────────────────────────────────────
    @ObservationIgnored public var sources: @MainActor () -> FloatingBarSources = { FloatingBarSources() }
    @ObservationIgnored public var isProviderEnabled: @MainActor (String) -> Bool = { _ in true }
    @ObservationIgnored public var showRecents: @MainActor () -> Bool = { true }
    @ObservationIgnored public var actionsFor: @MainActor (SearchResult) -> [ResultAction] = { _ in [] }
    /// Runs a result: (result, keep the bar open).
    @ObservationIgnored public var onRun: (@MainActor (SearchResult, Bool) -> Void)?
    @ObservationIgnored public var onAction: (@MainActor (ResultAction, SearchResult) -> Void)?
    @ObservationIgnored public var onHistoryChange: (@MainActor (FloatingBarHistory) -> Void)?
    @ObservationIgnored public var paintDeadline: Duration = .milliseconds(50)
    @ObservationIgnored public var resultLimit = 40
    /// A prefix with nothing after it lists a whole source (`a ` lists every app).
    @ObservationIgnored public var scopedResultLimit = 300

    public let commandProvider: CommandSearchProvider
    private let commands: CommandRegistry
    @ObservationIgnored private var searchTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var batches: [String: ProviderBatch] = [:]
    @ObservationIgnored private var expected: Set<String> = []
    @ObservationIgnored private var responded: Set<String> = []
    @ObservationIgnored private var painted = false
    @ObservationIgnored private var rankingText = ""
    @ObservationIgnored private var currentLimit = 40
    /// The row the user moved to, kept while late providers fill in.
    @ObservationIgnored private var chosenRowID: String?
    @ObservationIgnored private var isSettingQuery = false

    public init(commands: CommandRegistry, commandProvider: CommandSearchProvider) {
        self.commands = commands
        self.commandProvider = commandProvider
    }

    // MARK: Reading

    public var selectedResult: SearchResult? {
        rows.indices.contains(selection) ? rows[selection].result : nil
    }

    public var selectedAction: ResultAction? {
        currentActions.indices.contains(actionSelection) ? currentActions[actionSelection] : nil
    }

    /// Nothing typed: Favourites and Recent.
    public var isEmptyState: Bool {
        route == .empty && pending == nil && activeMode == nil
    }

    /// The provider a prefix scoped the search to.
    public var scopedProvider: ProviderEntry? {
        guard case .scoped(let key, _) = route else { return nil }
        return sources().providers.first { $0.key == key }
    }

    // MARK: Lifecycle

    /// Back to an empty bar (after it has been hidden for a while).
    public func reset() {
        cancelSearch()
        pending = nil
        activeMode = nil
        actionsShown = false
        showsPreview = false
        message = nil
        setQuerySilently("")
        route = .empty
        rows = emptyRows()
        selection = 0
        chosenRowID = nil
    }

    /// Runs the current query again (the bar was reopened; states may have changed).
    public func refresh() {
        guard activeMode == nil else { return }
        queryChanged()
    }

    public func requestFocus() {
        focusToken &+= 1
    }

    // MARK: Selection

    public func moveSelection(_ delta: Int) {
        if actionsShown {
            guard !currentActions.isEmpty else { return }
            actionSelection = min(max(actionSelection + delta, 0), currentActions.count - 1)
            return
        }
        guard !rows.isEmpty else { return }
        selection = min(max(selection + delta, 0), rows.count - 1)
        chosenRowID = rows[selection].id
    }

    public func select(_ rowID: String) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        selection = index
        chosenRowID = rowID
    }

    // MARK: Actions (⌘K)

    public func toggleActions() {
        if actionsShown {
            closeActions()
            return
        }
        guard let result = selectedResult else { return }
        let actions = actionsFor(result)
        guard !actions.isEmpty else { return }
        currentActions = actions
        actionSelection = 0
        actionsShown = true
    }

    public func closeActions() {
        actionsShown = false
        currentActions = []
    }

    public func selectAction(_ id: String) {
        if let index = currentActions.firstIndex(where: { $0.id == id }) {
            actionSelection = index
        }
    }

    // MARK: Running

    /// ↵ (or ⌘↵ with `keepOpen`): runs the selected action or result.
    public func activateSelection(keepOpen: Bool) {
        if actionsShown {
            let action = selectedAction
            let result = selectedResult
            closeActions()
            if let action, let result {
                onAction?(action, result)
            }
            return
        }
        guard let result = selectedResult else { return }
        activate(result, keepOpen: keepOpen)
    }

    /// Runs `result`, or asks for its argument first if it's a command that takes one.
    public func activate(_ result: SearchResult, keepOpen: Bool) {
        if pending == nil,
           result.perform == nil,
           case .command(let id, .none) = result.kind,
           let command = commands.command(id),
           let parameter = command.parameter {
            beginArgument(PendingArgument(
                commandID: id,
                title: command.title,
                symbol: command.symbol,
                parameter: parameter
            ))
            return
        }
        history.recordRun(result, query: rankingText)
        onRun?(result, keepOpen)
        if pending != nil {
            pending = nil
            setQuerySilently("")
            queryChanged()
        }
    }

    public func toggleFavourite(_ result: SearchResult) {
        history.toggleFavourite(result)
    }

    public func removeRecent(_ id: String) {
        history.removeRecent(id)
    }

    // MARK: Arguments

    public func beginArgument(_ argument: PendingArgument) {
        cancelSearch()
        closeActions()
        pending = argument
        setQuerySilently("")
        route = .empty
        argumentRows(argument)
        requestFocus()
    }

    public func cancelArgument() {
        guard pending != nil else { return }
        pending = nil
        setQuerySilently("")
        queryChanged()
    }

    // MARK: Modes

    /// Opens a mode by key ("quickNote.editor"). `returnsToSearch`: ⎋ goes back to
    /// search instead of closing the bar.
    public func openMode(key: String, text: String, returnsToSearch: Bool = false) {
        guard let entry = sources().modes.first(where: { $0.key == key }) else { return }
        enterMode(entry, text: text, returnsToSearch: returnsToSearch)
    }

    public func exitMode() {
        guard activeMode != nil else { return }
        activeMode = nil
        route = .empty
        rows = emptyRows()
        selection = 0
        requestFocus()
    }

    // MARK: Query

    private func queryChanged() {
        guard !isSettingQuery else { return }
        closeActions()
        message = nil
        if let pending {
            argumentRows(pending)
            return
        }
        let current = sources()
        let enabled = current.providers.filter { isProviderEnabled($0.key) }
        let providerPrefixes = enabled.compactMap { entry in
            entry.provider.prefix.map { PrefixTarget(key: entry.key, prefix: $0) }
        }
        let modePrefixes = current.modes.compactMap { entry in
            entry.mode.prefix.map { PrefixTarget(key: entry.key, prefix: $0) }
        }
        let newRoute = QueryRouter.route(query, providers: providerPrefixes, modes: modePrefixes)
        switch newRoute {
        case .mode(let key, let text):
            if let entry = current.modes.first(where: { $0.key == key }) {
                enterMode(entry, text: text, returnsToSearch: true)
            }
        case .empty:
            route = .empty
            cancelSearch()
            rankingText = ""
            rows = emptyRows()
            selection = 0
            chosenRowID = nil
        case .root(let text):
            route = newRoute
            let rootProviders = enabled.filter { $0.provider.includeInRootSearch }
            search(rootProviders, query: SearchQuery(text: text, isScoped: false), scoped: false)
        case .scoped(let key, let text):
            route = newRoute
            search(enabled.filter { $0.key == key }, query: SearchQuery(text: text, isScoped: true), scoped: true)
        }
    }

    private func search(_ entries: [ProviderEntry], query: SearchQuery, scoped: Bool) {
        cancelSearch()
        generation &+= 1
        let current = generation
        batches = [:]
        expected = Set(entries.map(\.key))
        responded = []
        painted = false
        chosenRowID = nil
        rankingText = query.text
        currentLimit = scoped ? max(resultLimit, scopedResultLimit) : resultLimit
        guard !entries.isEmpty else {
            rows = []
            selection = 0
            return
        }
        isSearching = true
        for (order, entry) in entries.enumerated() {
            let stream = entry.provider.results(for: query)
            let key = entry.key
            let weight = scoped ? 1 : entry.weight
            searchTasks.append(Task { [weak self] in
                for await results in stream {
                    guard let self, self.generation == current else { return }
                    self.receive(ProviderBatch(key: key, order: order, weight: weight, results: results))
                }
                guard let self, self.generation == current else { return }
                self.providerFinished(key)
            })
        }
        let deadline = paintDeadline
        searchTasks.append(Task { [weak self] in
            try? await Task.sleep(for: deadline)
            guard !Task.isCancelled, let self, self.generation == current, !self.painted else { return }
            self.paint()
        })
    }

    private func receive(_ batch: ProviderBatch) {
        batches[batch.key] = batch
        responded.insert(batch.key)
        if painted || responded.isSuperset(of: expected) {
            paint()
        }
    }

    private func providerFinished(_ key: String) {
        responded.insert(key)
        if responded.isSuperset(of: expected) {
            isSearching = false
            if !painted {
                paint()
            }
        }
    }

    private func paint() {
        painted = true
        let ranked = ResultRanker.rank(
            Array(batches.values),
            query: rankingText,
            frecency: history.frecency,
            limit: currentLimit
        )
        rows = ranked.map { FloatingBarRow(result: $0, section: nil) }
        if let chosen = chosenRowID, let index = rows.firstIndex(where: { $0.id == chosen }) {
            selection = index
        } else {
            selection = 0
        }
    }

    private func cancelSearch() {
        searchTasks.forEach { $0.cancel() }
        searchTasks = []
        generation &+= 1
        isSearching = false
    }

    private func setQuerySilently(_ text: String) {
        isSettingQuery = true
        query = text
        isSettingQuery = false
    }

    private func clampSelection() {
        if selection >= rows.count {
            selection = max(rows.count - 1, 0)
        }
    }

    private func enterMode(_ entry: ModeEntry, text: String, returnsToSearch: Bool) {
        cancelSearch()
        closeActions()
        activeMode = ActiveMode(key: entry.key, owner: entry.owner, mode: entry.mode, text: text, returnsToSearch: returnsToSearch)
        route = .mode(modeKey: entry.key, text: text)
        setQuerySilently("")
        rows = []
        selection = 0
    }

    // MARK: Rows

    /// Favourites, then Recent (without the favourites).
    func emptyRows() -> [FloatingBarRow] {
        let favourites = history.favourites.compactMap { resolve($0) }.map {
            FloatingBarRow(result: $0, section: .favourites)
        }
        guard showRecents() else { return favourites }
        let favouriteIDs = Set(history.favourites.map(\.id))
        let recents = history.recents
            .filter { !favouriteIDs.contains($0.id) }
            .compactMap { resolve($0) }
            .map { FloatingBarRow(result: $0, section: .recent) }
        return favourites + recents
    }

    /// A saved result, refreshed: commands get their current title and state, and
    /// files that are gone (or commands whose feature is off) are skipped.
    func resolve(_ stored: StoredResult) -> SearchResult? {
        switch stored.kind {
        case .command(let id, let argument):
            return commandProvider.result(id: id, argument: argument)
        case .application(let url), .file(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return stored.makeResult()
        default:
            return stored.makeResult()
        }
    }

    private func argumentRows(_ argument: PendingArgument) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        message = nil
        var results: [SearchResult] = []
        switch argument.parameter {
        case .choice(let choices):
            let matching = text.isEmpty ? choices : choices.filter { FuzzyMatch.score(text, in: $0) != nil }
            results = matching.compactMap { commandProvider.result(id: argument.commandID, argument: .choice($0)) }
            if results.isEmpty {
                message = argument.hint
            }
        case .text:
            if text.isEmpty {
                message = argument.hint
            } else if let value = CommandArgumentParser.parse(text, for: argument.parameter),
                      let result = commandProvider.result(id: argument.commandID, argument: value) {
                results = [result]
            }
        case .percent, .duration:
            if text.isEmpty {
                if var result = commandProvider.result(id: argument.commandID, argument: nil) {
                    result.title = String(localized: "\(CommandSearchProvider.trimmingEllipsis(argument.title)) (default)")
                    result.actionTitle = String(localized: "Run")
                    results = [result]
                }
            } else if let value = CommandArgumentParser.parse(text, for: argument.parameter),
                      let result = commandProvider.result(id: argument.commandID, argument: value) {
                results = [result]
            } else {
                message = String(localized: "Type \(argument.hint.lowercased()).")
            }
        }
        rows = results.map { FloatingBarRow(result: $0, section: nil) }
        selection = 0
    }
}
