import Foundation

/// What to save, worked out on the main actor.
struct NoteRequest: Sendable {
    var text: String
    var target: NoteTargetKind
    var vault: URL
    var configuration: NoteConfiguration
    var date: Date
    /// The app that was in front, when "include context" is on.
    var appName: String?
    var timeZone: TimeZone = .current
}

enum NoteError: LocalizedError, Equatable {
    case noVault
    case vaultMissing(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .noVault: String(localized: "Choose your Obsidian vault in Quick Note settings.")
        case .vaultMissing(let path): String(localized: "Your vault folder isn't there any more: \(path)")
        case .empty: String(localized: "Type a note first.")
        }
    }
}

/// Reads and writes the vault's files off the main thread. Every write is atomic, so
/// Obsidian (watching the folder) never sees half a file.
actor NoteWriter {
    private var namesCache: (vault: URL, names: [String], date: Date)?

    /// Saves the note and returns the file it went to.
    func save(_ request: NoteRequest) throws -> URL {
        let configuration = request.configuration
        var values = NoteTemplate.values(date: request.date, timeFormat: configuration.timeFormat, timeZone: request.timeZone)
        let context = configuration.includeContext ? request.appName : nil
        switch request.target {
        case .inbox:
            let file = try NotePaths.resolve(NotePaths.withMarkdownExtension(configuration.inboxPath), in: request.vault)
            let entry = EntryFormatter.entry(request.text, template: configuration.entryTemplate, values: values, context: context)
            try append(entry, to: file, heading: configuration.inboxHeading, initial: "")
            return file
        case .daily:
            let file = try dailyNote(request)
            let entry = EntryFormatter.entry(request.text, template: configuration.entryTemplate, values: values, context: context)
            try append(entry, to: file, heading: configuration.dailyHeading, initial: nil)
            return file
        case .newNote:
            let lines = request.text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
            let title = NoteFileName.from(lines.first ?? "")
            var body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .newlines)
            if let context {
                body += (body.isEmpty ? "" : "\n\n") + String(localized: "From \(context)")
            }
            values["title"] = title
            values["text"] = body
            values["app"] = context ?? ""
            let folder = try NotePaths.resolve(configuration.newNoteFolder, in: request.vault)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = NoteFileName.unique(title, in: folder) { FileManager.default.fileExists(atPath: $0.path) }
            try write(NoteTemplate.render(configuration.newNoteTemplate, values), to: file)
            return file
        }
    }

    /// Today's daily note, created from the template if it doesn't exist.
    func dailyNote(_ request: NoteRequest) throws -> URL {
        let configuration = request.configuration
        let path = NotePaths.daily(configuration.dailyPattern, date: request.date, timeZone: request.timeZone)
        let file = try NotePaths.resolve(path, in: request.vault)
        if !FileManager.default.fileExists(atPath: file.path) {
            var values = NoteTemplate.values(date: request.date, timeFormat: configuration.timeFormat, timeZone: request.timeZone)
            values["title"] = file.deletingPathExtension().lastPathComponent
            try write(NoteTemplate.render(configuration.dailyTemplate, values), to: file)
        }
        return file
    }

    /// Markdown file names in the vault (without ".md"), for `[[` completion. Skips
    /// hidden folders (.obsidian, .trash). Cached for a minute.
    func noteNames(in vault: URL, limit: Int = 5000) -> [String] {
        if let namesCache, namesCache.vault == vault, Date().timeIntervalSince(namesCache.date) < 60 {
            return namesCache.names
        }
        var names: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: vault,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        while let url = enumerator?.nextObject() as? URL, names.count < limit {
            if url.pathExtension.lowercased() == "md" {
                names.append(url.deletingPathExtension().lastPathComponent)
            }
        }
        names.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        namesCache = (vault, names, Date())
        return names
    }

    // MARK: Files

    /// - Parameter initial: what a missing file starts as; `nil` means it must exist.
    private func append(_ entry: String, to file: URL, heading: String, initial: String?) throws {
        let existing: String
        if FileManager.default.fileExists(atPath: file.path) {
            existing = try String(contentsOf: file, encoding: .utf8)
        } else {
            existing = initial ?? ""
        }
        let updated = MarkdownAppender.append(entry, to: existing, heading: heading.isEmpty ? nil : heading)
        try write(updated, to: file)
    }

    private func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file, options: .atomic)
    }
}
