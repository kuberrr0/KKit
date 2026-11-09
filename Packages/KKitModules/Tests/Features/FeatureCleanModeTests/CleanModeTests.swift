import CoreGraphics
import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureCleanMode

@MainActor
struct CleanModeTests {
    private func make(_ env: TestEnvironment) -> (CleanModeController, FeatureSettings) {
        let settings = FeatureSettings(featureID: "cleanMode", store: env.settings)
        let controller = CleanModeController(
            input: FeatureInput(owner: "cleanMode", service: env.input),
            overlays: env.overlays,
            settings: settings,
            detachesCursor: false
        )
        return (controller, settings)
    }

    @Test func keyboardLockBlocksKeysButNotTheMouse() throws {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        try controller.lock(.keyboard)
        #expect(controller.isLocked)
        #expect(env.input.handlers(owner: "cleanMode").first?.priority == .safety)
        #expect(env.input.sendKey(Shortcut.Key.a, down: true))
        #expect(env.input.sendMedia(.volumeUp))
        #expect(env.input.sendFlags([.command], keyCode: Shortcut.Key.leftCommand))
        // Releases go through so nothing stays held.
        #expect(!env.input.sendKey(Shortcut.Key.a, down: false))
        #expect(!env.input.sendFlags([], keyCode: Shortcut.Key.leftCommand))
        #expect(!env.input.sendMouse(.leftMouseDown, at: CGPoint(x: 10, y: 10)))
        #expect(env.overlays.openPanels.count == env.overlays.screens.count)
        #expect(env.overlays.openPanels.first?.configuration.level == .screenSaver)

        controller.unlock()
        #expect(!controller.isLocked)
        #expect(!env.input.sendKey(Shortcut.Key.a, down: true))
        #expect(env.overlays.openPanels.isEmpty)
    }

    @Test func everythingLockBlocksTheMouseToo() throws {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        try controller.lock(.everything)
        #expect(env.input.sendMouse(.leftMouseDown, at: CGPoint(x: 10, y: 10)))
        #expect(env.input.tappedTypes.contains(.mouseMoved))
        #expect(env.input.sendMouse(.mouseMoved, at: CGPoint(x: 20, y: 20)))
        controller.unlock()
        #expect(!env.input.tappedTypes.contains(.mouseMoved))
    }

    @Test func unlocksWhenTheCountdownEnds() throws {
        let env = TestEnvironment()
        let (controller, settings) = make(env)
        settings[CleanModeSettings.countdown] = 30
        let start = Date(timeIntervalSince1970: 1000)
        try controller.lock(.everything, now: start)
        controller.tick(now: start.addingTimeInterval(10))
        #expect(controller.isLocked)
        #expect(controller.remaining == 20)
        controller.tick(now: start.addingTimeInterval(30))
        #expect(!controller.isLocked)
        #expect(env.input.handlers(owner: "cleanMode").isEmpty)
    }

    @Test func neverLongerThanTwoMinutes() throws {
        let env = TestEnvironment()
        let (controller, settings) = make(env)
        settings[CleanModeSettings.countdown] = 600
        #expect(controller.countdown == 120)
    }

    @Test func refusesWithoutTheTap() {
        let env = TestEnvironment()
        env.input.status = .needsPermission
        let (controller, _) = make(env)
        #expect(throws: CleanModeError.self) {
            try controller.lock()
        }
        #expect(!controller.isLocked)
    }

    @Test func featureStopUnlocks() async throws {
        let env = TestEnvironment()
        let feature = CleanModeFeature(context: env.makeContext(for: "cleanMode"))
        try await feature.start()
        let start = try #require(feature.commands.first { $0.id == "cleanMode.start" })
        try await start.perform(CommandInvocation())
        #expect(feature.controller.isLocked)
        #expect(start.state?() == .on)
        await feature.stop()
        #expect(!feature.controller.isLocked)
        #expect(env.input.handlers.isEmpty)
    }
}
