import Foundation
import KKitCore

/// Test features. Each records its lifecycle in a shared log.
@MainActor
enum Lifecycle {
    static var events: [String] = []
}

struct StartFailure: LocalizedError {
    var errorDescription: String? { "boom" }
}

@MainActor
final class AlphaFeature: Feature {
    static let manifest = FeatureManifest(
        id: "alpha", name: "Alpha", symbol: "a.circle",
        summary: "Test feature with commands and a toggle.",
        category: .productivity, enabledByDefault: true
    )

    let context: FeatureContext
    var isOn = false
    var publishesService = false

    init(context: FeatureContext) {
        self.context = context
        Lifecycle.events.append("alpha.init")
    }

    func start() async throws {
        Lifecycle.events.append("alpha.start")
        context.services.publish((any GreetingService).self, Greeter())
    }

    func stop() async {
        Lifecycle.events.append("alpha.stop")
    }

    var commands: [Command] {
        [
            Command(id: "alpha.toggle", title: "Toggle Alpha", symbol: "a.circle",
                    state: { [weak self] in self?.isOn == true ? .on : .off }) { [weak self] _ in
                self?.isOn.toggle()
            },
            // Wrong prefix: the registry must reject it.
            Command(id: "beta.sneaky", title: "Sneaky", symbol: "eye") { _ in },
        ]
    }

    var quickToggles: [QuickToggle] {
        commands.filter { $0.id == "alpha.toggle" }.map(QuickToggle.init)
    }
}

@MainActor
final class NeedsAccessibilityFeature: Feature {
    static let manifest = FeatureManifest(
        id: "needsAX", name: "Needs AX", symbol: "accessibility",
        summary: "Requires Accessibility.", category: .windows,
        requiredPermissions: [.accessibility], enabledByDefault: true
    )

    init(context: FeatureContext) {}

    func start() async throws {
        Lifecycle.events.append("needsAX.start")
    }

    func stop() async {
        Lifecycle.events.append("needsAX.stop")
    }

    var commands: [Command] {
        [Command(id: "needsAX.snap", title: "Snap", symbol: "rectangle.split.2x1") { _ in }]
    }
}

@MainActor
final class BrokenFeature: Feature {
    static let manifest = FeatureManifest(
        id: "broken", name: "Broken", symbol: "xmark",
        summary: "Always fails to start.", category: .system
    )

    static var shouldFail = true

    init(context: FeatureContext) {}

    func start() async throws {
        Lifecycle.events.append("broken.start")
        if Self.shouldFail { throw StartFailure() }
    }

    func stop() async {
        Lifecycle.events.append("broken.stop")
    }
}

@MainActor
protocol GreetingService: AnyObject {
    func greet() -> String
}

@MainActor
final class Greeter: GreetingService {
    func greet() -> String { "hi" }
}
