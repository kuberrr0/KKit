import Foundation

/// Saved text with placeholders, pasted from the clipboard picker or `c ` search.
struct Snippet: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Optional short word to find it by: "sig", "addr".
    var keyword: String
    var text: String

    init(id: UUID = UUID(), name: String, keyword: String = "", text: String) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.text = text
    }
}

/// Fills a snippet's placeholders:
/// `{date}` 2026-11-09 · `{time}` 14:05 · `{datetime}` · `{date:EEEE d MMMM}` any
/// date format · `{clipboard}` what's copied now · `{uuid}` · `{{` and `}}` for braces.
enum SnippetExpander {
    static let help = "{date} · {time} · {datetime} · {date:FORMAT} · {clipboard} · {uuid}"

    static func expand(
        _ template: String,
        date: Date = Date(),
        clipboard: String? = nil,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        var output = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            let next = template.index(after: index)
            if character == "{", next < template.endIndex, template[next] == "{" {
                output.append("{")
                index = template.index(after: next)
                continue
            }
            if character == "}", next < template.endIndex, template[next] == "}" {
                output.append("}")
                index = template.index(after: next)
                continue
            }
            guard character == "{", let close = template[next...].firstIndex(of: "}") else {
                output.append(character)
                index = next
                continue
            }
            let name = String(template[next..<close])
            if let value = value(for: name, date: date, clipboard: clipboard, timeZone: timeZone, locale: locale) {
                output.append(value)
            } else {
                output.append(contentsOf: template[index...close])
            }
            index = template.index(after: close)
        }
        return output
    }

    private static func value(for name: String, date: Date, clipboard: String?, timeZone: TimeZone, locale: Locale) -> String? {
        switch name {
        case "date": return format(date, "yyyy-MM-dd", timeZone: timeZone, locale: locale)
        case "time": return format(date, "HH:mm", timeZone: timeZone, locale: locale)
        case "datetime": return format(date, "yyyy-MM-dd HH:mm", timeZone: timeZone, locale: locale)
        case "clipboard": return clipboard ?? ""
        case "uuid": return UUID().uuidString
        default:
            if name.hasPrefix("date:") {
                let pattern = String(name.dropFirst("date:".count))
                return pattern.isEmpty ? nil : format(date, pattern, timeZone: timeZone, locale: locale)
            }
            return nil
        }
    }

    private static func format(_ date: Date, _ pattern: String, timeZone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = pattern.contains("E") || pattern.contains("MMM") ? locale : Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// The paste stack: copy several things, then paste them back in the same order.
struct PasteStack: Sendable, Equatable {
    private(set) var items: [Int64] = []
    private(set) var isCollecting = false

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    mutating func start() {
        items = []
        isCollecting = true
    }

    mutating func stop() {
        items = []
        isCollecting = false
    }

    /// A newly copied item joins the end of the stack.
    mutating func push(_ id: Int64) {
        guard isCollecting else { return }
        items.removeAll { $0 == id }
        items.append(id)
    }

    /// The next item to paste. The stack ends once it's empty.
    mutating func popNext() -> Int64? {
        guard isCollecting, !items.isEmpty else { return nil }
        let next = items.removeFirst()
        if items.isEmpty {
            isCollecting = false
        }
        return next
    }
}
