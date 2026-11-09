import KKitCore
import Testing

@MainActor
struct CommandRegistryTests {
    @Test func commandIDParts() {
        let id: CommandID = "nightShift.setIntensity"
        #expect(id.featureID == "nightShift")
        #expect(id.verb == "setIntensity")
        #expect(CommandID("nodot").verb == "")
    }

    @Test func rejectsDuplicatesAndBadPrefixes() {
        let registry = CommandRegistry()
        let added = registry.register([
            Command(id: "timer.start", title: "Start Timer", symbol: "timer") { _ in },
            Command(id: "timer.start", title: "Again", symbol: "timer") { _ in },
            Command(id: "other.thing", title: "Other", symbol: "x") { _ in },
            Command(id: "timer", title: "No verb", symbol: "x") { _ in },
        ], owner: "timer")

        #expect(added == ["timer.start"])
        #expect(registry.command("timer.start")?.title == "Start Timer")
        #expect(registry.commands(owner: "timer").count == 1)
    }

    @Test func notifiesObservers() {
        let registry = CommandRegistry()
        var changes: [CommandRegistry.Change] = []
        registry.addObserver { changes.append($0) }

        registry.register([Command(id: "timer.start", title: "Start", symbol: "timer") { _ in }], owner: "timer")
        registry.unregister(owner: "timer")
        registry.unregister(owner: "timer")

        #expect(changes == [.added(["timer.start"]), .removed(["timer.start"])])
    }

    @Test func performPassesTheInvocation() async throws {
        let registry = CommandRegistry()
        var received: Double?
        registry.register([
            Command(id: "nightShift.set", title: "Set", symbol: "moon", parameter: .percent(default: 0.7)) { invocation in
                received = invocation.percent
            },
        ], owner: "nightShift")

        try await registry.perform("nightShift.set", CommandInvocation(argument: .percent(1.5), source: .url))
        #expect(received == 1.5)
    }

    @Test func performFailsForUnknownOrDisabledCommands() async {
        let registry = CommandRegistry()
        registry.register([
            Command(id: "timer.cancel", title: "Cancel", symbol: "xmark", isEnabled: { false }) { _ in },
        ], owner: "timer")

        await #expect(throws: CommandRegistry.RegistryError.unknownCommand("timer.nope")) {
            try await registry.perform("timer.nope")
        }
        await #expect(throws: CommandRegistry.RegistryError.commandDisabled("timer.cancel")) {
            try await registry.perform("timer.cancel")
        }
    }

    @Test func allCommandsAreSortedByTitle() {
        let registry = CommandRegistry()
        registry.register([
            Command(id: "a.zeta", title: "Zeta", symbol: "z.circle") { _ in },
            Command(id: "a.alpha", title: "alpha", symbol: "a.circle") { _ in },
        ], owner: "a")
        #expect(registry.allCommands.map(\.title) == ["alpha", "Zeta"])
    }
}
