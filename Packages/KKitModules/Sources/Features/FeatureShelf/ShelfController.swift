import AppKit
import Foundation
import KKitCore
import KKitServicesAPI

/// What the feature shows in the Island after a Shelf action.
enum ShelfEvent {
    case added(Int)
    case done(String, symbol: String)
    case problem(String)
}

/// The Shelf's items: adding, removing, persisting, and the file actions.
@MainActor
@Observable
final class ShelfController: ShelfServicing {
    private(set) var items: [ShelfItem] = []

    @ObservationIgnored private let settings: FeatureSettings
    @ObservationIgnored private let pasteboard: any PasteboardService
    /// Where copies and dropped images live. Set by `attach`.
    @ObservationIgnored private(set) var folder: URL?
    @ObservationIgnored var onChange: (@MainActor ([ShelfItem]) -> Void)?
    @ObservationIgnored var onEvent: @MainActor (ShelfEvent) -> Void = { _ in }
    @ObservationIgnored var now: @MainActor () -> Date = { Date() }
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    init(settings: FeatureSettings, pasteboard: any PasteboardService) {
        self.settings = settings
        self.pasteboard = pasteboard
    }

    var itemCount: Int { items.count }

    func attach(folder: URL, items saved: [ShelfItem]) {
        self.folder = folder
        // Files that were moved or deleted while KKit wasn't looking are dropped.
        items = saved.filter { item in
            guard let url = item.fileURL else { return true }
            return FileManager.default.fileExists(atPath: url.path)
        }
        removeExpired()
        if items != saved { onChange?(items) }
    }

    func detach() {
        expiryTask?.cancel()
        expiryTask = nil
        folder = nil
    }

    // MARK: Adding

    /// `ShelfServicing`: adds dropped or handed-over items, newest last.
    func add(_ dropped: [DroppedItem]) async throws {
        guard let folder else { return }
        let keepCopies = settings[ShelfSettings.keepCopies]
        let existing = Set(items.compactMap(\.fileURL).map(\.standardizedFileURL))
        let date = now()
        let filesFolder = folder.appendingPathComponent("Files", isDirectory: true)
        let added = try await Task.detached(priority: .userInitiated) {
            var added: [ShelfItem] = []
            var seen = existing
            for item in dropped {
                switch item {
                case .file(let url):
                    let standard = url.standardizedFileURL
                    guard !seen.contains(standard) else { continue }
                    seen.insert(standard)
                    if keepCopies {
                        let copy = try FileActions.copyIn(url, to: filesFolder)
                        added.append(ShelfItem(content: .file(copy), addedAt: date, isOwnCopy: true))
                    } else {
                        added.append(ShelfItem(content: .file(url), addedAt: date))
                    }
                case .url(let url):
                    if url.isFileURL {
                        added.append(ShelfItem(content: .file(url), addedAt: date))
                    } else {
                        added.append(ShelfItem(content: .link(url), addedAt: date))
                    }
                case .text(let text):
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    added.append(ShelfItem(content: .text(text), addedAt: date))
                case .image(let data, let type):
                    let url = try FileActions.writeImage(data, type: type, to: filesFolder)
                    added.append(ShelfItem(content: .file(url), addedAt: date, isOwnCopy: true))
                }
            }
            return added
        }.value
        guard !added.isEmpty else { return }
        insert(added)
        onEvent(.added(added.count))
    }

    /// Whatever is on the clipboard.
    func addClipboard() async throws {
        let contents = pasteboard.read()
        var dropped: [DroppedItem] = []
        if !contents.fileURLs.isEmpty {
            dropped = contents.fileURLs.map { .file($0) }
        } else if let image = contents.image {
            dropped = [.image(image, type: contents.imageType ?? "public.png")]
        } else if let url = contents.url, !url.isFileURL {
            dropped = [.url(url)]
        } else if let text = contents.string {
            dropped = [.text(text)]
        }
        try await add(dropped)
    }

    private func insert(_ added: [ShelfItem]) {
        items.append(contentsOf: added)
        let limit = max(settings[ShelfSettings.maxItems], 1)
        if items.count > limit {
            let overflow = items.prefix(items.count - limit)
            items.removeFirst(overflow.count)
            deleteCopies(Array(overflow))
        }
        changed()
    }

    // MARK: Removing

    func remove(_ ids: Set<ShelfItem.ID>) {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        deleteCopies(removed)
        changed()
    }

    func remove(_ item: ShelfItem) {
        remove([item.id])
    }

    func clear() {
        let removed = items
        items = []
        deleteCopies(removed)
        changed()
    }

    /// The Shelf's own copies go when their items do; the user's files never do.
    private func deleteCopies(_ removed: [ShelfItem]) {
        let urls = removed.filter(\.isOwnCopy).compactMap(\.fileURL)
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in urls {
                // Each copy sits in a folder of its own.
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        }
    }

    func removeExpired() {
        guard let interval = settings[ShelfSettings.autoClear].interval else { return }
        let cutoff = now().addingTimeInterval(-interval)
        let expired = Set(items.filter { $0.addedAt < cutoff }.map(\.id))
        if !expired.isEmpty {
            remove(expired)
        }
        scheduleExpiry()
    }

