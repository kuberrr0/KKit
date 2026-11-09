import AppKit
import SwiftUI

/// The Floating Bar's text field: a plain, large `NSTextField` that takes focus when the
/// bar opens. Navigation keys (↑ ↓ ↵ ⎋ Tab ⌘K) never reach it: the host handles them
/// before the field editor sees them.
struct FloatingBarSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    /// Changing it focuses the field and selects its text.
    let focusToken: Int

    func makeNSView(context: Context) -> FocusingTextField {
        let field = FocusingTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.stringValue = text
        field.placeholderString = placeholder
        field.setAccessibilityLabel(String(localized: "Search"))
        field.focusToken = focusToken
        return field
    }

    func updateNSView(_ field: FocusingTextField, context: Context) {
        let binding = $text
        field.onTextChange = { binding.wrappedValue = $0 }
        if field.stringValue != text {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
        if field.focusToken != focusToken {
            field.focusToken = focusToken
            field.focus()
        }
    }
}

/// Reports edits, and focuses itself as soon as it's in a window and whenever asked.
final class FocusingTextField: NSTextField {
    var onTextChange: ((String) -> Void)?
    var focusToken = 0
    private var wantsFocus = true

    func focus() {
        guard let window else {
            wantsFocus = true
            return
        }
        window.makeFirstResponder(self)
        currentEditor()?.selectAll(nil)
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onTextChange?(stringValue)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if wantsFocus, window != nil {
            wantsFocus = false
            focus()
        }
    }
}
