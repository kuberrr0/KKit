import AppKit
import KeyboardShortcuts
import KKitCore
import KKitServicesAPI
import Observation
import SwiftUI

/// Global hotkeys for commands, backed by sindresorhus/KeyboardShortcuts (Carbon
/// `RegisterEventHotKey`, so no permission is needed).
///
/// User-recorded shortcuts are stored by KeyboardShortcuts in `UserDefaults`
/// ("KeyboardShortcuts_cmd-<feature>-<verb>").
@MainActor
@Observable
public final class KeyboardShortcutsHotkeyService: HotkeyService {
    private let commands: CommandRegistry
    /// Bumped when the user records a shortcut, so the Shortcuts page refreshes.
    private var revision = 0
    @ObservationIgnored private var active: Set<CommandID> = []
    private let log = KKitLog.logger("hotkeys")

    public init(commands: CommandRegistry) {
        self.commands = commands
        commands.addObserver { [weak self] change in
            self?.apply(change)
        }
        apply(.added(Array(commands.commands.keys)))
    }

    public func shortcut(for command: CommandID) -> Shortcut? {
        _ = revision
        return KeyboardShortcuts.getShortcut(for: shortcutName(for: command)).map(Self.convert)
    }

    public func setShortcut(_ shortcut: Shortcut?, for command: CommandID) {
        KeyboardShortcuts.setShortcut(shortcut.map(Self.convert), for: shortcutName(for: command))
        revision &+= 1
    }

    public func resetShortcut(for command: CommandID) {
        KeyboardShortcuts.reset(shortcutName(for: command))
        revision &+= 1
    }

    public func conflicts(for command: CommandID) -> [CommandID] {
        guard let mine = shortcut(for: command) else { return [] }
        return commands.commands.keys
            .filter { $0 != command && shortcut(for: $0) == mine }
            .sorted()
    }

    public func displayString(for shortcut: Shortcut) -> String {
        Self.convert(shortcut).description
    }

    public func recorder(for command: CommandID) -> AnyView {
        AnyView(KeyboardShortcuts.Recorder(for: shortcutName(for: command), onChange: { [weak self] _ in
            self?.revision &+= 1
        }))
    }

    // MARK: Private

    private func apply(_ change: CommandRegistry.Change) {
        switch change {
        case .added(let ids):
            for id in ids where !active.contains(id) {
                active.insert(id)
                KeyboardShortcuts.onKeyDown(for: shortcutName(for: id)) { [weak self] in
                    self?.fire(id)
                }
            }
        case .removed(let ids):
            for id in ids where active.contains(id) {
                active.remove(id)
                KeyboardShortcuts.removeHandler(for: shortcutName(for: id))
            }
        }
        revision &+= 1
    }

    private func fire(_ id: CommandID) {
        let registry = self.commands
        let logger = self.log
        Task {
            do {
                try await registry.perform(id, CommandInvocation(source: .hotkey))
            } catch {
                logger.error("Hotkey for \(id.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// KeyboardShortcuts names can't contain dots.
    private func shortcutName(for id: CommandID) -> KeyboardShortcuts.Name {
        let initial = commands.command(id)?.defaultShortcut.map(Self.convert)
        return KeyboardShortcuts.Name("cmd-" + id.rawValue.replacingOccurrences(of: ".", with: "-"), default: initial)
    }

    static func convert(_ shortcut: Shortcut) -> KeyboardShortcuts.Shortcut {
        var flags: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.command) { flags.insert(.command) }
        if shortcut.modifiers.contains(.option) { flags.insert(.option) }
        if shortcut.modifiers.contains(.control) { flags.insert(.control) }
        if shortcut.modifiers.contains(.shift) { flags.insert(.shift) }
        return KeyboardShortcuts.Shortcut(KeyboardShortcuts.Key(rawValue: shortcut.keyCode), modifiers: flags)
    }

    static func convert(_ shortcut: KeyboardShortcuts.Shortcut) -> Shortcut {
        var modifiers: Shortcut.Modifiers = []
        if shortcut.modifiers.contains(.command) { modifiers.insert(.command) }
        if shortcut.modifiers.contains(.option) { modifiers.insert(.option) }
        if shortcut.modifiers.contains(.control) { modifiers.insert(.control) }
        if shortcut.modifiers.contains(.shift) { modifiers.insert(.shift) }
        return Shortcut(keyCode: shortcut.carbonKeyCode, modifiers: modifiers)
    }
}
