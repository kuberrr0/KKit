import Foundation

/// Published by Quick Note while it runs, so other features can send text to the
/// user's notes without importing it ("Send to note" from Clipboard, OCR and Shelf):
///
/// ```swift
/// if let notes = context.services.resolve((any QuickNoteServicing).self) { … }
/// ```
@MainActor
public protocol QuickNoteServicing: AnyObject {
    /// Adds `text` to the default note target (Inbox, daily note…).
    func append(_ text: String) async throws
    /// Opens the note editor in the Floating Bar with `text` filled in.
    func openEditor(with text: String)
}
