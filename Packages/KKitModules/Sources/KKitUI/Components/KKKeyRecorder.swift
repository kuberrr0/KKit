import AppKit
import KKitCore
import SwiftUI

/// Names for keys and shortcuts in KKit's own key fields (the Hyper key's bindings,
/// push-to-talk). Letters follow the US layout's positions.
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

/// A field that records one key with its modifiers, for KKit's own key settings (Hyper
/// bindings, push-to-talk). Click, press the keys; ⎋ cancels, ⌫ clears. With
/// `allowsModifierOnly`, pressing and releasing a modifier on its own records that key
/// (Right ⌥, fn).
public struct KKKeyRecorder: View {
    @Binding var shortcut: Shortcut?
    let allowsModifierOnly: Bool
    let requiresModifier: Bool
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var pendingModifierKey: Int?

    public init(shortcut: Binding<Shortcut?>, allowsModifierOnly: Bool = false, requiresModifier: Bool = false) {
        self._shortcut = shortcut
        self.allowsModifierOnly = allowsModifierOnly
        self.requiresModifier = requiresModifier
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
    }

    private var label: String {
        if isRecording {
            return String(localized: "Type a key…")
        }
        return shortcut.map(KKKeyNames.string(for:)) ?? String(localized: "Record Key")
    }

    private func start() {
        stop()
        isRecording = true
        pendingModifierKey = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event) ? nil : event
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
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
            if modifiers.isEmpty, keyCode == Shortcut.Key.escape {
                stop()
                return true
            }
            if modifiers.isEmpty, keyCode == Shortcut.Key.delete {
                shortcut = nil
                stop()
                return true
            }
            if requiresModifier, modifiers.isEmpty {
                NSSound.beep()
                return true
            }
            shortcut = Shortcut(keyCode: keyCode, modifiers: modifiers)
            stop()
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
