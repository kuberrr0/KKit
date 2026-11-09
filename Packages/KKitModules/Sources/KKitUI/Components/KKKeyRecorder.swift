import AppKit
import Combine
import KKitCore
import SwiftUI

/// Names for keys and shortcuts in KKit's own key fields (command shortcuts, the
/// Hyper key's bindings, push-to-talk). Letters follow the US layout's positions.
public enum KKKeyNames {
    private static let names: [Int: String] = {
        var names: [Int: String] = [
            Shortcut.Key.space: "Space", Shortcut.Key.returnKey: "↩", Shortcut.Key.escape: "⎋",
            Shortcut.Key.tab: "⇥", Shortcut.Key.delete: "⌫", Shortcut.Key.forwardDelete: "⌦",
            Shortcut.Key.leftArrow: "←", Shortcut.Key.rightArrow: "→", Shortcut.Key.upArrow: "↑",
            Shortcut.Key.downArrow: "↓", Shortcut.Key.home: "↖", Shortcut.Key.end: "↘",
            Shortcut.Key.pageUp: "⇞", Shortcut.Key.pageDown: "⇟", Shortcut.Key.comma: ",",
            Shortcut.Key.equal: "=", Shortcut.Key.minus: "-", Shortcut.Key.leftBracket: "[",
            Shortcut.Key.rightBracket: "]", 41: ";", 39: "'", 42: "\\", 44: "/", 47: ".", 50: "`",
            Shortcut.Key.capsLock: "⇪", Shortcut.Key.function: "fn",
            Shortcut.Key.leftCommand: "Left ⌘", Shortcut.Key.rightCommand: "Right ⌘",
            Shortcut.Key.leftOption: "Left ⌥", Shortcut.Key.rightOption: "Right ⌥",
            Shortcut.Key.leftShift: "Left ⇧", Shortcut.Key.rightShift: "Right ⇧",
            Shortcut.Key.leftControl: "Left ⌃", Shortcut.Key.rightControl: "Right ⌃",
        ]
        let letters: [(Int, String)] = [
            (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"), (4, "H"), (34, "I"),
            (38, "J"), (40, "K"), (37, "L"), (46, "M"), (45, "N"), (31, "O"), (35, "P"), (12, "Q"),
            (15, "R"), (1, "S"), (17, "T"), (32, "U"), (9, "V"), (13, "W"), (7, "X"), (16, "Y"), (6, "Z"),
            (29, "0"), (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"), (22, "6"), (26, "7"),
            (28, "8"), (25, "9"),
        ]
        for (code, name) in letters {
            names[code] = name
        }
        let functionKeys: [(Int, Int)] = [
            (122, 1), (120, 2), (99, 3), (118, 4), (96, 5), (97, 6), (98, 7), (100, 8), (101, 9),
            (109, 10), (103, 11), (111, 12), (105, 13), (107, 14), (113, 15), (106, 16), (64, 17),
            (79, 18), (80, 19), (90, 20),
        ]
        for (code, number) in functionKeys {
            names[code] = "F\(number)"
        }
        return names
    }()

    public static func name(forKeyCode keyCode: Int) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    /// "⌃⌥⇧⌘", or "Hyper" for all four.
    public static func modifiers(_ modifiers: Shortcut.Modifiers) -> String {
        if modifiers == .hyper {
            return "Hyper "
        }
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text
    }

    /// "Hyper B", "⌃⌥←", "Right ⌥".
    public static func string(for shortcut: Shortcut) -> String {
        modifiers(shortcut.modifiers) + name(forKeyCode: shortcut.keyCode)
    }

    public static func modifiers(from flags: NSEvent.ModifierFlags) -> Shortcut.Modifiers {
        var result: Shortcut.Modifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
}

/// Whether one of KKit's key recorders is waiting for a key.
///
/// KKit's global hotkeys are Carbon hot keys, and macOS hands a hot key to its owner
/// before any window sees the key press. So while a recorder is recording, the hotkey
/// service turns KKit's hotkeys off (`observe`), or a shortcut KKit already uses, like
/// Window Management's ⌃⌥ keys, could never be recorded.
@MainActor
public final class KKShortcutRecording {
    public static let shared = KKShortcutRecording()

    public private(set) var isActive = false
    private var recorders = 0
    private var observers: [UUID: @MainActor (Bool) -> Void] = [:]

    public init() {}

    /// A recorder started waiting for a key.
    public func begin() {
        recorders += 1
        update()
    }

    /// A recorder stopped. Calls must pair with `begin`.
    public func end() {
        guard recorders > 0 else { return }
        recorders -= 1
        update()
    }

    /// Called with `true` when the first recorder starts and `false` when the last stops.
    @discardableResult
    public func observe(_ handler: @escaping @MainActor (Bool) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    public func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func update() {
        let active = recorders > 0
        guard active != isActive else { return }
        isActive = active
        for observer in observers.values {
            observer(active)
        }
    }
}

/// What a recorder does with a key press.
public enum KKKeyRecorderAction: Hashable, Sendable {
    /// ⎋: stop without changing anything.
    case cancel
    /// ⌫: remove the shortcut.
    case clear
    /// Beep and keep waiting (a shortcut needs ⌃, ⌥ or ⌘).
    case reject
    case record(Shortcut)

    /// With `requiresModifier`, a shortcut needs ⌃, ⌥ or ⌘ (⇧ alone types a character),
    /// except F1–F20.
    public static func forKeyDown(keyCode: Int, modifiers: Shortcut.Modifiers, requiresModifier: Bool) -> Self {
        if modifiers.isEmpty, keyCode == Shortcut.Key.escape {
            return .cancel
        }
        if modifiers.isEmpty, keyCode == Shortcut.Key.delete || keyCode == Shortcut.Key.forwardDelete {
            return .clear
        }
        if requiresModifier, modifiers.subtracting(.shift).isEmpty, !Shortcut.Key.isFunctionKey(keyCode) {
            return .reject
        }
        return .record(Shortcut(keyCode: keyCode, modifiers: modifiers))
    }
}

/// A field that records one key with its modifiers: command shortcuts, the Hyper key's
/// bindings, push-to-talk. Click, press the keys; ⎋ cancels, ⌫ clears. With
/// `allowsModifierOnly`, pressing and releasing a modifier on its own records that key
/// (Right ⌥, fn). While it records, KKit's own hotkeys are off (`KKShortcutRecording`),
/// so it can record a shortcut KKit already uses.
public struct KKKeyRecorder: View {
    @Binding var shortcut: Shortcut?
    let allowsModifierOnly: Bool
    let requiresModifier: Bool
    let placeholder: String
    let recording: KKShortcutRecording
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var pendingModifierKey: Int?

    public init(
        shortcut: Binding<Shortcut?>,
        allowsModifierOnly: Bool = false,
        requiresModifier: Bool = false,
        placeholder: String = String(localized: "Record Key"),
        recording: KKShortcutRecording = .shared
    ) {
        self._shortcut = shortcut
        self.allowsModifierOnly = allowsModifierOnly
        self.requiresModifier = requiresModifier
        self.placeholder = placeholder
        self.recording = recording
    }

    public var body: some View {
        HStack(spacing: KKSpacing.xs) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(label)
                    .frame(minWidth: 110)
                    .foregroundStyle(isRecording ? Color.accentColor : (shortcut == nil ? Color.secondary : Color.primary))
            }
            .accessibilityLabel(Text("Shortcut"))
            .accessibilityValue(Text(shortcut.map(KKKeyNames.string(for:)) ?? String(localized: "None")))
            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Clear shortcut"))
            }
        }
        .onDisappear { stop() }
        // Don't leave KKit's hotkeys off while the user is in another app.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stop()
        }
    }

