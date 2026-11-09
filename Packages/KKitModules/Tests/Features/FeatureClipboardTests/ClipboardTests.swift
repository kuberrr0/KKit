import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureClipboard

private func change(_ contents: PasteboardContents, from bundleID: String? = "com.apple.TextEdit", count: Int = 1, date: Date = Date()) -> PasteboardChange {
    PasteboardChange(changeCount: count, contents: contents, sourceBundleID: bundleID, sourceAppName: "TextEdit", date: date)
}

private func makeStore() throws -> ClipboardStore {
    let images = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardTests-\(UUID().uuidString)", isDirectory: true)
    let db = try InMemoryStorageService().openDatabase(named: "history", for: "clipboard")
    return try ClipboardStore(db: db, imagesDirectory: images)
}

private func draft(_ text: String, kind: ClipboardKind = .text, date: Date = Date()) -> ClipboardDraft {
    ClipboardDraft(kind: kind, text: text, date: date)
}

struct ClipboardFilterTests {
    private let rules = ClipboardRules()

    @Test func skipsPasswordsAndIgnoredApps() {
        let concealed = PasteboardContents(string: "hunter2", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
        #expect(ClipboardFilter.draft(from: change(concealed), rules: rules) == nil)
        #expect(ClipboardFilter.draft(from: change(.text("secret"), from: "com.bitwarden.desktop"), rules: rules) == nil)
        #expect(ClipboardFilter.draft(from: change(.text("   ")), rules: rules) == nil)
    }

    @Test func recognisesKinds() {
        #expect(ClipboardFilter.draft(from: change(.text("hello")), rules: rules)?.kind == .text)
        #expect(ClipboardFilter.draft(from: change(.text("https://example.com/a")), rules: rules)?.kind == .link)
        #expect(ClipboardFilter.draft(from: change(.text("#FF8800")), rules: rules)?.kind == .color)
        let rich = PasteboardContents(string: "bold", rtf: Data("{\\rtf1 bold}".utf8), types: ["public.rtf"])
        #expect(ClipboardFilter.draft(from: change(rich), rules: rules)?.kind == .richText)
        let files = PasteboardContents(fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")], types: ["public.file-url"])
        let fileDraft = ClipboardFilter.draft(from: change(files), rules: rules)
        #expect(fileDraft?.kind == .files)
        #expect(fileDraft?.text == "/tmp/a.txt")
        let image = PasteboardContents(image: Data([1, 2, 3]), imageType: "public.png", types: ["public.png"])
        #expect(ClipboardFilter.draft(from: change(image), rules: rules)?.kind == .image)
    }

    @Test func honoursTheTypeSettings() {
        var rules = ClipboardRules()
        rules.keepsImages = false
        rules.keepsRichText = false
        let image = PasteboardContents(image: Data([1]), imageType: "public.png", types: ["public.png"])
        #expect(ClipboardFilter.draft(from: change(image), rules: rules) == nil)
        let rich = PasteboardContents(string: "bold", rtf: Data("{\\rtf1 bold}".utf8), types: ["public.rtf"])
        #expect(ClipboardFilter.draft(from: change(rich), rules: rules)?.kind == .text)
    }

    @Test func linksAreSingleURLs() {
        #expect(ClipboardFilter.isLink("https://kkit.app"))
        #expect(ClipboardFilter.isLink("mailto:me@example.com"))
        #expect(!ClipboardFilter.isLink("https://kkit.app and more"))
        #expect(!ClipboardFilter.isLink("hello"))
        #expect(!ClipboardFilter.isLink("file:///etc/hosts"))
    }

    @Test func richAndPlainCopiesOfTheSameWordsMatch() {
        #expect(draft("same", kind: .richText).contentHash == draft("same").contentHash)
        #expect(draft("same").contentHash != draft("other").contentHash)
    }
}

struct ClipboardStoreTests {
    @Test func copyingAgainMovesToTheTop() async throws {
        let store = try makeStore()
        let first = try await store.insert(draft("alpha", date: Date(timeIntervalSince1970: 100)))
        _ = try await store.insert(draft("beta", date: Date(timeIntervalSince1970: 200)))
        let again = try await store.insert(draft("alpha", date: Date(timeIntervalSince1970: 300)))
        #expect(again?.id == first?.id)
        #expect(try await store.count() == 2)
        #expect(try await store.recent(limit: 10).map(\.text) == ["alpha", "beta"])
    }

    @Test func searchesText() async throws {
        let store = try makeStore()
        _ = try await store.insert(draft("The quick brown fox"))
        _ = try await store.insert(draft("lazy dog"))
        _ = try await store.insert(draft("https://example.com/fox", kind: .link))
        let foxes = try await store.search("fox", limit: 10)
        #expect(Set(foxes.map(\.text)) == ["The quick brown fox", "https://example.com/fox"])
        let links = try await store.search("fox", limit: 10, kinds: [.link])
        #expect(links.map(\.text) == ["https://example.com/fox"])
        #expect(try await store.search("qui bro", limit: 10).map(\.text) == ["The quick brown fox"])
        #expect(try await store.search("50%_", limit: 10).isEmpty)
    }

    @Test func pinnedItemsSurviveClearingAndTrimming() async throws {
        let store = try makeStore()
        let old = Date(timeIntervalSince1970: 0)
        let pinned = try #require(try await store.insert(draft("keep me", date: old)))
        try await store.setPinned(pinned.id, true)
        _ = try await store.insert(draft("old", date: old))
        for index in 0..<5 {
            _ = try await store.insert(draft("new \(index)", date: Date(timeIntervalSince1970: 1000 + Double(index))))
        }
        let removed = try await store.trim(maxItems: 3, maxAge: 500, now: Date(timeIntervalSince1970: 1010))
        #expect(removed == 3)
        let left = try await store.recent(limit: 10).map(\.text)
        #expect(left.contains("keep me"))
        #expect(!left.contains("old"))
        #expect(left.count == 4)
        try await store.clear(keepPinned: true)
        #expect(try await store.recent(limit: 10).map(\.text) == ["keep me"])
        #expect(try await store.recent(limit: 10, pinnedOnly: true).count == 1)
        try await store.clear(keepPinned: false)
        #expect(try await store.count() == 0)
    }

    @Test func storesImagesAsFiles() async throws {
        let store = try makeStore()
        var image = draft("", kind: .image)
        image.imageData = Data([0x89, 0x50, 0x4E, 0x47])
        image.imageType = "public.png"
        let item = try #require(try await store.insert(image))
        #expect(item.imageFile != nil)
        #expect(await store.imageData(for: item) == Data([0x89, 0x50, 0x4E, 0x47]))
        try await store.delete(item.id)
        #expect(try await store.count() == 0)
    }
}

struct SnippetTests {
    private let date: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 14, minute: 5))!
    }()

    private func expand(_ template: String, clipboard: String? = nil) -> String {
        SnippetExpander.expand(template, date: date, clipboard: clipboard, timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_US_POSIX"))
    }

    @Test func fillsPlaceholders() {
        #expect(expand("Today is {date} at {time}") == "Today is 2026-11-09 at 14:05")
        #expect(expand("{datetime}") == "2026-11-09 14:05")
        #expect(expand("{date:EEEE d MMMM}") == "Monday 9 November")
        #expect(expand("Re: {clipboard}", clipboard: "hello") == "Re: hello")
        #expect(expand("{{date}} {unknown}") == "{date} {unknown}")
        #expect(expand("{uuid}").count == 36)
    }
}

