import KeyboardShortcuts
import KKitCore
import KKitUI
import Testing
@testable import KKitServices

@MainActor
struct HotkeyServiceTests {
    /// KeyboardShortcuts' own recorder only pauses the handlers and leaves the Carbon hot
    /// keys registered, and macOS hands a hot key to its owner before any window sees the
    /// key, so ⌃⌥← (Window Management) couldn't be recorded. The service unregisters the
    /// hot keys for as long as a recorder records.
    @Test func hotkeysAreUnregisteredWhileRecording() {
        let commands = CommandRegistry()
        let recording = KKShortcutRecording()
        let service = KeyboardShortcutsHotkeyService(commands: commands, recording: recording)
        let id: CommandID = "hotkeytest.record"
        let shortcut = Shortcut(keyCode: Shortcut.Key.f19, modifiers: [.control, .option, .shift])
        commands.register(
            [Command(id: id, title: "Test", symbol: "keyboard", defaultShortcut: shortcut) { _ in }],
            owner: "hotkeytest"
        )
        let name = KeyboardShortcuts.Name("cmd-hotkeytest-record")
        defer {
            commands.unregister(owner: "hotkeytest")
            KeyboardShortcuts.reset(name)
        }

        #expect(service.shortcut(for: id) == shortcut)
        #expect(KeyboardShortcuts.isEnabled(for: name))
        recording.begin()
        #expect(!KeyboardShortcuts.isEnabled(for: name))
        recording.end()
        #expect(KeyboardShortcuts.isEnabled(for: name))
    }

    @Test func convertsControlOptionShortcuts() {
        let shortcut = Shortcut(keyCode: Shortcut.Key.leftArrow, modifiers: [.control, .option])
        let converted = KeyboardShortcutsHotkeyService.convert(shortcut)
        #expect(converted.modifiers == [.control, .option])
        #expect(KeyboardShortcutsHotkeyService.convert(converted) == shortcut)
    }
}
