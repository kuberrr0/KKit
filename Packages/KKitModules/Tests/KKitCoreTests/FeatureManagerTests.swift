import KKitCore
import KKitServicesTesting
import Testing

@MainActor
@Suite(.serialized)
struct FeatureManagerTests {
    let env = TestEnvironment()

    init() {
        Lifecycle.events = []
        BrokenFeature.shouldFail = true
    }

    @Test func startsFeaturesEnabledByDefault() async {
        let manager = env.makeFeatureManager(catalog: [AlphaFeature.self, BrokenFeature.self])
        await manager.startEnabledFeatures()

        #expect(manager.state(of: "alpha") == .running)
        #expect(manager.state(of: "broken") == .disabled)
        #expect(Lifecycle.events == ["alpha.init", "alpha.start"])
        #expect(manager.runningFeatures.count == 1)
    }

    @Test func registersCommandsWithTheRightPrefixOnly() async {
        let manager = env.makeFeatureManager(catalog: [AlphaFeature.self])
        await manager.startEnabledFeatures()

        #expect(env.commands.command("alpha.toggle") != nil)
        #expect(env.commands.command("beta.sneaky") == nil)
    }

    @Test func disablingStopsAndRemovesContributions() async throws {
        let manager = env.makeFeatureManager(catalog: [AlphaFeature.self])
        await manager.startEnabledFeatures()
        #expect(env.services.resolve((any GreetingService).self)?.greet() == "hi")

        await manager.setEnabled(false, for: "alpha")

        #expect(manager.state(of: "alpha") == .disabled)
        #expect(manager.isEnabled("alpha") == false)
        #expect(env.commands.command("alpha.toggle") == nil)
        #expect(env.services.resolve((any GreetingService).self) == nil)
        #expect(Lifecycle.events.last == "alpha.stop")
    }

    @Test func enabledChoiceIsRemembered() async {
        let first = env.makeFeatureManager(catalog: [AlphaFeature.self])
        await first.setEnabled(false, for: "alpha")

        let second = env.makeFeatureManager(catalog: [AlphaFeature.self])
        await second.startEnabledFeatures()
        #expect(second.state(of: "alpha") == .disabled)
    }

    @Test func waitsForPermissionsThenStarts() async {
        let manager = env.makeFeatureManager(catalog: [NeedsAccessibilityFeature.self])
        manager.recheckInterval = .seconds(3600)
        await manager.startEnabledFeatures()

        #expect(manager.state(of: "needsAX") == .waitingForPermissions([.accessibility]))
        #expect(manager.missingPermissions == [.accessibility])
        #expect(env.commands.command("needsAX.snap") == nil)

        env.permissions.set(.granted, for: .accessibility)
        await manager.reevaluatePermissions()

        #expect(manager.state(of: "needsAX") == .running)
        #expect(env.commands.command("needsAX.snap") != nil)
    }

    @Test func stopsWhenAPermissionIsRevoked() async {
        env.permissions.set(.granted, for: .accessibility)
        let manager = env.makeFeatureManager(catalog: [NeedsAccessibilityFeature.self])
        manager.recheckInterval = .seconds(3600)
        await manager.startEnabledFeatures()
        #expect(manager.state(of: "needsAX") == .running)

        env.permissions.set(.denied, for: .accessibility)
        await manager.reevaluatePermissions()

        #expect(manager.state(of: "needsAX") == .waitingForPermissions([.accessibility]))
        #expect(Lifecycle.events.last == "needsAX.stop")
        #expect(env.commands.command("needsAX.snap") == nil)
    }

    @Test func failedStartIsContainedAndRetryable() async {
        let manager = env.makeFeatureManager(catalog: [BrokenFeature.self, AlphaFeature.self])
        await manager.setEnabled(true, for: "broken")

        #expect(manager.state(of: "broken") == .failed("boom"))
        #expect(Lifecycle.events.contains("broken.stop"))

        BrokenFeature.shouldFail = false
        await manager.retry("broken")
        #expect(manager.state(of: "broken") == .running)
    }

    @Test func publishesStateChangeEvents() async {
        let stream = env.events.stream { event in
            if case .featureStateChanged = event { true } else { false }
        }
        let manager = env.makeFeatureManager(catalog: [AlphaFeature.self])
        await manager.startEnabledFeatures()

        var received: AppEvent?
        for await event in stream {
            received = event
            break
        }
        #expect(received == .featureStateChanged("alpha"))
    }

    @Test func stopAllStopsRunningFeatures() async {
        let manager = env.makeFeatureManager(catalog: [AlphaFeature.self])
        await manager.startEnabledFeatures()
        await manager.stopAll()

        #expect(manager.runningFeatures.isEmpty)
        #expect(Lifecycle.events.last == "alpha.stop")
        // Stopping for quit doesn't change the user's choice.
        #expect(manager.isEnabled("alpha"))
    }

    @Test func quickTogglesReflectCommandState() async throws {
        let manager = env.makeFeatureManager(catalog: [AlphaFeature.self])
        await manager.startEnabledFeatures()
        let toggle = try #require(manager.runningFeatures.first?.quickToggles.first)

        #expect(toggle.state == .off)
        try await env.commands.perform(toggle.id)
        #expect(toggle.state == .on)
    }
}
