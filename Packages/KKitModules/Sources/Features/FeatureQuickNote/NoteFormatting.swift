import Foundation

/// Where a note goes. DESIGN.md §3.11.
enum NoteTargetKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Append to one file (Inbox.md), optionally under a heading.
    case inbox
    /// Append to today's daily note, created from a template if missing.
    case daily
    /// A new file in a folder; the first line is the title.
    case newNote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: String(localized: "Inbox")
        case .daily: String(localized: "Daily Note")
        case .newNote: String(localized: "New Note")
        }
    }

    var symbol: String {
        switch self {
        case .inbox: "tray.and.arrow.down"
        case .daily: "calendar"
        case .newNote: "doc.badge.plus"
        }
    }

    func next(_ step: Int) -> NoteTargetKind {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + step % all.count + all.count) % all.count]
    }
}

/// The note settings, as one value the writer can take off the main actor.
struct NoteConfiguration: Sendable, Equatable {
    var inboxPath = "Inbox.md"
    var inboxHeading = ""
    var dailyPattern = "Daily/{yyyy}/{yyyy-MM-dd}.md"
    var dailyTemplate = "# {{date}}\n\n"
    var dailyHeading = ""
    var newNoteFolder = "Notes"
    var newNoteTemplate = "# {{title}}\n\n{{text}}\n"
    var entryTemplate = "- {{time}} {{text}}"
    var timeFormat = "HH:mm"
    var includeContext = false
}

/// `{{name}}` placeholders: date, time, title, text, app.
enum NoteTemplate {
    static func render(_ template: String, _ values: [String: String]) -> String {
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    static func values(date: Date, timeFormat: String, timeZone: TimeZone = .current) -> [String: String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = timeFormat.isEmpty ? "HH:mm" : timeFormat
        return ["date": day, "time": formatter.string(from: date)]
    }
}

/// One entry for an append target: the entry template with the text in it. Later lines
/// of a multi-line note are indented under a list item so they stay part of it.
enum EntryFormatter {
    static func entry(_ text: String, template: String, values: [String: String], context: String?) -> String {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var first = lines.first ?? ""
        var values = values
        values["app"] = context ?? ""
        if let context, !context.isEmpty, !template.contains("{{app}}") {
            first += " (\(String(localized: "from \(context)")))"
        }
        values["text"] = first
        let firstLine = NoteTemplate.render(template.contains("{{text}}") ? template : template + " {{text}}", values)
        let indent = isListItem(firstLine) ? "  " : ""
        let rest = lines.dropFirst().map { $0.isEmpty ? "" : indent + $0 }
        return ([firstLine] + rest).joined(separator: "\n")
    }

    static func isListItem(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return true
        }
        let digits = trimmed.prefix { $0.isNumber }
        return !digits.isEmpty && trimmed.dropFirst(digits.count).hasPrefix(". ")
    }
}

/// Paths inside the vault.
enum NotePaths {
    enum PathError: LocalizedError, Equatable {
        case outsideVault(String)

        var errorDescription: String? {
            switch self {
            case .outsideVault(let path):
                String(localized: "“\(path)” is outside your vault.")
            }
        }
    }

