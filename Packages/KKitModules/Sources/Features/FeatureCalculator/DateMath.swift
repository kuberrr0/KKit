import Foundation

/// Where and when date and time answers are worked out.
struct CalendarContext: Sendable {
    var now: Date
    var calendar: Calendar
    var timeZone: TimeZone
    var locale: Locale

    static func current(now: Date = Date()) -> CalendarContext {
        var calendar = Calendar.current
        calendar.timeZone = .current
        return CalendarContext(now: now, calendar: calendar, timeZone: .current, locale: .current)
    }
}

/// A date or a span of time, worked out from a phrase.
enum DateAnswer: Equatable {
    case date(Date, includesTime: Bool)
    /// "46 days".
    case span(Double, unit: Calendar.Component)
}

/// "today + 45 days", "tomorrow", "3 weeks from now", "10 days ago",
/// "days until dec 25", "weeks since 2024-01-01", "dec 25 - 10 days".
enum DateMath {
    static func evaluate(_ raw: String, in context: CalendarContext) -> DateAnswer? {
        var text = FuzzyNormalize.collapse(raw.lowercased())
        if text.hasPrefix("how many ") {
            text = String(text.dropFirst("how many ".count))
        }
        if let span = span(text, in: context) {
            return span
        }
        if let relative = relative(text, in: context) {
            return relative
        }
        if let arithmetic = arithmetic(text, in: context) {
            return arithmetic
        }
        if let base = baseDate(text, in: context, preferFuture: true) {
            return base.hasRelativeWord ? .date(base.date, includesTime: base.includesTime) : nil
        }
        return nil
    }

    // MARK: Phrases

    /// "days until dec 25", "weeks since 2024-01-01", "hours until tomorrow".
    private static func span(_ text: String, in context: CalendarContext) -> DateAnswer? {
        let words = text.split(separator: " ").map(String.init)
        guard words.count >= 3, let unit = unit(words[0]),
              let direction = ["until", "till", "til", "to", "since", "from"].first(where: { $0 == words[1] })
        else { return nil }
        let future = direction != "since" && direction != "from"
        let rest = words.dropFirst(2).joined(separator: " ")
        guard let target = baseDate(rest, in: context, preferFuture: future) else { return nil }
        let calendar = context.calendar
        let start: Date
        let end: Date
        if unit == .hour || unit == .minute {
            start = context.now
            end = target.date
        } else {
            start = calendar.startOfDay(for: context.now)
            end = calendar.startOfDay(for: target.date)
        }
        let seconds = end.timeIntervalSince(start)
        let value: Double
        switch unit {
        case .minute: value = (seconds / 60).rounded()
        case .hour: value = (seconds / 3600 * 10).rounded() / 10
        case .day: value = Double(calendar.dateComponents([.day], from: start, to: end).day ?? 0)
        case .weekOfYear: value = (Double(calendar.dateComponents([.day], from: start, to: end).day ?? 0) / 7 * 10).rounded() / 10
        case .month: value = Double(calendar.dateComponents([.month], from: start, to: end).month ?? 0)
        case .year: value = Double(calendar.dateComponents([.year], from: start, to: end).year ?? 0)
        default: return nil
        }
        return .span(Swift.abs(value), unit: unit)
    }

    /// "3 weeks from now", "10 days ago", "in 2 months", "45 days later".
    private static func relative(_ text: String, in context: CalendarContext) -> DateAnswer? {
        var words = text.split(separator: " ").map(String.init)
        var sign = 1
        if words.first == "in" {
            words.removeFirst()
        } else if words.suffix(2) == ["from", "now"] || words.suffix(2) == ["from", "today"] {
            words.removeLast(2)
        } else if words.last == "later" || words.last == "hence" {
            words.removeLast()
        } else if words.last == "ago" {
            words.removeLast()
            sign = -1
        } else {
            return nil
        }
        guard words.count == 2, let amount = Int(words[0]), let unit = unit(words[1]) else { return nil }
        guard let date = context.calendar.date(byAdding: unit, value: sign * amount, to: context.now) else { return nil }
        return .date(date, includesTime: unit == .hour || unit == .minute)
    }

