import AppKit
import SwiftUI

/// A key the search field hands to its owner before typing sees it.
public enum KKFieldKey: Equatable, Sendable {
    case up
    case down
    /// ↵, with ⌘ and/or ⇧ held.
    case submit(command: Bool, shift: Bool)
    case cancel
    case tab(backwards: Bool)
    /// ⌫ with nothing typed.
    case deleteWhenEmpty
    /// ⌘⌫.
    case commandDelete
    /// ⌘ plus a character: "1"…"9", "p", "c".
    case command(String)
}

/// A plain search field for feature views inside the Floating Bar (the clipboard
/// picker). Focuses itself when shown, and passes ↑ ↓ ↵ ⎋ Tab and ⌘-keys to `onKey`
/// first; return `true` from `onKey` to swallow the key.
public struct KKSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontSize: CGFloat
    let onKey: @MainActor (KKFieldKey) -> Bool

    public init(
        text: Binding<String>,
        placeholder: String,
        fontSize: CGFloat = 17,
        onKey: @escaping @MainActor (KKFieldKey) -> Bool
    ) {
        self._text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.onKey = onKey
    }

    public func makeNSView(context: Context) -> KKKeyTextField {
        let field = KKKeyTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.stringValue = text
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        return field
    }

    public func updateNSView(_ field: KKKeyTextField, context: Context) {
        let binding = $text
        field.onTextChange = { binding.wrappedValue = $0 }
        field.onKey = onKey
        if field.stringValue != text {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
    }
}

/// The `NSTextField` behind `KKSearchField`. It watches key presses in its window
/// while it's editing, so arrow keys and ⌘-shortcuts reach the owner first.
public final class KKKeyTextField: NSTextField {
    var onTextChange: (@MainActor (String) -> Void)?
    var onKey: (@MainActor (KKFieldKey) -> Bool)?
    private var monitor: Any?

    public func focus() {
        guard let window else { return }
        window.makeFirstResponder(self)
        currentEditor()?.selectAll(nil)
    }

    public override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onTextChange?(stringValue)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.focus() }
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, let editor = currentEditor(),
              window.firstResponder === editor, let onKey
        else { return false }
        if let textView = editor as? NSTextView, textView.hasMarkedText() {
            return false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key: KKFieldKey?
        switch event.keyCode {
        case 126: key = .up
        case 125: key = .down
        case 36, 76: key = .submit(command: flags.contains(.command), shift: flags.contains(.shift))
        case 53: key = .cancel
        case 48: key = .tab(backwards: flags.contains(.shift))
        case 51 where flags.contains(.command): key = .commandDelete
        case 51 where stringValue.isEmpty: key = .deleteWhenEmpty
        default:
            if flags.contains(.command), let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty {
                key = .command(characters)
            } else {
                key = nil
            }
        }
        guard let key else { return false }
        return onKey(key)
    }
}
