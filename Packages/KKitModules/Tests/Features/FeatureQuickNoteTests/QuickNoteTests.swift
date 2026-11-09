import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureQuickNote

/// 9 November 2026, 14:05 UTC.
private let noon: Date = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 14, minute: 5))!
}()

private let utc = TimeZone(identifier: "UTC")!

private func makeVault() throws -> URL {
    let vault = FileManager.default.temporaryDirectory.appendingPathComponent("QuickNoteTests-\(UUID().uuidString)/My Vault")
    try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    return vault
}

private func read(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}

struct EntryFormatterTests {
    private let values = NoteTemplate.values(date: noon, timeFormat: "HH:mm", timeZone: utc)

    @Test func fillsTheTemplate() {
        #expect(values == ["date": "2026-11-09", "time": "14:05"])
        #expect(EntryFormatter.entry("buy milk", template: "- {{time}} {{text}}", values: values, context: nil) == "- 14:05 buy milk")
        #expect(EntryFormatter.entry("idea", template: "- [ ] {{text}} ({{app}})", values: values, context: "Safari") == "- [ ] idea (Safari)")
        #expect(EntryFormatter.entry("idea", template: "- {{text}}", values: values, context: "Safari") == "- idea (from Safari)")
    }

    @Test func indentsLaterLinesUnderAListItem() {
        let entry = EntryFormatter.entry("first\nsecond\n\nthird", template: "- {{text}}", values: values, context: nil)
        #expect(entry == "- first\n  second\n\n  third")
        let plain = EntryFormatter.entry("first\nsecond", template: "{{text}}", values: values, context: nil)
        #expect(plain == "first\nsecond")
    }
}

struct MarkdownAppenderTests {
    @Test func appendsAtTheEnd() {
        #expect(MarkdownAppender.append("- a", to: "", heading: nil) == "- a\n")
        #expect(MarkdownAppender.append("- b", to: "# Inbox\n- a", heading: nil) == "# Inbox\n- a\n- b\n")
        #expect(MarkdownAppender.append("- b", to: "- a\r\n", heading: nil) == "- a\r\n- b\r\n")
    }

