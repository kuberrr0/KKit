import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureBrightness

struct BrightnessKeyActionTests {
    @Test func keyCodes() {
        #expect(BrightnessKeyAction.action(forKeyCode: 144, isDown: true, modifiers: []) == .step(up: true, fine: false))
        #expect(BrightnessKeyAction.action(forKeyCode: 145, isDown: true, modifiers: [.shift, .option]) == .step(up: false, fine: true))
        #expect(BrightnessKeyAction.action(forKeyCode: 145, isDown: false, modifiers: []) == .swallow)
        #expect(BrightnessKeyAction.action(forKeyCode: Shortcut.Key.a, isDown: true, modifiers: []) == .pass)
    }

    @Test func mediaKeys() {
        let up = MediaKeyEvent(key: .brightnessUp, isDown: true, isRepeat: false)
        #expect(BrightnessKeyAction.action(for: up, modifiers: []) == .step(up: true, fine: false))
        let volume = MediaKeyEvent(key: .volumeUp, isDown: true, isRepeat: false)
        #expect(BrightnessKeyAction.action(for: volume, modifiers: []) == .pass)
    }
}

@MainActor
struct BrightnessFeatureTests {
    @Test func brightnessKeysStepAndShowTheHUD() async throws {
        let env = TestEnvironment()
        let feature = BrightnessFeature(context: env.makeContext(for: "brightness"))
        try await feature.start()
        await env.settle()

        #expect(env.input.sendKey(144, down: true))
        #expect(env.input.sendKey(144, down: false))
        #expect(env.display.brightnessLevels[1] == 0.5625)
        #expect(env.island.huds.last?.id == "brightness")
        #expect(env.island.huds.last?.level == 0.5625)

        #expect(env.input.sendMedia(.brightnessDown, modifiers: [.shift, .option]))
        #expect(abs((env.display.brightnessLevels[1] ?? 0) - 0.546875) < 1e-9)
        await feature.stop()
        #expect(env.input.handlers(owner: "brightness").isEmpty)
    }

    @Test func keysGoToMacOSWhenTheDisplayCantBeControlled() async throws {
        let env = TestEnvironment()
        env.display.brightnessLevels = [:]
        let feature = BrightnessFeature(context: env.makeContext(for: "brightness"))
        try await feature.start()
        #expect(!env.input.sendKey(144, down: true))
        #expect(!env.input.sendKey(144, down: false))
        #expect(feature.menuBarSections.isEmpty)
        await feature.stop()
    }

    @Test func takeoverCanBeTurnedOff() async throws {
        let env = TestEnvironment()
        let context = env.makeContext(for: "brightness")
        context.settings[BrightnessSettings.takeOverKeys] = false
        let feature = BrightnessFeature(context: context)
        try await feature.start()
        await env.settle()
        #expect(!env.input.sendKey(144, down: true))
        await feature.stop()
    }

    @Test func setCommand() async throws {
        let env = TestEnvironment()
        let feature = BrightnessFeature(context: env.makeContext(for: "brightness"))
        try await feature.start()
        let set = try #require(feature.commands.first { $0.id == "brightness.set" })
        try await set.perform(CommandInvocation(argument: .percent(30)))
        #expect(env.display.brightnessLevels[1] == 0.3)
        await feature.stop()
    }
}
