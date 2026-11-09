import Foundation
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Capture a thought into your Obsidian vault in two keystrokes. DESIGN.md §3.11.
@MainActor
public final class QuickNoteFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "quickNote",
        name: String(localized: "Quick Note"),
        symbol: "square.and.pencil",
        summary: String(localized: "Jot a note into your Obsidian vault from the Floating Bar."),
        category: .productivity,
        enabledByDefault: true
    )

    static let editorMode = "editor"

    private let context: FeatureContext
    let controller: QuickNoteController

    public init(context: FeatureContext) {
        self.context = context
        controller = QuickNoteController(settings: context.settings)
    }

    public func start() async throws {
        controller.showEditor = { [weak self] text in
            guard let self else { return }
            self.context.floatingBar.showMode(Self.editorMode, text: text)
        }
        controller.onSaved = { [weak self] target, file in
            guard let self else { return }
            let name = target == .newNote ? file.deletingPathExtension().lastPathComponent : self.controller.label(for: target)
            self.context.island.showHUD(IslandHUD(
                id: "quickNote.saved",
                symbol: "checkmark.circle.fill",
                title: String(localized: "Saved to \(name)"),
                tint: .accent
            ))
        }
        context.services.publish((any QuickNoteServicing).self, controller)
    }

    public func stop() async {
        context.services.unpublish((any QuickNoteServicing).self)
        controller.showEditor = { _ in }
        controller.onSaved = { _, _ in }
    }

    // MARK: Contributions

    public var commands: [Command] {
        [
            Command(
                id: "quickNote.new",
                title: String(localized: "New Quick Note"),
                subtitle: String(localized: "Opens the note editor"),
                symbol: "square.and.pencil",
                keywords: ["note", "obsidian", "jot", "write", "inbox"]
            ) { [weak self] _ in
                self?.controller.showEditor(nil)
            },
            Command(
                id: "quickNote.append",
                title: String(localized: "Add to Note…"),
                subtitle: String(localized: "Saves one line without opening the editor"),
                symbol: "text.append",
                keywords: ["note", "inbox", "obsidian", "todo"],
                parameter: .text(placeholder: String(localized: "call the dentist"))
            ) { [weak self] invocation in
                guard let self else { return }
                guard let text = invocation.text, !text.isEmpty else { throw NoteError.empty }
                try await self.controller.append(text)
            },
            Command(
                id: "quickNote.openDaily",
                title: String(localized: "Open Today's Daily Note"),
                symbol: "calendar",
                keywords: ["note", "obsidian", "journal", "daily"]
            ) { [weak self] _ in
                try await self?.controller.openDailyNote()
            },
        ]
    }

    public var floatingBarModes: [FloatingBarMode] {
        let controller = controller
        return [
            FloatingBarMode(
                id: Self.editorMode,
                title: String(localized: "Quick Note"),
                symbol: "square.and.pencil",
                prefix: "n ",
                height: 260
            ) { modeContext in
                QuickNoteEditorView(controller: controller, context: modeContext)
            },
        ]
    }

    public var resultActions: [ResultAction] {
        [
            ResultAction(
                id: "quickNote.sendToNote",
                title: String(localized: "Send to Note"),
                symbol: "square.and.pencil",
                appliesTo: { result in
                    switch result.kind {
                    case .text, .url, .file: true
                    default: false
                    }
                }
            ) { [weak self] result in
                guard let self else { return }
                self.controller.openEditor(with: QuickNoteFeature.noteText(for: result))
            },
        ]
    }

    public var settingsPane: SettingsPane? {
        let controller = controller
        return SettingsPane {
            QuickNoteSettingsView(controller: controller)
        }
    }

    /// What "Send to Note" puts in the note: the copied text, a markdown link, a path.
    static func noteText(for result: SearchResult) -> String {
        switch result.kind {
        case .text(let text): text
        case .url(let url): "[\(result.title)](\(url.absoluteString))"
        case .file(let url): url.path
        default: result.title
        }
    }
}
