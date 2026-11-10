import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import SwiftUI
import Testing
@testable import KKitHosts

private func result(_ id: String, _ title: String, score: Double = 0.8, fallback: Bool = false) -> SearchResult {
    SearchResult(id: id, title: title, icon: .symbol("circle"), score: score, kind: .text(title), isFallback: fallback)
}

/// Waits for main-actor stream deliveries.
@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
final class FakeSearchProvider: SearchProvider {
    let id: String
    let displayName = "Fake"
    let symbol = "circle"
    let prefix: String?
    var includeInRootSearch = true
    var items: [SearchResult]
    private(set) var queries: [SearchQuery] = []

    init(id: String = "fake", prefix: String? = nil, items: [SearchResult]) {
        self.id = id
        self.prefix = prefix
        self.items = items
    }

    func results(for query: SearchQuery) -> AsyncStream<[SearchResult]> {
        queries.append(query)
        let matches = query.isEmpty ? items : items.filter { FuzzyMatch.score(query.text, in: $0.title) != nil }
        return .single(matches)
    }
}

/// Answers after the first-paint deadline, like the app index on its first scan.
@MainActor
final class SlowSearchProvider: SearchProvider {
    let id = "slow"
    let displayName = "Slow"
    let symbol = "tortoise"
    let prefix: String? = "s "
    let items: [SearchResult]

    init(items: [SearchResult]) {
        self.items = items
    }

    func results(for query: SearchQuery) -> AsyncStream<[SearchResult]> {
        let items = items
        return .task {
            try? await Task.sleep(for: .milliseconds(150))
            return items
        }
    }
}

struct QueryRouterTests {
    private let providers = [
        PrefixTarget(key: "search.files", prefix: "f "),
        PrefixTarget(key: "search.web", prefix: "w "),
        PrefixTarget(key: "floatingBar.commands", prefix: ">"),
        PrefixTarget(key: "calculator.calculator", prefix: "="),
    ]
    private let modes = [PrefixTarget(key: "quickNote.editor", prefix: "n ")]

    @Test func routesByPrefix() {
        #expect(QueryRouter.route("", providers: providers, modes: modes) == .empty)
        #expect(QueryRouter.route("   ", providers: providers, modes: modes) == .empty)
        #expect(QueryRouter.route("safari", providers: providers, modes: modes) == .root("safari"))
        #expect(QueryRouter.route("f report", providers: providers, modes: modes) == .scoped(providerKey: "search.files", text: "report"))
        #expect(QueryRouter.route("F  report", providers: providers, modes: modes) == .scoped(providerKey: "search.files", text: "report"))
        #expect(QueryRouter.route(">night", providers: providers, modes: modes) == .scoped(providerKey: "floatingBar.commands", text: "night"))
        #expect(QueryRouter.route("=2+2", providers: providers, modes: modes) == .scoped(providerKey: "calculator.calculator", text: "2+2"))
        #expect(QueryRouter.route("n buy milk", providers: providers, modes: modes) == .mode(modeKey: "quickNote.editor", text: "buy milk"))
        // "f" alone or "files" isn't the "f " prefix.
        #expect(QueryRouter.route("files", providers: providers, modes: modes) == .root("files"))
    }
}

struct ResultRankerTests {
    @Test func mergesDeduplicatesAndPutsFallbacksLast() {
        let batches = [
            ProviderBatch(key: "a", order: 0, results: [result("x", "X", score: 0.6), result("web", "Search", score: 0.9, fallback: true)]),
            ProviderBatch(key: "b", order: 1, results: [result("y", "Y", score: 0.9), result("x", "X again", score: 0.7)]),
        ]
        let ranked = ResultRanker.rank(batches, query: "x", frecency: FrecencyStore())
        #expect(ranked.map(\.id) == ["y", "x", "web"])
        #expect(ranked[1].title == "X again")
    }