    /// One sleep until the oldest item expires (no polling).
    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard folder != nil, let interval = settings[ShelfSettings.autoClear].interval,
              let oldest = items.map(\.addedAt).min()
        else { return }
        let wait = max(oldest.addingTimeInterval(interval).timeIntervalSince(now()), 1)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.removeExpired()
        }
    }

    private func changed() {
        onChange?(items)
        scheduleExpiry()
    }

    // MARK: Actions

    func copy(_ selection: [ShelfItem]) {
        let files = selection.compactMap(\.fileURL)
        if !files.isEmpty {
            pasteboard.write(PasteboardContents(fileURLs: files, types: ["public.file-url"]))
        } else if selection.count == 1, case .link(let url) = selection[0].content {
            pasteboard.write(PasteboardContents(string: url.absoluteString, url: url, types: ["public.url", "public.utf8-plain-text"]))
        } else {
            pasteboard.copy(selection.compactMap(\.plainText).joined(separator: "\n"))
        }
        onEvent(.done(String(localized: "Copied"), symbol: "doc.on.doc"))
    }

    func copyPath(_ item: ShelfItem) {
        guard let url = item.fileURL else { return }
        pasteboard.copy(url.path)
        onEvent(.done(String(localized: "Path copied"), symbol: "doc.on.doc"))
    }

    func open(_ item: ShelfItem) {
        switch item.content {
        case .file(let url), .link(let url):
            _ = NSWorkspace.shared.open(url)
        case .text:
            break
        }
    }

    func open(_ item: ShelfItem, with app: URL) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Apps that can open the file, the default first.
    func apps(for item: ShelfItem) -> [URL] {
        guard let url = item.fileURL else { return [] }
        return Array(NSWorkspace.shared.urlsForApplications(toOpen: url).prefix(12))
    }

    func reveal(_ selection: [ShelfItem]) {
        let urls = selection.compactMap(\.fileURL)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Sends files and links over AirDrop (text goes as a file-less item too).
    func airDrop(_ selection: [ShelfItem]) {
        let shareable: [Any] = selection.map { item -> Any in
            switch item.content {
            case .file(let url), .link(let url):
                return url
            case .text(let text):
                return text
            }
        }
        Self.airDrop(shareable)
    }

    static func airDrop(_ items: [Any]) {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: items)
    }

    func rename(_ item: ShelfItem, to proposed: String) throws {
        guard let url = item.fileURL, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard let name = FileActions.renamedFileName(proposed, original: url) else { throw ShelfError.invalidName }
        let destination = url.deletingLastPathComponent().appendingPathComponent(name)
        guard destination != url else { return }
        if FileManager.default.fileExists(atPath: destination.path),
           destination.path.lowercased() != url.path.lowercased() {
            throw ShelfError.nameTaken(name)
        }
        try FileManager.default.moveItem(at: url, to: destination)
        items[index].content = .file(destination)
        changed()
    }

    /// Where a file made from `item` goes: next to the user's file, or in the Shelf's
    /// folder for its own copies.
    private func outputFolder(for item: ShelfItem) throws -> URL {
        guard let url = item.fileURL else { throw ShelfError.failed(String(localized: "That isn't a file.")) }
        if item.isOwnCopy || !FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path) {
            guard let folder else { throw ShelfError.failed(String(localized: "The Shelf isn't running.")) }
            let holder = folder.appendingPathComponent("Files", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: holder, withIntermediateDirectories: true)
            return holder
        }
        return url.deletingLastPathComponent()
    }

    /// Adds a file an action made, right after the item it came from.
    private func addResult(_ url: URL, after item: ShelfItem, symbol: String) {
        let isOwnCopy = folder.map { url.path.hasPrefix($0.path) } ?? false
        let result = ShelfItem(content: .file(url), addedAt: now(), isOwnCopy: isOwnCopy)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.insert(result, at: index + 1)
        } else {
            items.append(result)
        }
        changed()
        onEvent(.done(url.lastPathComponent, symbol: symbol))
    }

    func compress(_ item: ShelfItem) async {
        guard let url = item.fileURL else { return }
        do {
            let output = try outputFolder(for: item)
            let zip = try await Task.detached(priority: .userInitiated) { try FileActions.compress(url, into: output) }.value
            addResult(zip, after: item, symbol: "doc.zipper")
        } catch {
            onEvent(.problem(error.localizedDescription))
        }
    }

    func convert(_ item: ShelfItem, to format: ShelfImageFormat, halfSize: Bool = false) async {
        guard let url = item.fileURL, item.isImage else {
            onEvent(.problem(ShelfError.notAnImage.localizedDescription))
            return
        }
        do {
            let output = try outputFolder(for: item)
            let converted = try await Task.detached(priority: .userInitiated) {
                let maxPixels = halfSize ? FileActions.halfSize(of: url) : nil
                return try FileActions.convertImage(url, to: format, maxPixels: maxPixels, into: output)
            }.value
            addResult(converted, after: item, symbol: "photo")
        } catch {
            onEvent(.problem(error.localizedDescription))
        }
    }

    var pdfs: [ShelfItem] { items.filter(\.isPDF) }

    func mergePDFs() async {
        let pdfs = pdfs
        guard let first = pdfs.first, pdfs.count >= 2 else {
            onEvent(.problem(ShelfError.needsTwoPDFs.localizedDescription))
            return
        }
        let sources = pdfs.compactMap(\.fileURL)
        do {
            let output = try outputFolder(for: first)
            let merged = try await Task.detached(priority: .userInitiated) { try FileActions.mergePDFs(sources, into: output) }.value
            addResult(merged, after: pdfs[pdfs.count - 1], symbol: "doc.on.doc")
        } catch {
            onEvent(.problem(error.localizedDescription))
        }
    }

    /// What dragging an item out of the Shelf carries.
    static func provider(for item: ShelfItem) -> NSItemProvider {
        switch item.content {
        case .file(let url): NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
        case .link(let url): NSItemProvider(object: url as NSURL)
        case .text(let text): NSItemProvider(object: text as NSString)
        }
    }
}
