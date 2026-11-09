import AppKit
import Foundation
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Clipboard History: everything you copy, searchable, with a picker, a paste stack and
/// snippets. DESIGN.md §3.7.
@MainActor
public final class ClipboardFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "clipboard",
        name: String(localized: "Clipboard History"),
        symbol: "list.clipboard",
        summary: String(localized: "Everything you copy, searchable, with a picker, a paste stack and snippets."),
        category: .productivity,
        optionalPermissions: [.accessibility],
        enabledByDefault: true
    )

    static let pickerMode = "picker"
    static let snippetsFile = "snippets"
    static let databaseName = "history"

    private let context: FeatureContext
    let controller: ClipboardController
    private lazy var provider = ClipboardProvider(controller: controller)
    private var stackActivity: (any IslandHandle)?

    public init(context: FeatureContext) {
        self.context = context
        controller = ClipboardController(settings: context.settings, pasteboard: context.pasteboard)
    }

    public func start() async throws {
        let storage = context.storage
        let directory = try storage.directory()
        let database = try storage.openDatabase(named: Self.databaseName)
        let store = try ClipboardStore(db: database, imagesDirectory: directory.appendingPathComponent("images", isDirectory: true))
        controller.loadSnippets((try? storage.read([Snippet].self, named: Self.snippetsFile)) ?? [])
        let log = context.log
        controller.onSnippetsChange = { snippets in
            do {
                try storage.write(snippets, named: ClipboardFeature.snippetsFile)
            } catch {
                log.error("Couldn't save snippets: \(error.localizedDescription, privacy: .public)")
            }
        }
        controller.onEvent = { [weak self] event in self?.handle(event) }
        await controller.attach(store)
        controller.startMonitoring()
    }

    public func stop() async {
        // KKit stops every feature before it quits, so this covers quitting too.
        if context.settings[ClipboardSettings.clearOnQuit], let store = controller.store {
            try? await store.clear(keepPinned: true)
        }
        controller.detach()
        controller.onEvent = { _ in }
        controller.onSnippetsChange = nil
        stackActivity?.dismiss()
        stackActivity = nil
    }

    // MARK: Contributions

    public var commands: [Command] {
        [
            Command(
                id: "clipboard.showHistory",
                title: String(localized: "Show Clipboard History"),
                subtitle: String(localized: "Search and paste anything you copied"),
                symbol: "list.clipboard",
                keywords: ["clipboard", "paste", "history", "copy"],
                defaultShortcut: Shortcut(keyCode: Shortcut.Key.v, modifiers: [.command, .shift])
            ) { [weak self] _ in
                self?.context.floatingBar.showMode(Self.pickerMode)
            },
            Command(
                id: "clipboard.pastePlain",
                title: String(localized: "Paste as Plain Text"),
                subtitle: String(localized: "Pastes the latest copy without formatting"),
                symbol: "doc.plaintext",
                keywords: ["clipboard", "paste", "plain", "unformatted"]
            ) { [weak self] _ in
                guard let self, let latest = self.controller.recent.first else {
                    throw ClipboardError.nothingCopied
                }
                await self.controller.paste(latest, plain: true)
            },
            Command(
                id: "clipboard.togglePasteStack",
                title: String(localized: "Start or Stop Paste Stack"),
                subtitle: String(localized: "Copy several things, then paste them in order"),
                symbol: "square.stack.3d.up",
                keywords: ["clipboard", "stack", "queue", "multiple"],
                state: { [weak self] in
                    guard let stack = self?.controller.stack, stack.isCollecting else { return .off }
                    return .value(String(localized: "\(stack.count) items"))
                }
            ) { [weak self] _ in
                self?.controller.toggleStack()
            },
            Command(
                id: "clipboard.pasteNext",
                title: String(localized: "Paste Next from Stack"),
                symbol: "arrow.down.doc",
                keywords: ["clipboard", "stack", "paste"],
                isEnabled: { [weak self] in self?.controller.stack.isCollecting == true }
            ) { [weak self] _ in
                await self?.controller.pasteNext()
            },
            Command(
                id: "clipboard.togglePause",
                title: String(localized: "Pause or Resume Clipboard History"),
                symbol: "pause.circle",
                keywords: ["clipboard", "private", "pause", "record"],
                state: { [weak self] in self?.controller.isPaused == true ? .value(String(localized: "Paused")) : .off }
            ) { [weak self] _ in
                guard let self else { return }
                self.controller.isPaused.toggle()
                self.context.island.showHUD(IslandHUD(
                    id: "clipboard.paused",
                    symbol: self.controller.isPaused ? "pause.circle.fill" : "list.clipboard",
                    title: self.controller.isPaused ? String(localized: "Clipboard history paused") : String(localized: "Clipboard history on")
                ))
            },
            Command(
                id: "clipboard.clear",
                title: String(localized: "Clear Clipboard History"),
                subtitle: String(localized: "Pinned items stay"),
                symbol: "trash",
                keywords: ["clipboard", "delete", "erase"]
            ) { [weak self] _ in
                await self?.controller.clear(keepPinned: true)
            },
        ]
    }

    public var quickToggles: [QuickToggle] {
        let controller = controller
        return [
            QuickToggle(Command(
                id: "clipboard.recordingTile",
                title: String(localized: "Clipboard"),
                symbol: "list.clipboard",
                state: { controller.isPaused ? .off : .value(String(localized: "\(controller.itemCount) items")) }
            ) { _ in
                controller.isPaused.toggle()
            }),
        ]
    }

    public var searchProviders: [any SearchProvider] {
        [provider]
    }

    public var floatingBarModes: [FloatingBarMode] {
        let controller = controller
        return [
            FloatingBarMode(
                id: Self.pickerMode,
                title: String(localized: "Clipboard History"),
                symbol: "list.clipboard",
                height: 400
            ) { modeContext in
                ClipboardPickerView(controller: controller, context: modeContext)
            },
        ]
    }

    public var resultActions: [ResultAction] {
        let controller = controller
        let services = context.services
        let isHistory: @MainActor @Sendable (SearchResult) -> Bool = { ClipboardProvider.itemID(of: $0) != nil }
        return [
            ResultAction(id: "clipboard.pastePlainResult", title: String(localized: "Paste as Plain Text"), symbol: "doc.plaintext", appliesTo: isHistory) { result in
                guard let id = ClipboardProvider.itemID(of: result), let item = await controller.item(id) else { return }
                await controller.paste(item, plain: true)
            },
            ResultAction(id: "clipboard.copyResult", title: String(localized: "Copy"), symbol: "doc.on.doc", appliesTo: isHistory) { result in
                guard let id = ClipboardProvider.itemID(of: result), let item = await controller.item(id) else { return }
                await controller.copy(item)
            },
            ResultAction(id: "clipboard.pinResult", title: String(localized: "Pin or Unpin"), symbol: "pin", dismissesBar: false, appliesTo: isHistory) { result in
                guard let id = ClipboardProvider.itemID(of: result), let item = await controller.item(id) else { return }
                await controller.togglePin(item)
            },
            ResultAction(id: "clipboard.deleteResult", title: String(localized: "Delete from History"), symbol: "trash", dismissesBar: false, appliesTo: isHistory) { result in
                guard let id = ClipboardProvider.itemID(of: result), let item = await controller.item(id) else { return }
                await controller.delete(item)
            },
            ResultAction(
                id: "clipboard.shelfResult",
                title: String(localized: "Add to Shelf"),
                symbol: "tray.and.arrow.down",
                appliesTo: { isHistory($0) && services.resolve((any ShelfServicing).self) != nil }
            ) { result in
                guard let id = ClipboardProvider.itemID(of: result), let item = await controller.item(id),
                      let shelf = services.resolve((any ShelfServicing).self)
                else { return }
                try await shelf.add(ClipboardFeature.droppedItems(for: item, imageURL: controller.imageURL(for: item)))
            },
            ResultAction(
                id: "clipboard.noteResult",
                title: String(localized: "Send to Note"),
                symbol: "square.and.pencil",
                appliesTo: { isHistory($0) && services.resolve((any QuickNoteServicing).self) != nil }
            ) { result in
                guard let id = ClipboardProvider.itemID(of: result), let item = await controller.item(id),
                      let notes = services.resolve((any QuickNoteServicing).self)
                else { return }
                notes.openEditor(with: item.text)
            },
        ]
    }

    public var menuBarSections: [MenuBarSection] {
        let controller = controller
        let floatingBar = context.floatingBar
        return [
            MenuBarSection(id: "count", order: 960) {
                Button {
                    floatingBar.showMode(ClipboardFeature.pickerMode)
                } label: {
                    HStack {
                        Image(systemName: "list.clipboard")
                            .foregroundStyle(.secondary)
                        Text("Clipboard: \(controller.itemCount)")
                        if controller.isPaused {
                            Text("Paused")
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                    }
                    .font(.caption)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            },
        ]
    }

    public var settingsPane: SettingsPane? {
        let controller = controller
        let permissions = context.permissions
        return SettingsPane {
            ClipboardSettingsView(
                controller: controller,
                canPaste: controller.pasteboard.canPaste,
                openAccessibility: { permissions.openSystemSettings(for: .accessibility) }
            )
        }
    }

    // MARK: Events

    private func handle(_ event: ClipboardEvent) {
        switch event {
        case .saved(let item):
            context.events.publish(.clipboardChanged)
            if context.settings[ClipboardSettings.flashInIsland] {
                context.island.showHUD(IslandHUD(id: "clipboard.copied", symbol: item.kind.symbol, detail: String(localized: "Copied"), duration: 1))
            }
        case .pasted:
            break
        case .stackChanged:
            updateStackActivity()
        case .problem(let message):
            context.island.showHUD(IslandHUD(
                id: "clipboard.problem",
                symbol: "exclamationmark.triangle.fill",
                title: message,
                tint: .warning,
                duration: 3
            ))
        }
    }

    /// The paste stack's count in the Island while it's collecting.
    private func updateStackActivity() {
        let stack = controller.stack
        guard stack.isCollecting else {
            stackActivity?.dismiss()
            stackActivity = nil
            return
        }
        let activity = IslandActivity(
            id: "pasteStack",
            title: String(localized: "Paste Stack"),
            symbol: "square.stack.3d.up",
            priority: .normal,
            compactLeading: AnyView(Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.white)),
            compactTrailing: AnyView(Text("\(stack.count)").foregroundStyle(.white)),
            expanded: AnyView(PasteStackPage(controller: controller))
        )
        if let stackActivity, stackActivity.isActive {
            stackActivity.update(activity)
        } else {
            stackActivity = context.island.present(activity)
        }
    }

    /// What "Add to Shelf" puts on the Shelf for an item.
    static func droppedItems(for item: ClipboardItem, imageURL: URL?) -> [DroppedItem] {
        switch item.kind {
        case .files: item.fileURLs.map { .file($0) }
        case .image: imageURL.map { [.file($0)] } ?? []
        case .link: item.url.map { [.url($0)] } ?? [.text(item.text)]
        case .text, .richText, .color: [.text(item.text)]
        }
    }
}

/// The paste stack's page in the expanded Island.
struct PasteStackPage: View {
    let controller: ClipboardController

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            Text(controller.stack.isEmpty
                ? String(localized: "Copy things to add them. Paste them in order with “Paste Next from Stack”.")
                : String(localized: "\(controller.stack.count) items to paste, oldest first."))
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
            HStack {
                Button(String(localized: "Paste Next")) {
                    Task { await controller.pasteNext() }
                }
                .disabled(controller.stack.isEmpty)
                Button(String(localized: "Stop")) {
                    controller.toggleStack()
                }
            }
            .buttonStyle(.bordered)
        }
    }
}