    @Test func weightsAndTiesFollowProviderOrder() {
        let batches = [
            ProviderBatch(key: "files", order: 1, weight: 0.5, results: [result("f", "F", score: 1)]),
            ProviderBatch(key: "apps", order: 0, results: [result("a", "A", score: 0.5)]),
        ]
        let ranked = ResultRanker.rank(batches, query: "", frecency: FrecencyStore())
        #expect(ranked.map(\.id) == ["a", "f"])
    }

    @Test func frecencyLiftsWhatYouPick() {
        var frecency = FrecencyStore()
        let now = Date()
        frecency.record(id: "safari", query: "sa", at: now)
        frecency.record(id: "safari", query: "sa", at: now)
        let batches = [ProviderBatch(key: "apps", order: 0, results: [
            result("sandbox", "Sandbox", score: 0.92),
            result("safari", "Safari", score: 0.9),
        ])]
        let ranked = ResultRanker.rank(batches, query: "sa", frecency: frecency, now: now)
        #expect(ranked.first?.id == "safari")
        // Typing less than what was picked still helps.
        #expect(frecency.boost(id: "safari", query: "s", now: now) > frecency.boost(id: "sandbox", query: "s", now: now))
    }
}

struct FloatingBarHistoryTests {
    @Test func recentsAreUniqueNewestFirstAndCapped() {
        var history = FloatingBarHistory()
        for index in 0..<10 {
            history.recordRun(result("r\(index)", "R\(index)"), query: "")
        }
        history.recordRun(result("r5", "R5"), query: "")
        #expect(history.recents.count == FloatingBarHistory.maxRecents)
        #expect(history.recents.first?.id == "r5")
        #expect(Set(history.recents.map(\.id)).count == history.recents.count)
    }

    @Test func customResultsAreNotStored() {
        var history = FloatingBarHistory()
        let custom = SearchResult(id: "c", title: "C", icon: .symbol("circle"), score: 1, kind: .custom)
        history.recordRun(custom, query: "c")
        #expect(history.recents.isEmpty)
        let customStarred = history.toggleFavourite(custom)
        #expect(!customStarred)
        let starred = history.toggleFavourite(result("t", "T"))
        #expect(starred)
        #expect(history.isFavourite("t"))
        let unstarred = history.toggleFavourite(result("t", "T"))
        #expect(!unstarred)
    }

    @Test func roundTripsThroughJSON() throws {
        var history = FloatingBarHistory()
        history.recordRun(SearchResult(
            id: "command:timer.start=25m",
            title: "Start Timer 25m",
            icon: .symbol("timer"),
            score: 1,
            kind: .command("timer.start", argument: .duration(.seconds(1500)))
        ), query: "timer 25")
        history.toggleFavourite(SearchResult(id: "file:/tmp", title: "tmp", icon: .file(URL(fileURLWithPath: "/tmp")), score: 1, kind: .file(URL(fileURLWithPath: "/tmp"))))
        let data = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(FloatingBarHistory.self, from: data)
        #expect(decoded == history)
    }
}

@MainActor
struct CommandSearchProviderTests {
    private func makeProvider() -> (CommandRegistry, CommandSearchProvider) {
        let registry = CommandRegistry()
        registry.register([
            Command(id: "nightShift.toggle", title: "Toggle Night Shift", symbol: "moon", keywords: ["warm"]) { _ in },
            Command(id: "nightShift.setIntensity", title: "Set Night Shift Intensity…", symbol: "moon", parameter: .percent(default: 70)) { _ in },
        ], owner: "nightShift")
        registry.register([
            Command(id: "timer.startLabeled", title: "Start Labeled Timer…", symbol: "timer", parameter: .text(placeholder: "10m tea")) { _ in },
            Command(id: "timer.cancelAll", title: "Cancel All Timers", symbol: "xmark", isEnabled: { false }) { _ in },
        ], owner: "timer")
        let provider = CommandSearchProvider(commands: registry, shortcutText: { $0 == "nightShift.toggle" ? "⌃⌥N" : nil }, ownerName: { $0 == "nightShift" ? "Night Shift" : "Timer" })
        return (registry, provider)
    }

