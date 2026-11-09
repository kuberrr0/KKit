import Foundation
import KKitCore
import KKitServicesAPI
import Observation

/// Things the feature shows in the Island or reports.
enum ClipboardEvent: Sendable {
    case saved(ClipboardItem)
    case pasted(ClipboardItem?)
    case stackChanged
    case problem(String)
}

/// Watches the clipboard, saves what the rules allow, and pastes items back. The
/// picker, the `c ` provider and the commands all go through it.
@MainActor
@Observable
final class ClipboardController {
    /// The newest items, for the picker's first screen.
    private(set) var recent: [ClipboardItem] = []
    private(set) var itemCount = 0
    private(set) var stack = PasteStack()
    private(set) var snippets: [Snippet] = []

    @ObservationIgnored let settings: FeatureSettings
    @ObservationIgnored let pasteboard: any PasteboardService
    @ObservationIgnored private(set) var store: ClipboardStore?
    @ObservationIgnored private(set) var imagesDirectory: URL?
    @ObservationIgnored var onEvent: @MainActor (ClipboardEvent) -> Void = { _ in }
    @ObservationIgnored var onSnippetsChange: (@MainActor ([Snippet]) -> Void)?
    /// The change count after KKit's own write, so pasting from history isn't saved again.
    @ObservationIgnored private var ownChangeCount: Int?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?

    static let recentLimit = 200

    init(settings: FeatureSettings, pasteboard: any PasteboardService) {
        self.settings = settings
        self.pasteboard = pasteboard
    }

    var isPaused: Bool {
        get { settings[ClipboardSettings.paused] }
        set { settings[ClipboardSettings.paused] = newValue }
    }

    // MARK: Lifecycle

    func attach(_ store: ClipboardStore) async {
        self.store = store
        imagesDirectory = store.imagesDirectory
        await trim()
        await reload()
    }

