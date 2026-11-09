import KKitCore
import KKitUI
import Testing

@MainActor
struct KeyRecorderTests {
    // MARK: Key presses

    @Test func recordsControlOptionShortcuts() {
        for key in [Shortcut.Key.leftArrow, Shortcut.Key.a, Shortcut.Key.returnKey, Shortcut.Key.delete, Shortcut.Key.escape] {
            let action = KKKeyRecorderAction.forKeyDown(keyCode: key, modifiers: [.control, .option], requiresModifier: true)
            #expect(action == .record(Shortcut(keyCode: key, modifiers: [.control, .option])))
        }
    }

    @Test func escapeCancelsAndDeleteClears() {
        #expect(KKKeyRecorderAction.forKeyDown(keyCode: Shortcut.Key.escape, modifiers: [], requiresModifier: true) == .cancel)
        #expect(KKKeyRecorderAction.forKeyDown(keyCode: Shortcut.Key.delete, modifiers: [], requiresModifier: true) == .clear)
        #expect(KKKeyRecorderAction.forKeyDown(keyCode: Shortcut.Key.forwardDelete, modifiers: [], requiresModifier: false) == .clear)
    }

    @Test func shortcutsNeedARealModifier() {
        #expect(KKKeyRecorderAction.forKeyDown(keyCode: Shortcut.Key.a, modifiers: [], requiresModifier: true) == .reject)
        #expect(KKKeyRecorderAction.forKeyDown(keyCode: Shortcut.Key.a, modifiers: [.shift], requiresModifier: true) == .reject)
        #expect(KKKeyRecorderAction.forKeyDown(keyCode: Shortcut.Key.a, modifiers: [.shift], requiresModifier: false)
            == .record(Shortcut(keyCode: Shortcut.Key.a, modifiers: [.shift])))
        #expect(KKKeyRecorderAction.forKeyDown(keyCode: Shortcut.Key.f13, modifiers: [], requiresModifier: true)
            == .record(Shortcut(keyCode: Shortcut.Key.f13, modifiers: [])))
    }

    @Test func functionKeys() {
        #expect(Shortcut.Key.functionKeys.count == 20)
        #expect(Set(Shortcut.Key.functionKeys).count == 20)
        #expect(Shortcut.Key.isFunctionKey(122)) // F1
        #expect(!Shortcut.Key.isFunctionKey(Shortcut.Key.a))
        for key in Shortcut.Key.functionKeys {
            #expect(KKKeyNames.name(forKeyCode: key).hasPrefix("F"))
        }
    }

    // MARK: Pausing hotkeys while recording

    @Test func recordingIsActiveWhileAnyRecorderRecords() {
        let recording = KKShortcutRecording()
        let changes = Changes()
        recording.observe { changes.values.append($0) }

        recording.begin()
        recording.begin()
        #expect(recording.isActive)
        recording.end()
        #expect(recording.isActive)
        recording.end()
        #expect(!recording.isActive)
        #expect(changes.values == [true, false])
    }

    @Test func unpairedEndIsIgnored() {
        let recording = KKShortcutRecording()
        let changes = Changes()
        recording.observe { changes.values.append($0) }

        recording.end()
        #expect(!recording.isActive)
        recording.begin()
        #expect(recording.isActive)
        #expect(changes.values == [true])
    }

    @Test func removedObserversAreNotCalled() {
        let recording = KKShortcutRecording()
        let changes = Changes()
        let id = recording.observe { changes.values.append($0) }
        recording.removeObserver(id)
        recording.begin()
        #expect(changes.values.isEmpty)
    }
}

@MainActor
private final class Changes {
    var values: [Bool] = []
}