struct PasteStackTests {
    @Test func pastesInOrderThenEnds() {
        var stack = PasteStack()
        stack.push(1)
        #expect(stack.isEmpty)
        stack.start()
        stack.push(1)
        stack.push(2)
        stack.push(1)
        #expect(stack.items == [2, 1])
        #expect(stack.popNext() == 2)
        #expect(stack.isCollecting)
        #expect(stack.popNext() == 1)
        #expect(!stack.isCollecting)
        #expect(stack.popNext() == nil)
    }
}

@MainActor
struct ClipboardControllerTests {
    private func makeController() async throws -> (TestEnvironment, ClipboardController) {
        let environment = TestEnvironment()
        let context = environment.makeContext(for: ClipboardFeature.manifest.id)
        let controller = ClipboardController(settings: context.settings, pasteboard: environment.pasteboard)
        await controller.attach(try makeStore())
        return (environment, controller)
    }

    @Test func savesCopiesAndSkipsWhenPaused() async throws {
        let (environment, controller) = try await makeController()
        await controller.handle(change(.text("one"), count: 1))
        #expect(controller.recent.map(\.text) == ["one"])
        #expect(controller.itemCount == 1)
        controller.isPaused = true
        await controller.handle(change(.text("two"), count: 2))
        #expect(controller.itemCount == 1)
        _ = environment
    }

    @Test func pastingWritesAndDoesNotRecordItself() async throws {
        let (environment, controller) = try await makeController()
        await controller.handle(change(.text("hello"), count: 1))
        let item = try #require(controller.recent.first)
        #expect(await controller.paste(item, plain: true))
        #expect(environment.pasteboard.pasteCount == 1)
        #expect(environment.pasteboard.writes.last?.string == "hello")
        // The clipboard change our own write causes isn't saved again.
        await controller.handle(change(.text("hello"), count: environment.pasteboard.changeCount))
        #expect(controller.itemCount == 1)
    }

    @Test func pasteStackCollectsCopiesInOrder() async throws {
        let (environment, controller) = try await makeController()
        controller.toggleStack()
        await controller.handle(change(.text("first"), count: 1))
        await controller.handle(change(.text("second"), count: 2))
        #expect(controller.stack.count == 2)
        await controller.pasteNext()
        #expect(environment.pasteboard.writes.last?.string == "first")
        await controller.pasteNext()
        #expect(environment.pasteboard.writes.last?.string == "second")
        #expect(!controller.stack.isCollecting)
    }

    @Test func snippetsMatchByKeywordAndName() async throws {
        let (_, controller) = try await makeController()
        var saved: [Snippet] = []
        controller.onSnippetsChange = { saved = $0 }
        controller.loadSnippets([
            Snippet(name: "Email signature", keyword: "sig", text: "Best, KV"),
            Snippet(name: "Address", keyword: "addr", text: "1 Infinite Loop"),
        ])
        #expect(controller.matchingSnippets("sig").first?.snippet.name == "Email signature")
        #expect(controller.matchingSnippets("addr").first?.snippet.name == "Address")
        controller.addSnippet()
        #expect(saved.count == 3)
    }

    @Test func featureContributesCommands() {
        let environment = TestEnvironment()
        let feature = ClipboardFeature(context: environment.makeContext(for: ClipboardFeature.manifest.id))
        let ids = feature.commands.map(\.id.rawValue)
        #expect(ids.contains("clipboard.showHistory"))
        #expect(ids.allSatisfy { $0.hasPrefix("clipboard.") })
        #expect(feature.floatingBarModes.map(\.id) == [ClipboardFeature.pickerMode])
    }
}