    /// `{…}` holds a date format: "Daily/{yyyy}/{yyyy-MM-dd}.md" → "Daily/2026/2026-11-09.md".
    static func daily(_ pattern: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        var result = ""
        var rest = pattern[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            result += rest[..<open]
            formatter.dateFormat = String(rest[rest.index(after: open)..<close])
            result += formatter.string(from: date)
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return withMarkdownExtension(result)
    }

    static func withMarkdownExtension(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        return (trimmed as NSString).pathExtension.isEmpty ? trimmed + ".md" : trimmed
    }

    /// `relative` inside `vault`, refusing "../" escapes and absolute paths.
    static func resolve(_ relative: String, in vault: URL) throws -> URL {
        let cleaned = relative.trimmingCharacters(in: .whitespaces)
        let components = cleaned.split(separator: "/").map(String.init)
        guard !cleaned.hasPrefix("/"), !cleaned.hasPrefix("~"), !components.contains("..") else {
            throw PathError.outsideVault(relative)
        }
        var url = vault
        for component in components where component != "." {
            url.appendPathComponent(component)
        }
        return url
    }

    /// The path of `file` inside `vault`: "Daily/2026/2026-11-09.md".
    static func relativePath(of file: URL, in vault: URL) -> String {
        let base = vault.standardizedFileURL.path
        let path = file.standardizedFileURL.path
        guard path.hasPrefix(base) else { return file.lastPathComponent }
        return String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

/// A file name from a note's first line.
enum NoteFileName {
    /// Without characters Obsidian or Finder reject, at most 80 characters.
    static func from(_ firstLine: String) -> String {
        var title = firstLine.trimmingCharacters(in: .whitespaces)
        while title.hasPrefix("#") {
            title.removeFirst()
        }
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
        title = String(String.UnicodeScalarView(title.unicodeScalars.filter { !forbidden.contains($0) }))
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while title.hasPrefix(".") {
            title.removeFirst()
        }
        if title.count > 80 {
            title = String(title.prefix(80)).trimmingCharacters(in: .whitespaces)
        }
        return title.isEmpty ? String(localized: "Untitled") : title
    }

    /// "Idea.md", or "Idea 2.md" if that's taken.
    static func unique(_ title: String, in folder: URL, exists: (URL) -> Bool) -> URL {
        var candidate = folder.appendingPathComponent(title + ".md")
        var number = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(title) \(number).md")
            number += 1
        }
        return candidate
    }
}

/// Adds an entry to a markdown document without disturbing the rest: the line endings
/// it uses, its frontmatter and every other section stay as they were.
enum MarkdownAppender {
    static func append(_ entry: String, to document: String, heading: String?) -> String {
        let newline = document.contains("\r\n") ? "\r\n" : "\n"
        let entryLines = entry.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let wantedHeading = heading?.trimmingCharacters(in: .whitespaces) ?? ""

        guard !wantedHeading.isEmpty else {
            var result = document
            if !result.isEmpty, !result.hasSuffix(newline) {
                result += newline
            }
            return result + entryLines.joined(separator: newline) + newline
        }

        var lines = document.isEmpty ? [] : document.components(separatedBy: newline)
        if lines.last == "" {
            lines.removeLast()
        }
        let (title, level) = parseHeading(wantedHeading) ?? (wantedHeading, 2)
        let bodyStart = frontmatterEnd(lines)

        if let headingIndex = lines.indices.dropFirst(bodyStart).first(where: { index in
            guard let found = parseHeading(lines[index]) else { return false }
            return found.title.caseInsensitiveCompare(title) == .orderedSame
        }) {
            let sectionLevel = parseHeading(lines[headingIndex])?.level ?? level
            var sectionEnd = lines.count
            for index in (headingIndex + 1)..<max(lines.count, headingIndex + 1) {
                if let other = parseHeading(lines[index]), other.level <= sectionLevel {
                    sectionEnd = index
                    break
                }
            }
            var insertAt = headingIndex + 1
            for index in stride(from: sectionEnd - 1, through: headingIndex + 1, by: -1)
            where !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                insertAt = index + 1
                break
            }
            lines.insert(contentsOf: entryLines, at: insertAt)
        } else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            }
            lines.append(String(repeating: "#", count: level) + " " + title)
            lines.append(contentsOf: entryLines)
        }
        return lines.joined(separator: newline) + newline
    }

    /// "## Inbox" → ("Inbox", 2). Up to six #s, then a space.
    static func parseHeading(_ line: String) -> (title: String, level: Int)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return (rest.trimmingCharacters(in: .whitespaces), hashes.count)
    }

    /// The first line after a leading `---` … `---` block.
    private static func frontmatterEnd(_ lines: [String]) -> Int {
        guard lines.first == "---" else { return 0 }
        for index in lines.indices.dropFirst() where lines[index] == "---" || lines[index] == "..." {
            return index + 1
        }
        return 0
    }
}

/// Links that open notes in Obsidian.
enum ObsidianLink {
    /// Only unreserved ASCII is left as is (Obsidian is strict about `&`, `+` and `/`).
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// `obsidian://open?vault=<name>&file=<path without .md>`.
    static func open(file: URL, in vault: URL) -> URL? {
        var relative = NotePaths.relativePath(of: file, in: vault)
        if relative.lowercased().hasSuffix(".md") {
            relative = String(relative.dropLast(3))
        }
        guard let name = vault.lastPathComponent.addingPercentEncoding(withAllowedCharacters: unreserved),
              let path = relative.addingPercentEncoding(withAllowedCharacters: unreserved)
        else { return nil }
        return URL(string: "obsidian://open?vault=\(name)&file=\(path)")
    }
}