    /// "today + 45 days", "dec 25 - 2 weeks", "now + 90 minutes".
    private static func arithmetic(_ text: String, in context: CalendarContext) -> DateAnswer? {
        let spaced = text.replacingOccurrences(of: "+", with: " + ")
        let words = FuzzyNormalize.collapse(spaced).split(separator: " ").map(String.init)
        guard let opIndex = words.lastIndex(where: { $0 == "+" || $0 == "-" }), opIndex > 0,
              words.count == opIndex + 3,
              let amount = Int(words[opIndex + 1]),
              let unit = unit(words[opIndex + 2])
        else { return nil }
        let baseText = words[..<opIndex].joined(separator: " ")
        guard let base = baseDate(baseText, in: context, preferFuture: true) else { return nil }
        let sign = words[opIndex] == "+" ? 1 : -1
        guard let date = context.calendar.date(byAdding: unit, value: sign * amount, to: base.date) else { return nil }
        let withTime = base.includesTime || unit == .hour || unit == .minute
        return .date(date, includesTime: withTime)
    }

    // MARK: Pieces

    struct BaseDate {
        let date: Date
        let includesTime: Bool
        /// today, tomorrow… (a bare "dec 25" isn't worth answering on its own).
        let hasRelativeWord: Bool
    }

    /// "today", "tomorrow", "yesterday", "now", "dec 25", "25 december 2026",
    /// "2026-12-25". Without a year: the next one (or the last one, for "since").
    static func baseDate(_ text: String, in context: CalendarContext, preferFuture: Bool) -> BaseDate? {
        let calendar = context.calendar
        let today = calendar.startOfDay(for: context.now)
        switch text {
        case "now":
            return BaseDate(date: context.now, includesTime: true, hasRelativeWord: true)
        case "today":
            return BaseDate(date: today, includesTime: false, hasRelativeWord: true)
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: today).map { BaseDate(date: $0, includesTime: false, hasRelativeWord: true) }
        case "yesterday":
            return calendar.date(byAdding: .day, value: -1, to: today).map { BaseDate(date: $0, includesTime: false, hasRelativeWord: true) }
        default:
            break
        }
        if let named = namedDay(text, in: context, preferFuture: preferFuture) {
            return BaseDate(date: named, includesTime: false, hasRelativeWord: false)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        // "dec 25th, 2026" → "Dec 25 2026".
        let cleaned = text.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(\\d+)(st|nd|rd|th)\\b", with: "$1", options: .regularExpression)
            .capitalized
        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "MMM d yyyy", "MMMM d yyyy", "d MMM yyyy", "d MMMM yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                return BaseDate(date: date, includesTime: false, hasRelativeWord: false)
            }
        }
        for format in ["MMM d", "MMMM d", "d MMM", "d MMMM"] {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: cleaned) else { continue }
            let parts = calendar.dateComponents([.month, .day], from: parsed)
            var components = DateComponents()
            components.month = parts.month
            components.day = parts.day
            components.hour = 0
            let direction: Calendar.SearchDirection = preferFuture ? .forward : .backward
            let found = calendar.nextDate(after: today, matching: components, matchingPolicy: .nextTime, direction: direction)
            // Today itself counts ("days until dec 25" on Dec 25 is 0).
            let sameDay = calendar.dateComponents([.month, .day], from: today) == parts
            if let date = sameDay ? today : found {
                return BaseDate(date: date, includesTime: false, hasRelativeWord: false)
            }
        }
        return nil
    }

    private static func namedDay(_ text: String, in context: CalendarContext, preferFuture: Bool) -> Date? {
        let named: [String: (Int, Int)] = [
            "christmas": (12, 25), "xmas": (12, 25), "new year": (1, 1), "new years": (1, 1),
            "new year's day": (1, 1), "halloween": (10, 31), "valentines": (2, 14), "valentine's day": (2, 14),
        ]
        guard let monthDay = named[text] else { return nil }
        let (month, day) = monthDay
        let today = context.calendar.startOfDay(for: context.now)
        var components = DateComponents()
        components.month = month
        components.day = day
        components.hour = 0
        let todayParts = context.calendar.dateComponents([.month, .day], from: today)
        if todayParts.month == month, todayParts.day == day {
            return today
        }
        return context.calendar.nextDate(
            after: today,
            matching: components,
            matchingPolicy: .nextTime,
            direction: preferFuture ? .forward : .backward
        )
    }

    static func unit(_ word: String) -> Calendar.Component? {
        switch word {
        case "minute", "minutes", "min", "mins": .minute
        case "hour", "hours", "hr", "hrs", "h": .hour
        case "day", "days", "d": .day
        case "week", "weeks", "wk", "wks", "w": .weekOfYear
        case "month", "months", "mo": .month
        case "year", "years", "yr", "yrs", "y": .year
        default: nil
        }
    }
}

enum FuzzyNormalize {
    /// Trims and collapses runs of spaces.
    static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