    @Test func findsCommandsWithShortcuts() {
        let (_, provider) = makeProvider()
        let results = provider.search(SearchQuery(text: "toggle night"))
        let toggle = results.first { $0.id == "command:nightShift.toggle" }
        #expect(toggle?.accessory == "⌃⌥N")
        #expect(toggle?.subtitle == "Night Shift")
        let disabled = provider.search(SearchQuery(text: "cancel all")).contains { $0.id == "command:timer.cancelAll" }
        #expect(!disabled)
    }

    @Test func parsesInlineArguments() {
        let (_, provider) = makeProvider()
        let results = provider.search(SearchQuery(text: "night 150"))
        let set = results.first { $0.kind == .command("nightShift.setIntensity", argument: .percent(150)) }
        #expect(set?.title == "Set Night Shift Intensity 150%")
        #expect(set?.id == "command:nightShift.setIntensity=150%")
        let labeled = provider.search(SearchQuery(text: "start labeled 10m tea"))
        let text = labeled.first { $0.kind == .command("timer.startLabeled", argument: .text("10m tea")) }
        #expect(text != nil)
    }

    @Test func findsCommandsByLooserWording() {
        let (registry, provider) = makeProvider()
        registry.register([
            Command(id: "screenTools.pickColor", title: "Pick Colour", symbol: "eyedropper", keywords: ["hex", "eyedropper"]) { _ in },
        ], owner: "screenTools")
        for query in ["pick colour", "pick color", "color picker", "colour picker", "colours"] {
            let top = provider.search(SearchQuery(text: query)).max { $0.score < $1.score }
            #expect(top?.id == "command:screenTools.pickColor", "\(query)")
        }
    }

    @Test func prefixAloneListsEverything() {
        let (_, provider) = makeProvider()
        #expect(provider.search(SearchQuery(text: "", isScoped: true)).count == 3)
        #expect(provider.search(SearchQuery(text: "")).isEmpty)
    }
}

@MainActor
struct FloatingBarModelTests {
    private let registry = CommandRegistry()
    private let model: FloatingBarModel
    private let files: FakeSearchProvider
    private let box = RunBox()

    @MainActor
    final class RunBox {
        struct Run {
            let result: SearchResult
            let keepOpen: Bool
        }

        var runs: [Run] = []
    }

    init() {
        let box = box
        registry.register([
            Command(id: "test.hello", title: "Say Hello", symbol: "hand.wave") { _ in },
            Command(id: "test.level", title: "Set Level…", symbol: "slider.horizontal.3", parameter: .percent(default: 50)) { _ in },
        ], owner: "test")
        let commands = CommandSearchProvider(commands: registry, shortcutText: { _ in nil }, ownerName: { _ in "Test" })
        files = FakeSearchProvider(id: "files", prefix: "f ", items: [result("file:report", "Report.pdf"), result("file:hello", "hello.txt", score: 0.5)])
        model = FloatingBarModel(commands: registry, commandProvider: commands)
        let files = files
        model.sources = {
            FloatingBarSources(
                providers: [
                    ProviderEntry(owner: "floatingBar", provider: commands),
                    ProviderEntry(owner: "search", provider: files),
                ],
                modes: [ModeEntry(owner: "quickNote", mode: FloatingBarMode(id: "editor", title: "Note", symbol: "pencil", prefix: "n ") { _ in
                    Text(verbatim: "editor")
                })]
            )
        }
        model.onRun = { result, keepOpen in box.runs.append(RunBox.Run(result: result, keepOpen: keepOpen)) }
    }

