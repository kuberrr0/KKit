import KKitCore
import Testing

@MainActor
struct ServiceRegistryTests {
    @Test func resolvesByProtocolType() {
        let registry = ServiceRegistry()
        #expect(registry.resolve((any GreetingService).self) == nil)

        registry.register((any GreetingService).self, Greeter())
        #expect(registry.resolve((any GreetingService).self)?.greet() == "hi")
    }

    @Test func unpublishAllRemovesOnlyThatFeaturesServices() {
        let registry = ServiceRegistry()
        registry.register((any GreetingService).self, Greeter())
        registry.publish(String.self, "shelf", by: "shelf")

        registry.unpublishAll(by: "shelf")
        #expect(registry.resolve(String.self) == nil)
        #expect(registry.resolve((any GreetingService).self) != nil)
    }
}

@MainActor
struct EventBusTests {
    @Test func deliversMatchingEventsOnly() async {
        let bus = EventBus()
        let stream = bus.stream { $0 == .displaysChanged }

        bus.publish(.frontmostAppChanged(bundleID: "com.apple.finder"))
        bus.publish(.displaysChanged)

        var received: AppEvent?
        for await event in stream {
            received = event
            break
        }
        #expect(received == .displaysChanged)
    }
}

struct IdentifierTests {
    @Test func featureIDValidation() {
        #expect(FeatureID("nightShift").isValid)
        #expect(FeatureID("timer2").isValid)
        #expect(!FeatureID("NightShift").isValid)
        #expect(!FeatureID("night.shift").isValid)
        #expect(!FeatureID("").isValid)
    }
}