    func startMonitoring() {
        monitorTask?.cancel()
        let changes = pasteboard.changes()
        monitorTask = Task { [weak self] in
            for await change in changes {
                guard let self else { return }
                await self.handle(change)
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        stack.stop()
    }

    func detach() {
        stopMonitoring()
        store = nil
        recent = []
    }

    // MARK: Saving

    func handle(_ change: PasteboardChange) async {
        guard let store, !isPaused else { return }
        if let ownChangeCount, change.changeCount == ownChangeCount {
            return
        }
        guard let draft = ClipboardFilter.draft(from: change, rules: ClipboardSettings.rules(settings)) else { return }
        do {
            guard let item = try await store.insert(draft) else { return }
            if stack.isCollecting {
                stack.push(item.id)
                onEvent(.stackChanged)
            }
            await trim()
            await reload()
            onEvent(.saved(item))
        } catch {
            onEvent(.problem(error.localizedDescription))
        }
    }

    func trim() async {
        guard let store else { return }
        let maxItems = settings[ClipboardSettings.maxItems]
        let maxAge = settings[ClipboardSettings.retention].seconds
        _ = try? await store.trim(maxItems: maxItems, maxAge: maxAge)
    }

    func reload() async {
        guard let store else { return }
        recent = (try? await store.recent(limit: Self.recentLimit)) ?? []
        itemCount = (try? await store.count()) ?? recent.count
    }

    // MARK: Reading

    func search(_ query: String, kinds: Set<ClipboardKind>? = nil, pinnedOnly: Bool = false, limit: Int = 100) async -> [ClipboardItem] {
        guard let store else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, kinds == nil, !pinnedOnly, limit <= recent.count {
            return Array(recent.prefix(limit))
        }
        return (try? await store.search(trimmed, limit: limit, kinds: kinds, pinnedOnly: pinnedOnly)) ?? []
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let name = item.imageFile else { return nil }
        return imagesDirectory?.appendingPathComponent(name)
    }

    func item(_ id: Int64) async -> ClipboardItem? {
        try? await store?.item(id)
    }

    /// Snippets matching `query` by name, keyword or text, best first.
    func matchingSnippets(_ query: String) -> [SnippetMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return snippets.map { SnippetMatch(snippet: $0, score: 0.5) } }
        return snippets.compactMap { snippet -> SnippetMatch? in
            let keywords = snippet.keyword.isEmpty ? [snippet.text] : [snippet.keyword, snippet.text]
            guard let score = FuzzyMatch.score(trimmed, title: snippet.name, keywords: keywords) else { return nil }
            return SnippetMatch(snippet: snippet, score: score)
        }
        .sorted { $0.score > $1.score }
    }

    // MARK: Pasting

    /// Puts the item back on the clipboard and pastes it into the app in front.
    /// Without Accessibility it stays copied and a HUD says so. Returns whether it
    /// pasted.
    @discardableResult
    func paste(_ item: ClipboardItem, plain: Bool = false) async -> Bool {
        await copy(item, plain: plain)
        return await sendPaste(item)
    }

    private func sendPaste(_ item: ClipboardItem?) async -> Bool {
        do {
            try await pasteboard.paste()
            onEvent(.pasted(item))
            return true
        } catch {
            onEvent(.problem(error.localizedDescription))
            return false
        }
    }

    func copy(_ item: ClipboardItem, plain: Bool = false) async {
        var data: Data?
        if item.kind == .image, let store {
            data = await store.imageData(for: item)
        }
        write(item.contents(imageData: data, plain: plain))
        try? await store?.markUsed(item.id)
        await reload()
    }

    @discardableResult
    func pasteSnippet(_ snippet: Snippet) async -> Bool {
        let current = pasteboard.read().string
        let text = SnippetExpander.expand(snippet.text, clipboard: current)
        write(.text(text))
        return await sendPaste(nil)
    }

    private func write(_ contents: PasteboardContents) {
        pasteboard.write(contents)
        ownChangeCount = pasteboard.changeCount
    }

    // MARK: Editing

    func togglePin(_ item: ClipboardItem) async {
        try? await store?.setPinned(item.id, !item.isPinned)
        await reload()
    }

    func delete(_ item: ClipboardItem) async {
        try? await store?.delete(item.id)
        await reload()
    }

    func clear(keepPinned: Bool = true) async {
        try? await store?.clear(keepPinned: keepPinned)
        stack.stop()
        await reload()
    }

    // MARK: Paste stack

    func toggleStack() {
        if stack.isCollecting {
            stack.stop()
        } else {
            stack.start()
        }
        onEvent(.stackChanged)
    }

    /// Pastes the oldest item on the stack and removes it.
    func pasteNext() async {
        guard stack.isCollecting else {
            onEvent(.problem(ClipboardError.stackNotStarted.localizedDescription))
            return
        }
        guard let id = stack.popNext() else {
            onEvent(.problem(ClipboardError.stackEmpty.localizedDescription))
            return
        }
        onEvent(.stackChanged)
        guard let item = await item(id) else { return }
        await paste(item)
    }

    // MARK: Snippets

    func loadSnippets(_ snippets: [Snippet]) {
        self.snippets = snippets
    }

    @discardableResult
    func addSnippet() -> Snippet {
        let snippet = Snippet(name: String(localized: "New Snippet"), text: "")
        snippets.append(snippet)
        onSnippetsChange?(snippets)
        return snippet
    }

    func updateSnippet(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        onSnippetsChange?(snippets)
    }

    func removeSnippet(_ id: Snippet.ID) {
        snippets.removeAll { $0.id == id }
        onSnippetsChange?(snippets)
    }
}

struct SnippetMatch {
    let snippet: Snippet
    let score: Double
}

enum ClipboardError: LocalizedError {
    case stackNotStarted
    case stackEmpty
    case nothingCopied

    var errorDescription: String? {
        switch self {
        case .stackNotStarted: String(localized: "Start a paste stack first, then copy a few things.")
        case .stackEmpty: String(localized: "The paste stack is empty.")
        case .nothingCopied: String(localized: "Nothing has been copied yet.")
        }
    }
}