    @Test func searchesEveryProviderAndRunsTheTopResult() async {
        model.query = "hello"
        await waitUntil { model.rows.count == 2 }
        #expect(model.rows.map(\.result.id) == ["command:test.hello", "file:hello"])
        model.moveSelection(1)
        model.activateSelection(keepOpen: true)
        #expect(box.runs.map(\.result.id) == ["file:hello"])
        #expect(box.runs.first?.keepOpen == true)
        #expect(model.history.recents.first?.id == "file:hello")
    }

    @Test func previewKeepsTheBarWidth() async {
        model.query = "hello"
        await waitUntil { model.rows.count == 2 }
        let closed = FloatingBarLayout.size(for: model)
        model.showsPreview = true
        #expect(FloatingBarLayout.size(for: model).width == closed.width)
    }

    @Test func prefixesScopeToOneProvider() async {
        model.query = "f rep"
        await waitUntil { !model.rows.isEmpty }
        #expect(model.route == .scoped(providerKey: "search.files", text: "rep"))
        #expect(model.rows.map(\.result.id) == ["file:report"])
        #expect(files.queries.last == SearchQuery(text: "rep", isScoped: true))
    }

    @Test func turnedOffProvidersAreSkipped() async {
        model.isProviderEnabled = { $0 != "search.files" }
        model.query = "hello"
        await waitUntil { !model.rows.isEmpty }
        #expect(model.rows.map(\.result.id) == ["command:test.hello"])
    }

    @Test func inlineArgumentsRunStraightAway() async {
        model.query = "level 30"
        await waitUntil { !model.rows.isEmpty }
        let first = model.rows.first?.result
        #expect(first?.kind == .command("test.level", argument: .percent(30)))
        model.activateSelection(keepOpen: false)
        #expect(box.runs.count == 1)
        #expect(model.pending == nil)
    }

    @Test func commandsWithoutTheirValueAskForIt() async {
        model.query = "set level"
        await waitUntil { !model.rows.isEmpty }
        model.activateSelection(keepOpen: false)
        #expect(model.pending?.commandID == "test.level")
        #expect(box.runs.isEmpty)
        #expect(model.rows.first?.result.title == "Set Level (default)")

        model.query = "abc"
        #expect(model.rows.isEmpty)
        #expect(model.message != nil)

        model.query = "40"
        #expect(model.rows.first?.result.kind == .command("test.level", argument: .percent(40)))
        model.activateSelection(keepOpen: false)
        #expect(box.runs.map(\.result.kind) == [.command("test.level", argument: .percent(40))])
        #expect(model.pending == nil)
        #expect(model.query.isEmpty)
    }

    @Test func modePrefixesOpenTheMode() {
        model.query = "n buy milk"
        #expect(model.activeMode?.key == "quickNote.editor")
        #expect(model.activeMode?.text == "buy milk")
        model.exitMode()
        #expect(model.activeMode == nil)
        #expect(model.isEmptyState)
    }

    @Test func modesKnowWhetherEscapeGoesBackToSearch() {
        model.query = "n buy milk"
        #expect(model.activeMode?.returnsToSearch == true)
        model.exitMode()
        model.openMode(key: "quickNote.editor", text: "")
        #expect(model.activeMode?.returnsToSearch == false)
        model.exitMode()
        model.openMode(key: "quickNote.editor", text: "", returnsToSearch: true)
        #expect(model.activeMode?.returnsToSearch == true)
        model.exitMode()
        #expect(model.activeMode == nil)
        #expect(model.isEmptyState)
    }

    @Test func slowProvidersFillInAfterTheFirstPaint() async {
        let commands = model.commandProvider
        let slow = SlowSearchProvider(items: [result("app:hello", "Hello App", score: 0.95)])
        model.sources = {
            FloatingBarSources(providers: [
                ProviderEntry(owner: "floatingBar", provider: commands),
                ProviderEntry(owner: "search", provider: slow),
            ])
        }
        model.query = "hello"
        await waitUntil { model.rows.count == 2 }
        #expect(model.rows.map(\.result.id) == ["app:hello", "command:test.hello"])
    }