    @Test func appendsAtTheEndOfASection() {
        let document = """
        ---
        tags: [daily]
        ---
        # 2026-11-09

        ## Notes
        - first

        ## Tasks
        - [ ] thing
        """
        let updated = MarkdownAppender.append("- second", to: document, heading: "Notes")
        #expect(updated == """
        ---
        tags: [daily]
        ---
        # 2026-11-09

        ## Notes
        - first
        - second

        ## Tasks
        - [ ] thing

        """)
    }

    @Test func addsAMissingHeading() {
        let updated = MarkdownAppender.append("- a", to: "# Day\nsome text\n", heading: "### Log")
        #expect(updated == "# Day\nsome text\n\n### Log\n- a\n")
        #expect(MarkdownAppender.append("- a", to: "", heading: "Inbox") == "## Inbox\n- a\n")
    }

    @Test func keepsWindowsLineEndings() {
        let updated = MarkdownAppender.append("- b", to: "## Inbox\r\n- a\r\n", heading: "inbox")
        #expect(updated == "## Inbox\r\n- a\r\n- b\r\n")
    }
}

struct NotePathTests {
    @Test func expandsDatePatterns() {
        #expect(NotePaths.daily("Daily/{yyyy}/{yyyy-MM-dd}.md", date: noon, timeZone: utc) == "Daily/2026/2026-11-09.md")
        #expect(NotePaths.daily("Journal/{yyyy-MM-dd} {EEEE}", date: noon, timeZone: utc) == "Journal/2026-11-09 Monday.md")
    }

    @Test func staysInsideTheVault() throws {
        let vault = URL(fileURLWithPath: "/tmp/vault")
        #expect(try NotePaths.resolve("Inbox.md", in: vault).path == "/tmp/vault/Inbox.md")
        #expect(try NotePaths.resolve("./Notes/a.md", in: vault).path == "/tmp/vault/Notes/a.md")
        #expect(throws: NotePaths.PathError.self) { try NotePaths.resolve("../secrets.md", in: vault) }
        #expect(throws: NotePaths.PathError.self) { try NotePaths.resolve("/etc/hosts", in: vault) }
    }

    @Test func makesSafeFileNames() {
        #expect(NoteFileName.from("# Meeting: Q4 / plans?") == "Meeting Q4 plans")
        #expect(NoteFileName.from("   ") == "Untitled")
        #expect(NoteFileName.from(".hidden") == "hidden")
        #expect(NoteFileName.from(String(repeating: "a", count: 200)).count == 80)
        let folder = URL(fileURLWithPath: "/tmp/notes")
        let taken: Set<String> = ["/tmp/notes/Idea.md", "/tmp/notes/Idea 2.md"]
        let unique = NoteFileName.unique("Idea", in: folder) { taken.contains($0.path) }
        #expect(unique.lastPathComponent == "Idea 3.md")
    }

    @Test func buildsObsidianLinks() {
        let vault = URL(fileURLWithPath: "/Users/kv/My Vault")
        let link = ObsidianLink.open(file: vault.appendingPathComponent("Daily/2026 & co.md"), in: vault)
        #expect(link?.absoluteString == "obsidian://open?vault=My%20Vault&file=Daily%2F2026%20%26%20co")
    }

    @Test func cyclesTargets() {
        #expect(NoteTargetKind.inbox.next(1) == .daily)
        #expect(NoteTargetKind.inbox.next(-1) == .newNote)
        #expect(NoteTargetKind.newNote.next(1) == .inbox)
    }
}

struct NoteWriterTests {
    private func request(_ text: String, _ target: NoteTargetKind, vault: URL, configuration: NoteConfiguration = NoteConfiguration()) -> NoteRequest {
        NoteRequest(text: text, target: target, vault: vault, configuration: configuration, date: noon, appName: "Safari", timeZone: utc)
    }

    @Test func appendsToTheInbox() async throws {
        let vault = try makeVault()
        let writer = NoteWriter()
        let file = try await writer.save(request("one", .inbox, vault: vault))
        _ = try await writer.save(request("two", .inbox, vault: vault))
        #expect(file.lastPathComponent == "Inbox.md")
        #expect(try read(file) == "- 14:05 one\n- 14:05 two\n")
    }

    @Test func createsTheDailyNoteFromItsTemplate() async throws {
        let vault = try makeVault()
        var configuration = NoteConfiguration()
        configuration.dailyHeading = "Log"
        configuration.includeContext = true
        let file = try await NoteWriter().save(request("called mum", .daily, vault: vault, configuration: configuration))
        #expect(NotePaths.relativePath(of: file, in: vault) == "Daily/2026/2026-11-09.md")
        #expect(try read(file) == "# 2026-11-09\n\n## Log\n- 14:05 called mum (from Safari)\n")
    }

    @Test func newNotesTakeTheirTitleFromTheFirstLine() async throws {
        let vault = try makeVault()
        let writer = NoteWriter()
        let first = try await writer.save(request("Big idea\n\nDetails here.", .newNote, vault: vault))
        let second = try await writer.save(request("Big idea", .newNote, vault: vault))
        #expect(NotePaths.relativePath(of: first, in: vault) == "Notes/Big idea.md")
        #expect(second.lastPathComponent == "Big idea 2.md")
        #expect(try read(first) == "# Big idea\n\nDetails here.\n")
    }

    @Test func listsNoteNamesForLinks() async throws {
        let vault = try makeVault()
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try Data().write(to: vault.appendingPathComponent(".obsidian/workspace.md"))
        try Data().write(to: vault.appendingPathComponent("Zebra.md"))
        try Data().write(to: vault.appendingPathComponent("apple.md"))
        try Data().write(to: vault.appendingPathComponent("image.png"))
        #expect(await NoteWriter().noteNames(in: vault) == ["apple", "Zebra"])
    }
}

@MainActor
struct QuickNoteFeatureTests {
    @Test func appendCommandWritesToTheVault() async throws {
        let environment = TestEnvironment()
        let feature = QuickNoteFeature(context: environment.makeContext(for: "quickNote"))
        try await feature.start()
        let vault = try makeVault()
        feature.controller.setVault(vault)
        feature.controller.now = { noon }
        feature.controller.frontmostAppName = { nil }

        let found: Command? = feature.commands.first { $0.id == "quickNote.append" }
        let command = try #require(found)
        try await command.perform(CommandInvocation(argument: .text("call the dentist")))
        let inbox = try read(vault.appendingPathComponent("Inbox.md"))
        #expect(inbox.hasSuffix(" call the dentist\n"))
        #expect(environment.island.huds.last?.title == "Saved to Inbox")

        let published = environment.services.resolve((any QuickNoteServicing).self)
        #expect(published != nil)
        await feature.stop()
        #expect(environment.services.resolve((any QuickNoteServicing).self) == nil)
    }

    @Test func savingWithoutAVaultExplains() async {
        let environment = TestEnvironment()
        let controller = QuickNoteController(settings: FeatureSettings(featureID: "quickNote", store: environment.settings))
        controller.draft = "hello"
        let saved = await controller.saveDraft(openInObsidian: false)
        #expect(!saved)
        #expect(controller.errorMessage == NoteError.noVault.errorDescription)
        #expect(controller.draft == "hello")
    }

    @Test func saveAndOpenUsesAnObsidianLink() async throws {
        let environment = TestEnvironment()
        let controller = QuickNoteController(settings: FeatureSettings(featureID: "quickNote", store: environment.settings))
        let vault = try makeVault()
        controller.setVault(vault)
        var opened: [URL] = []
        controller.openURL = { opened.append($0) }
        controller.frontmostAppName = { nil }
        controller.draft = "Plan\nsteps"
        controller.target = .newNote
        let saved = await controller.saveDraft(openInObsidian: true)
        #expect(saved)
        #expect(controller.draft.isEmpty)
        #expect(opened.map(\.absoluteString) == ["obsidian://open?vault=My%20Vault&file=Notes%2FPlan"])
    }

    @Test func editorModeAndSendToNote() {
        let environment = TestEnvironment()
        let feature = QuickNoteFeature(context: environment.makeContext(for: "quickNote"))
        #expect(feature.floatingBarModes.map(\.prefix) == ["n "])
        let link = SearchResult(id: "x", title: "Swift", icon: .symbol("globe"), score: 1, kind: .url(URL(string: "https://swift.org")!))
        #expect(QuickNoteFeature.noteText(for: link) == "[Swift](https://swift.org)")
    }
}
