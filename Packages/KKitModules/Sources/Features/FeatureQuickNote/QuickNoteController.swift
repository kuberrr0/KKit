import AppKit
import KKitCore
import KKitServicesAPI
import Observation

/// The editor's state and everything that saves notes. Published to other features as
/// `QuickNoteServicing` ("Send to note").
@MainActor
@Observable
final class QuickNoteController: QuickNoteServicing {
    /// What's typed in the editor; kept when the bar closes, cleared after saving.
    var draft = ""
    var target: NoteTargetKind
    var errorMessage: String?
    private(set) var isSaving = false

    let settings: FeatureSettings
    let writer = NoteWriter()
    /// Opens the editor in the Floating Bar.
    @ObservationIgnored var showEditor: @MainActor (String?) -> Void = { _ in }
    /// After a save: "Saved to Inbox".
    @ObservationIgnored var onSaved: @MainActor (NoteTargetKind, URL) -> Void = { _, _ in }
    @ObservationIgnored var frontmostAppName: @MainActor () -> String? = {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
    @ObservationIgnored var openURL: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    @ObservationIgnored var now: @MainActor () -> Date = { Date() }
    @ObservationIgnored private var cachedNames: [String] = []

    init(settings: FeatureSettings) {
        self.settings = settings
        target = settings[QuickNoteSettings.defaultTarget]
    }

    // MARK: Vault

    /// The vault folder: the bookmark if it still resolves (the folder may have moved),
    /// otherwise the saved path.
    func vaultURL() throws -> URL {
        let path = settings[QuickNoteSettings.vaultPath]
        guard !path.isEmpty else { throw NoteError.noVault }
        let bookmark = settings[QuickNoteSettings.vaultBookmark]
        var url = URL(fileURLWithPath: path, isDirectory: true)
        if !bookmark.isEmpty {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                url = resolved
                if stale || resolved.path != path {
                    setVault(resolved)
                }
            }
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NoteError.vaultMissing(url.path)
        }
        return url
    }

    var hasVault: Bool {
        !settings[QuickNoteSettings.vaultPath].isEmpty
    }

    func setVault(_ url: URL) {
        settings[QuickNoteSettings.vaultPath] = url.path
        settings[QuickNoteSettings.vaultBookmark] = (try? url.bookmarkData()) ?? Data()
    }

    var configuration: NoteConfiguration {
        NoteConfiguration(
            inboxPath: settings[QuickNoteSettings.inboxPath],
            inboxHeading: settings[QuickNoteSettings.inboxHeading],
            dailyPattern: settings[QuickNoteSettings.dailyPattern],
            dailyTemplate: settings[QuickNoteSettings.dailyTemplate],
            dailyHeading: settings[QuickNoteSettings.dailyHeading],
            newNoteFolder: settings[QuickNoteSettings.newNoteFolder],
            newNoteTemplate: settings[QuickNoteSettings.newNoteTemplate],
            entryTemplate: settings[QuickNoteSettings.entryTemplate],
            timeFormat: settings[QuickNoteSettings.timeFormat],
            includeContext: settings[QuickNoteSettings.includeContext]
        )
    }

    /// The label for a target in the editor: the inbox file's name, "Daily Note"…
    func label(for kind: NoteTargetKind) -> String {
        guard kind == .inbox else { return kind.title }
        let name = (settings[QuickNoteSettings.inboxPath] as NSString).lastPathComponent
        return (name as NSString).deletingPathExtension.isEmpty ? kind.title : (name as NSString).deletingPathExtension
    }

    // MARK: Saving

    /// Saves `text` to `target` and returns the file.
    @discardableResult
    func save(_ text: String, to target: NoteTargetKind, openInObsidian: Bool) async throws -> URL {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NoteError.empty }
        let vault = try vaultURL()
        let request = NoteRequest(
            text: text,
            target: target,
            vault: vault,
            configuration: configuration,
            date: now(),
            appName: frontmostAppName()
        )
        let file = try await writer.save(request)
        if openInObsidian || settings[QuickNoteSettings.openAfterSave] {
            open(file, in: vault)
        }
        onSaved(target, file)
        return file
    }

    /// The editor's ⌘↵ / ⌘⇧↵.
    func saveDraft(openInObsidian: Bool) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await save(draft, to: target, openInObsidian: openInObsidian)
            draft = ""
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func openDailyNote() async throws {
        let vault = try vaultURL()
        let request = NoteRequest(text: "", target: .daily, vault: vault, configuration: configuration, date: now(), appName: nil)
        let file = try await writer.dailyNote(request)
        open(file, in: vault)
    }

    private func open(_ file: URL, in vault: URL) {
        if let link = ObsidianLink.open(file: file, in: vault) {
            openURL(link)
        }
    }

    // MARK: Links

    /// Note names for `[[` completion. Returns what's cached and refreshes it in the
    /// background, so typing never waits for the disk.
    func linkCandidates() -> [String] {
        if let vault = try? vaultURL() {
            let writer = writer
            Task { @MainActor [weak self] in
                let names = await writer.noteNames(in: vault)
                self?.cachedNames = names
            }
        }
        return cachedNames
    }

    func warmLinkCandidates() {
        _ = linkCandidates()
    }

    // MARK: QuickNoteServicing

    func append(_ text: String) async throws {
        try await save(text, to: settings[QuickNoteSettings.defaultTarget], openInObsidian: false)
    }

    func openEditor(with text: String) {
        if !text.isEmpty {
            draft = draft.isEmpty ? text : draft + "\n" + text
        }
        showEditor(nil)
    }
}
