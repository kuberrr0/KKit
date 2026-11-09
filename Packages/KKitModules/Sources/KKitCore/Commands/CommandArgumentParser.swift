import Foundation

/// Turns typed text into a command's argument, so every feature gets inline arguments
/// for free: `night 150`, `awake 2h`, `vol 30%`, `timer 1h30m`. The Floating Bar, the
/// `kkit://` URL handler and the Shortcuts action all use it.
public enum CommandArgumentParser {
    /// `nil` if `text` isn't a valid value for `parameter`.
    public static func parse(_ text: String, for parameter: CommandParameter) -> CommandArgument? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch parameter {
        case .percent:
            return parsePercent(trimmed).map(CommandArgument.percent)
        case .duration:
            return parseDuration(trimmed).map(CommandArgument.duration)
        case .text:
            return .text(trimmed)
        case .choice(let choices):
            return matchChoice(trimmed, in: choices).map(CommandArgument.choice)
        }
    }

    /// "30", "30%", "150 %", "12.5". Negative values and values over 1000 are rejected.
    public static func parsePercent(_ text: String) -> Double? {
        var value = text.trimmingCharacters(in: .whitespaces)
        if value.hasSuffix("%") {
            value = String(value.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard !value.isEmpty,
              value.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              let number = Double(value),
              number.isFinite, number >= 0, number <= 1000
        else { return nil }
        return number
    }

    /// "25m", "2h", "1h30m", "1h 30", "90s", "1.5 hours", "45 min", "2 days".
    /// A bare number is minutes. The total must be more than zero.
    public static func parseDuration(_ text: String) -> Duration? {
        let tokens = durationTokens(text.lowercased())
        guard let tokens, !tokens.isEmpty else { return nil }
        var total = 0.0
        var previousUnit: Double?
        for (index, token) in tokens.enumerated() {
            let unit: Double
            if let name = token.unit {
                guard let seconds = unitSeconds[name] else { return nil }
                unit = seconds
            } else if index == tokens.count - 1, let previous = previousUnit {
                // "1h30" → 30 minutes, "2m30" → 30 seconds.
                unit = previous == 3600 ? 60 : (previous == 60 ? 1 : 60)
            } else if tokens.count == 1 {
                unit = 60
            } else {
                return nil
            }
            total += token.value * unit
            previousUnit = unit
        }
        guard total > 0, total.isFinite, total < 366 * 86_400 else { return nil }
        return .milliseconds(Int64((total * 1000).rounded()))
    }

    /// The choice matching `text`: exact (ignoring case) first, then the only one it starts.
    public static func matchChoice(_ text: String, in choices: [String]) -> String? {
        let needle = text.lowercased()
        if let exact = choices.first(where: { $0.lowercased() == needle }) {
            return exact
        }
        let prefixed = choices.filter { $0.lowercased().hasPrefix(needle) }
        return prefixed.count == 1 ? prefixed[0] : nil
    }

    /// How an argument reads in a title: "150%", "1h 30m", "“tea”".
    public static func display(_ argument: CommandArgument) -> String {
        switch argument {
        case .percent(let value):
            return formatNumber(value) + "%"
        case .duration(let duration):
            return formatDuration(duration)
        case .text(let text):
            return "“\(text)”"
        case .choice(let choice):
            return choice
        }
    }

    /// What to type, for placeholders and hints.
    public static func hint(for parameter: CommandParameter) -> String {
        switch parameter {
        case .percent(let value):
            String(localized: "A percentage, like \(formatNumber(value))")
        case .duration(let value):
            String(localized: "A duration, like \(formatDuration(value)), 25m or 1h30m")
        case .text(let placeholder):
            placeholder
        case .choice(let choices):
            choices.joined(separator: ", ")
        }
    }

    /// "1h 30m", "45m", "30s", "2d".
    public static func formatDuration(_ duration: Duration) -> String {
        let components = duration.components
        let total = Int(components.seconds) + (components.attoseconds >= 500_000_000_000_000_000 ? 1 : 0)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if seconds > 0 || parts.isEmpty { parts.append("\(seconds)s") }
        return parts.joined(separator: " ")
    }

    // MARK: Private

    private struct DurationToken {
        var value: Double
        var unit: String?
    }

    private static let unitSeconds: [String: Double] = [
        "s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1,
        "m": 60, "min": 60, "mins": 60, "minute": 60, "minutes": 60,
        "h": 3600, "hr": 3600, "hrs": 3600, "hour": 3600, "hours": 3600,
        "d": 86_400, "day": 86_400, "days": 86_400,
    ]

    /// Splits "1h 30m" / "1.5hours" / "90 s" into number + unit pairs.
    private static func durationTokens(_ text: String) -> [DurationToken]? {
        var tokens: [DurationToken] = []
        var index = text.startIndex
        func skipSpaces() {
            while index < text.endIndex, text[index] == " " {
                index = text.index(after: index)
            }
        }
        skipSpaces()
        while index < text.endIndex {
            var number = ""
            while index < text.endIndex, text[index].isASCII, text[index].isNumber || text[index] == "." {
                number.append(text[index])
                index = text.index(after: index)
            }
            guard let value = Double(number) else { return nil }
            skipSpaces()
            var unit = ""
            while index < text.endIndex, text[index].isLetter {
                unit.append(text[index])
                index = text.index(after: index)
            }
            tokens.append(DurationToken(value: value, unit: unit.isEmpty ? nil : unit))
            skipSpaces()
        }
        return tokens
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(format: "%g", value)
    }
}