    private var label: String {
        if isRecording {
            return String(localized: "Type a key…")
        }
        return shortcut.map(KKKeyNames.string(for:)) ?? placeholder
    }

    private func start() {
        stop()
        isRecording = true
        pendingModifierKey = nil
        recording.begin()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event) ? nil : event
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if isRecording {
            recording.end()
        }
        isRecording = false
        pendingModifierKey = nil
    }

    /// Returns `true` when the event was used.
    private func handle(_ event: NSEvent) -> Bool {
        let keyCode = Int(event.keyCode)
        let modifiers = KKKeyNames.modifiers(from: event.modifierFlags)
        switch event.type {
        case .keyDown:
            pendingModifierKey = nil
            switch KKKeyRecorderAction.forKeyDown(keyCode: keyCode, modifiers: modifiers, requiresModifier: requiresModifier) {
            case .cancel:
                stop()
            case .clear:
                shortcut = nil
                stop()
            case .reject:
                NSSound.beep()
            case .record(let recorded):
                shortcut = recorded
                stop()
            }
            return true
        case .flagsChanged:
            guard allowsModifierOnly, Shortcut.Key.isModifierKey(keyCode) else { return false }
            let isDown: Bool
            if let modifier = Shortcut.Key.modifier(forKeyCode: keyCode) {
                isDown = modifiers.contains(modifier)
            } else {
                isDown = event.modifierFlags.contains(.function)
            }
            if isDown {
                pendingModifierKey = keyCode
            } else if pendingModifierKey == keyCode {
                shortcut = Shortcut(keyCode: keyCode, modifiers: [])
                stop()
            }
            return false
        default:
            return false
        }
    }
}
