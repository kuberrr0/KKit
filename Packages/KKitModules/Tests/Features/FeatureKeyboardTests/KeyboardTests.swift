import CoreGraphics
import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureKeyboard

struct HyperKeyMachineTests {
    private let hyper = Shortcut.Key.f18
    private let start = Date(timeIntervalSince1970: 1000)

    @Test func tapAloneIsATap() {
        var machine = HyperKeyMachine(keyCode: hyper)
        #expect(machine.handle(keyCode: hyper, isDown: true, isRepeat: false, at: start) == .pressed)
        #expect(machine.handle(keyCode: hyper, isDown: false, isRepeat: false, at: start.addingTimeInterval(0.1)) == .released(tapped: true))
    }

    @Test func otherKeysGetHyperWhileHeld() {
        var machine = HyperKeyMachine(keyCode: hyper)
        #expect(machine.handle(keyCode: Shortcut.Key.a, isDown: true, isRepeat: false, at: start) == .passThrough)
        _ = machine.handle(keyCode: hyper, isDown: true, isRepeat: false, at: start)
        #expect(machine.handle(keyCode: Shortcut.Key.a, isDown: true, isRepeat: false, at: start) == .addHyper)
        #expect(machine.handle(keyCode: Shortcut.Key.a, isDown: false, isRepeat: false, at: start) == .addHyper)
        // Used with a key, so releasing isn't a tap.
        #expect(machine.handle(keyCode: hyper, isDown: false, isRepeat: false, at: start.addingTimeInterval(0.1)) == .released(tapped: false))
        #expect(machine.handle(keyCode: Shortcut.Key.a, isDown: true, isRepeat: false, at: start) == .passThrough)
    }

    @Test func longPressIsNotATap() {
        var machine = HyperKeyMachine(keyCode: hyper)
        _ = machine.handle(keyCode: hyper, isDown: true, isRepeat: false, at: start)
        #expect(machine.handle(keyCode: hyper, isDown: true, isRepeat: true, at: start.addingTimeInterval(0.3)) == .swallow)
        #expect(machine.handle(keyCode: hyper, isDown: false, isRepeat: false, at: start.addingTimeInterval(0.9)) == .released(tapped: false))
    }

    @Test func markUsedCancelsTheTap() {
        var machine = HyperKeyMachine(keyCode: hyper)
        _ = machine.handle(keyCode: hyper, isDown: true, isRepeat: false, at: start)
        machine.markUsed()
        #expect(machine.handle(keyCode: hyper, isDown: false, isRepeat: false, at: start.addingTimeInterval(0.1)) == .released(tapped: false))
    }
}

struct LeaderMatcherTests {
    private let note = LeaderSequence(keys: "n d", title: "Daily Note", action: .runCommand("quickNote.daily", value: nil))
    private let new = LeaderSequence(keys: "n", title: "New Note", action: .runCommand("quickNote.new", value: nil))
    private let timer = LeaderSequence(keys: "t5", title: "5 minutes", action: .runCommand("timer.start", value: "5m"))

    @Test func uniqueSequenceRuns() {
        #expect(LeaderMatcher.step("t", sequences: [timer]) == .waiting(exact: nil, candidates: [timer]))
        #expect(LeaderMatcher.step("t5", sequences: [timer, note]) == .run(timer))
    }

    @Test func prefixOfALongerSequenceWaits() {
        #expect(LeaderMatcher.step("n", sequences: [note, new, timer]) == .waiting(exact: new, candidates: [note, new]))
        #expect(LeaderMatcher.step("nd", sequences: [note, new]) == .run(note))
    }

    @Test func noMatch() {
        #expect(LeaderMatcher.step("x", sequences: [note, timer]) == .noMatch)
        #expect(LeaderMatcher.step("n", sequences: []) == .noMatch)
    }

    @Test func nextKeysListWhatCanFollow() {
        let next = LeaderMatcher.nextKeys(after: "n", candidates: [note, new])
        #expect(next.map(\.key) == ["d"])
        #expect(next.map(\.title) == ["Daily Note"])
    }
}

@MainActor
struct KeyboardControllerTests {
    @Test func startRemapsCapsLockAndStopGivesItBack() async throws {
        let env = TestEnvironment()
        let feature = KeyboardFeature(context: env.makeContext(for: "keyboard"))
        try await feature.start()
        await env.settle(20)
        #expect(env.input.capsLockRemap == .f18)
        #expect(env.input.handlers(owner: "keyboard").first?.priority == .high)
        await feature.stop()
        #expect(env.input.capsLockRemap == nil)
        #expect(env.input.handlers(owner: "keyboard").isEmpty)
    }

    @Test func tappingHyperSendsEscape() async throws {
        let env = TestEnvironment()
        let feature = KeyboardFeature(context: env.makeContext(for: "keyboard"))
        try await feature.start()
        #expect(env.input.sendKey(Shortcut.Key.f18, down: true))
        #expect(env.input.sendKey(Shortcut.Key.f18, down: false))
        #expect(env.input.posted.map(\.keyCode) == [Shortcut.Key.escape, Shortcut.Key.escape])
        #expect(env.input.posted.map(\.down) == [true, false])
        await feature.stop()
    }

    @Test func keysWhileHyperIsHeldGetAllFourModifiers() async throws {
        let env = TestEnvironment()
        let feature = KeyboardFeature(context: env.makeContext(for: "keyboard"))
        try await feature.start()
        env.input.sendKey(Shortcut.Key.f18, down: true)
        let consumed = env.input.sendKey(Shortcut.Key.a, down: true)
        #expect(!consumed)
        let flags = try #require(env.input.lastEvent?.flags)
        #expect(InputEvent.modifiers(from: flags) == .hyper)
        env.input.sendKey(Shortcut.Key.a, down: false)
        env.input.sendKey(Shortcut.Key.f18, down: false)
        // Used with a key: no Escape.
        #expect(env.input.posted.isEmpty)
        await feature.stop()
    }

    @Test func hyperOffLeavesKeysAlone() async throws {
        let env = TestEnvironment()
        let context = env.makeContext(for: "keyboard")
        context.settings[KeyboardSettings.hyperEnabled] = false
        let feature = KeyboardFeature(context: context)
        try await feature.start()
        #expect(!env.input.sendKey(Shortcut.Key.f18, down: true))
        #expect(!env.input.sendKey(Shortcut.Key.f18, down: false))
        #expect(env.input.posted.isEmpty)
        await feature.stop()
    }

    @Test func bindingRunsACommand() async throws {
        let env = TestEnvironment()
        let context = env.makeContext(for: "keyboard")
        let trigger = Shortcut(keyCode: Shortcut.Key.n, modifiers: .hyper)
        context.settings[KeyboardSettings.bindings] = [
            KeyBinding(trigger: trigger, action: .runCommand("quickNote.new", value: nil)),
        ]
        let feature = KeyboardFeature(context: context)
        try await feature.start()
        #expect(env.input.sendKey(Shortcut.Key.n, down: true, modifiers: .hyper))
        #expect(env.input.sendKey(Shortcut.Key.n, down: false, modifiers: .hyper))
        await env.settle(20)
        #expect(env.commandRunner.runs.map { $0.0 } == ["quickNote.new"])
        await feature.stop()
    }
}
