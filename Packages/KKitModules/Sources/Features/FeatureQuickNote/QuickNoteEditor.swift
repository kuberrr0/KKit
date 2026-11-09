import AppKit
import KKitCore
import KKitUI
import SwiftUI

/// The Floating Bar mode: a small markdown editor. ⌘↵ saves and closes, ⌘⇧↵ also
/// opens the note in Obsidian, Tab switches the target, ⎋ leaves (back to search, or closes when opened by hotkey).
struct QuickNoteEditorView: View {
    @Bindable var controller: QuickNoteController
    let context: FloatingBarModeContext

    var body: some View {
        VStack(spacing: 0) {
            if controller.hasVault {
                targets
                    .padding(.horizontal, KKSpacing.l)
                    .padding(.vertical, KKSpacing.s)
                NoteTextEditor(
                    text: $controller.draft,
                    candidates: { controller.linkCandidates() },
                    onSubmit: { open in save(openInObsidian: open) },
                    onCycleTarget: { step in controller.target = controller.target.next(step) },
                    onCancel: { context.exit() }
                )
                Divider()
                footer
                    .padding(.horizontal, KKSpacing.l)
                    .frame(height: 30)
            } else {
                noVault
            }
        }
        .onAppear {
            if !context.initialText.isEmpty {
                controller.draft = controller.draft.isEmpty ? context.initialText : controller.draft + "\n" + context.initialText
            }
            controller.errorMessage = nil
            controller.warmLinkCandidates()
        }
    }

    private var targets: some View {
        HStack(spacing: KKSpacing.xs) {
            ForEach(NoteTargetKind.allCases) { kind in
                Button {
                    controller.target = kind
                } label: {
                    Label(controller.label(for: kind), systemImage: kind.symbol)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, KKSpacing.s)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(controller.target == kind ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                        )
                        .foregroundStyle(controller.target == kind ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            KKKeyCap("Tab")
        }
    }

    private var footer: some View {
        HStack(spacing: KKSpacing.s) {
            if let error = controller.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else {
                Text("Markdown · [[ links your notes")
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            KKKeyCap("⌘↵")
            Text("Save")
            KKKeyCap("⌘⇧↵")
            Text("Save & Open")
        }
        .font(.caption)
    }

    private var noVault: some View {
        VStack(spacing: KKSpacing.m) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Choose your Obsidian vault first")
                .font(.headline)
            Text("Quick Note writes markdown files into a folder you pick.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(String(localized: "Open Quick Note Settings")) {
                context.openSettings()
            }
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func save(openInObsidian: Bool) {
        Task {
            if await controller.saveDraft(openInObsidian: openInObsidian) {
                context.dismiss()
            }
        }
    }
}

/// A plain-text `NSTextView` with the editor's keys, light markdown colouring and `[[`
/// completion from the vault's note names.
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    let candidates: @MainActor () -> [String]
    let onSubmit: @MainActor (Bool) -> Void
    let onCycleTarget: @MainActor (Int) -> Void
    let onCancel: @MainActor () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let textView = NoteTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 200))
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = NoteTextView.baseFont
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: KKSpacing.l - 4, height: KKSpacing.s)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel(String(localized: "Note"))
        textView.string = text
        scroll.documentView = textView
        configure(textView)
        textView.highlight()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NoteTextView else { return }
        configure(textView)
        if textView.string != text {
            textView.string = text
            textView.highlight()
        }
    }

    private func configure(_ textView: NoteTextView) {
        let binding = $text
        textView.onChange = { binding.wrappedValue = $0 }
        textView.candidates = candidates
        textView.onSubmit = onSubmit
        textView.onCycleTarget = onCycleTarget
        textView.onCancel = onCancel
    }
}

final class NoteTextView: NSTextView {
    static let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    var onChange: (@MainActor (String) -> Void)?
    var candidates: @MainActor () -> [String] = { [] }
    var onSubmit: (@MainActor (Bool) -> Void)?
    var onCycleTarget: (@MainActor (Int) -> Void)?
    var onCancel: (@MainActor () -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.makeFirstResponder(self)
        setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 36 || event.keyCode == 76, flags.contains(.command) {
            onSubmit?(flags.contains(.shift))
            return
        }
        super.keyDown(with: event)
    }

    override func insertTab(_ sender: Any?) {
        onCycleTarget?(1)
    }

    override func insertBacktab(_ sender: Any?) {
        onCycleTarget?(-1)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func didChangeText() {
        super.didChangeText()
        onChange?(string)
        highlight()
        let text = string as NSString
        let cursor = selectedRange().location
        if cursor >= 2, text.substring(with: NSRange(location: cursor - 2, length: 2)) == "[[" {
            complete(nil)
        }
    }

    // MARK: [[ completion

    /// From just after the last unclosed "[[" to the cursor.
    override var rangeForUserCompletion: NSRange {
        let text = string as NSString
        let cursor = selectedRange().location
        let before = text.substring(to: min(cursor, text.length))
        guard let open = before.range(of: "[[", options: .backwards),
              !before[open.upperBound...].contains("]]"),
              !before[open.upperBound...].contains("\n")
        else { return super.rangeForUserCompletion }
        let start = (before as NSString).length - (String(before[open.upperBound...]) as NSString).length
        return NSRange(location: start, length: cursor - start)
    }

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        let text = string as NSString
        guard charRange.location >= 2, text.substring(with: NSRange(location: charRange.location - 2, length: 2)) == "[[" else {
            return nil
        }
        let partial = text.substring(with: charRange)
        let names = candidates()
        let matches = partial.isEmpty ? names : names.filter { FuzzyMatch.score(partial, in: $0) != nil }
        return Array(matches.prefix(50))
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        let text = string as NSString
        let closes = charRange.location + charRange.length + 2 <= text.length
            && text.substring(with: NSRange(location: charRange.location + charRange.length, length: 2)) == "]]"
        super.insertCompletion(flag && !closes ? word + "]]" : word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
    }

    // MARK: Highlighting

    /// Headings bold, `[[links]]` and `#tags` in the accent colour, list markers and
    /// `code` dimmed. Only attributes change; the text is plain markdown.
    func highlight() {
        guard let storage = textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: Self.baseFont, .foregroundColor: NSColor.labelColor], range: whole)
        let text = storage.string
        apply("(?m)^#{1,6} .*$", in: text, to: storage, [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)])
        apply("\\[\\[[^\\]\\n]+\\]\\]", in: text, to: storage, [.foregroundColor: NSColor.controlAccentColor])
        apply("(?<![\\w#])#[\\p{L}\\d_/-]+", in: text, to: storage, [.foregroundColor: NSColor.controlAccentColor])
        apply("(?m)^\\s*([-*+]|\\d+\\.)( \\[[ x]\\])? ", in: text, to: storage, [.foregroundColor: NSColor.secondaryLabelColor])
        apply("`[^`\\n]+`", in: text, to: storage, [.foregroundColor: NSColor.secondaryLabelColor])
        storage.endEditing()
    }

    private func apply(_ pattern: String, in text: String, to storage: NSTextStorage, _ attributes: [NSAttributedString.Key: Any]) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        for match in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
            storage.addAttributes(attributes, range: match.range)
        }
    }
}
