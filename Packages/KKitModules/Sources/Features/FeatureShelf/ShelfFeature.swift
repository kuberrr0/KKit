import AppKit
import Foundation
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Shelf: a holding area for files, images, links and text. Drag things to the notch,
/// drag them out later. DESIGN.md §3.8.
@MainActor
public final class ShelfFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "shelf",
        name: String(localized: "Shelf"),
        symbol: "tray",
        summary: String(localized: "Drag files to the notch to keep them for later, then drag them out, AirDrop or convert them."),
        category: .productivity,
        enabledByDefault: true
    )

    static let pageID = "shelf"
    static let itemsFile = "items"

    private let context: FeatureContext
    let controller: ShelfController
    private var renamePanel: (any OverlayHandle)?

    public init(context: FeatureContext) {
        self.context = context
        controller = ShelfController(settings: context.settings, pasteboard: context.pasteboard)
    }

    public func start() async throws {
        let storage = context.storage
        let folder = try storage.directory()
        let saved = (try? storage.read([ShelfItem].self, named: Self.itemsFile)) ?? []
        let log = context.log
        controller.onChange = { items in
            do {
                try storage.write(items, named: ShelfFeature.itemsFile)
            } catch {
                log.error("Couldn't save the Shelf: \(error.localizedDescription, privacy: .public)")
            }
        }
        controller.onEvent = { [weak self] event in self?.handle(event) }
        controller.attach(folder: folder, items: saved)
        context.services.publish((any ShelfServicing).self, controller)
    }

    public func stop() async {
        context.services.unpublish((any ShelfServicing).self)
        controller.detach()
        controller.onChange = nil
        controller.onEvent = { _ in }
        renamePanel?.close()
        renamePanel = nil
    }

    // MARK: Contributions

    public var commands: [Command] {
        let controller = controller
        let context = context
        return [
            Command(
                id: "shelf.show",
                title: String(localized: "Show Shelf"),
                symbol: "tray",
                keywords: ["shelf", "files", "drop", "holding"]
            ) { _ in
                context.island.showPage(ShelfFeature.pageID)
            },
            Command(
                id: "shelf.addClipboard",
                title: String(localized: "Add Clipboard to Shelf"),
                symbol: "tray.and.arrow.down",
                keywords: ["shelf", "clipboard", "paste"]
            ) { _ in
                try await controller.addClipboard()
            },
            Command(
                id: "shelf.airDropAll",
                title: String(localized: "AirDrop Everything on the Shelf"),
                symbol: "airplayaudio",
                keywords: ["shelf", "airdrop", "send", "share"],
                isEnabled: { !controller.items.isEmpty }
            ) { _ in
                controller.airDrop(controller.items)
            },
            Command(
                id: "shelf.clear",
                title: String(localized: "Clear Shelf"),
                symbol: "trash",
                keywords: ["shelf", "clear", "empty"],
                isEnabled: { !controller.items.isEmpty }
            ) { _ in
                controller.clear()
            },
        ]
    }

    public var islandPages: [IslandPage] {
        let controller = controller
        let actions = pageActions
        return [
            IslandPage(id: Self.pageID, title: String(localized: "Shelf"), symbol: "tray") {
                ShelfPage(controller: controller, actions: actions)
            },
        ]
    }

    public var islandDropZones: [IslandDropZone] {
        let controller = controller
        let context = context
        return [
            IslandDropZone(id: "shelf", title: String(localized: "Shelf"), symbol: "tray.and.arrow.down", order: 100) { items in
                do {
                    try await controller.add(items)
                    if context.settings[ShelfSettings.showAfterDrop] {
                        context.island.showPage(ShelfFeature.pageID)
                    }
                } catch {
                    controller.onEvent(.problem(error.localizedDescription))
                }
            },
            IslandDropZone(
                id: "airDrop",
                title: String(localized: "AirDrop"),
                symbol: "airplayaudio",
                order: 200,
                accepts: [.files, .urls, .images]
            ) { items in
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("KKit AirDrop", isDirectory: true)
                let shareable: [Any] = items.compactMap { item -> Any? in
                    switch item {
                    case .file(let url), .url(let url):
                        return url
                    case .image(let data, let type):
                        return try? FileActions.writeImage(data, type: type, to: temporary)
                    case .text:
                        return nil
                    }
                }
                ShelfController.airDrop(shareable)
            },
        ]
    }

    public var resultActions: [ResultAction] {
        let controller = controller
        return [
            ResultAction(
                id: "shelf.addResult",
                title: String(localized: "Add to Shelf"),
                symbol: "tray.and.arrow.down",
                appliesTo: { ShelfFeature.droppedItem(for: $0) != nil }
            ) { result in
                guard let item = ShelfFeature.droppedItem(for: result) else { return }
                try await controller.add([item])
            },
        ]
    }

    public var menuBarSections: [MenuBarSection] {
        let controller = controller
        let context = context
        return [
            MenuBarSection(id: "count", order: 950) {
                Button {
                    context.island.showPage(ShelfFeature.pageID)
                } label: {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundStyle(.secondary)
                        Text("Shelf: \(controller.itemCount) items")
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
        return SettingsPane {
            ShelfSettingsView(controller: controller)
        }
    }

    /// What "Add to Shelf" takes from a Floating Bar result.
    static func droppedItem(for result: SearchResult) -> DroppedItem? {
        switch result.kind {
        case .file(let url), .application(let url): .file(url)
        case .url(let url): .url(url)
        case .text(let text): .text(text)
        case .command, .custom: nil
        }
    }

    // MARK: Events and panels

    private var pageActions: ShelfPageActions {
        let services = context.services
        var sendToNote: (@MainActor (ShelfItem) -> Void)?
        if services.resolve((any QuickNoteServicing).self) != nil {
            sendToNote = { item in
                guard let text = item.plainText else { return }
                services.resolve((any QuickNoteServicing).self)?.openEditor(with: text)
            }
        }
        return ShelfPageActions(
            rename: { [weak self] item in self?.showRename(item) },
            sendToNote: sendToNote
        )
    }

    private func handle(_ event: ShelfEvent) {
        switch event {
        case .added(let count):
            context.island.showHUD(IslandHUD(
                id: "shelf.added",
                symbol: "tray.and.arrow.down.fill",
                title: count == 1 ? String(localized: "Added to Shelf") : String(localized: "\(count) items added to Shelf"),
                duration: 1.2
            ))
        case .done(let title, let symbol):
            context.island.showHUD(IslandHUD(id: "shelf.done", symbol: symbol, title: title, duration: 1.2))
        case .problem(let message):
            context.island.showHUD(IslandHUD(
                id: "shelf.problem",
                symbol: "exclamationmark.triangle.fill",
                title: message,
                tint: .warning,
                duration: 3
            ))
        }
    }

    private func showRename(_ item: ShelfItem) {
        guard let url = item.fileURL else { return }
        renamePanel?.close()
        let controller = controller
        let view = RenameView(
            original: url.lastPathComponent,
            rename: { [weak self] name in
                do {
                    try controller.rename(item, to: name)
                    self?.closeRename()
                    return nil
                } catch {
                    return error.localizedDescription
                }
            },
            cancel: { [weak self] in self?.closeRename() }
        )
        let panel = context.overlays.makePanel(
            OverlayConfiguration(
                level: .floating,
                screen: .withCursor,
                placement: .topCenter(size: CGSize(width: 340, height: 140), offset: 120),
                acceptsKeyFocus: true,
                hidesOnResignKey: true
            ),
            content: AnyView(view)
        )
        renamePanel = panel
        panel.show()
    }

    private func closeRename() {
        renamePanel?.close()
        renamePanel = nil
    }
}