    @Test func aPrefixAloneListsMoreThanTheRootLimit() async {
        let many = (0..<120).map { result("app:\($0)", "App \($0)", score: 0.5) }
        let slow = SlowSearchProvider(items: many)
        model.sources = {
            FloatingBarSources(providers: [ProviderEntry(owner: "search", provider: slow)])
        }
        model.query = "s "
        await waitUntil { !model.rows.isEmpty }
        #expect(model.rows.count == 120)
        #expect(model.rows.first?.result.id == "app:0")
    }

    @Test func favouritesAndRecentsFillTheEmptyBar() async {
        model.query = "hello"
        await waitUntil { model.rows.count == 2 }
        model.activateSelection(keepOpen: false)
        model.toggleFavourite(result("file:report", "Report.pdf"))
        model.query = ""
        let sections = model.rows.map(\.section)
        #expect(sections == [.favourites, .recent])
        #expect(model.rows.map(\.result.id) == ["file:report", "command:test.hello"])
        model.showRecents = { false }
        model.reset()
        #expect(model.rows.map(\.result.id) == ["file:report"])
    }

    @Test func actionsMenuRunsTheChosenAction() async {
        var performed: [String] = []
        let action = ResultAction(id: "test.copy", title: "Copy", symbol: "doc.on.doc") { _ in }
        model.actionsFor = { _ in [action] }
        model.onAction = { action, result in performed.append("\(action.id):\(result.id)") }
        model.query = "hello"
        await waitUntil { !model.rows.isEmpty }
        model.toggleActions()
        #expect(model.actionsShown)
        model.activateSelection(keepOpen: false)
        #expect(performed == ["test.copy:command:test.hello"])
        #expect(!model.actionsShown)
        #expect(box.runs.isEmpty)
    }
}

@MainActor
final class InvocationBox {
    var invocations: [CommandInvocation] = []
    var finished = false
}

@MainActor
struct ExternalCommandRunnerTests {
    @Test func runsLinksWithValuesOnceReady() async throws {
        let environment = TestEnvironment()
        let box = InvocationBox()
        environment.commands.register([
            Command(id: "test.level", title: "Set Level", symbol: "slider.horizontal.3", parameter: .percent(default: 50)) { invocation in
                box.invocations.append(invocation)
            },
        ], owner: "test")
        let runner = ExternalCommandRunner(commands: environment.commands, settings: environment.settings, floatingBar: environment.floatingBar)
        runner.markReady()
        try await runner.handle(URL(string: "kkit://run/test.level?value=30")!)
        #expect(box.invocations.map(\.percent) == [30])
        #expect(box.invocations.first?.source == .url)

        await #expect(throws: ExternalCommandRunner.RunError.badValue("lots", hint: CommandArgumentParser.hint(for: .percent(default: 50)))) {
            try await runner.handle(URL(string: "kkit://run/test.level?value=lots")!)
        }
        await #expect(throws: ExternalCommandRunner.RunError.unknownCommand("test.missing")) {
            try await runner.run("test.missing", value: nil, source: .intent)
        }

        try await runner.handle(URL(string: "kkit://search?q=f%20report")!)
        #expect(environment.floatingBar.shownQueries == ["f report"])

        environment.settings.set(false, for: AppSettingKeys.allowLinkCommands)
        await #expect(throws: ExternalCommandRunner.RunError.linksTurnedOff) {
            try await runner.handle(URL(string: "kkit://run/test.level?value=30")!)
        }
    }

    @Test func waitsForFeaturesToStart() async {
        let environment = TestEnvironment()
        let runner = ExternalCommandRunner(commands: environment.commands, settings: environment.settings, floatingBar: nil)
        let box = InvocationBox()
        let task = Task { @MainActor in
            await runner.waitUntilReady()
            box.finished = true
        }
        await environment.settle()
        #expect(!box.finished)
        runner.markReady()
        await task.value
        #expect(box.finished)
    }
}
