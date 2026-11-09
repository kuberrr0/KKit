import Foundation

/// How numbers are written in answers.
struct NumberStyle: Sendable, Equatable {
    /// At most this many digits after the point (trailing zeros dropped).
    var decimalPlaces = 6
    var grouping = true
    var locale = Locale.current

    /// For display: "1,234.5678". Very large or small numbers in scientific notation.
    func format(_ value: Double, fixedDecimals: Int? = nil, grouping: Bool? = nil) -> String {
        let magnitude = Swift.abs(value)
        if fixedDecimals == nil, magnitude != 0, magnitude >= 1e15 || magnitude < 1e-4 {
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .scientific
            formatter.maximumFractionDigits = min(decimalPlaces, 6)
            formatter.exponentSymbol = "e"
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping ?? self.grouping
        formatter.minimumFractionDigits = fixedDecimals ?? 0
        formatter.maximumFractionDigits = fixedDecimals ?? decimalPlaces
        formatter.roundingMode = .halfEven
        let text = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        // -0
        return text == "-0" ? "0" : text
    }

    /// For the clipboard: no grouping separators, so it pastes into anything.
    func plain(_ value: Double, fixedDecimals: Int? = nil) -> String {
        format(value, fixedDecimals: fixedDecimals, grouping: false)
    }
}

/// One answer for the Floating Bar.
struct CalculatorAnswer: Equatable, Sendable {
    enum Kind: String, Sendable {
        case math, unit, currency, base, date, time
    }

    /// The row's title, after "= ": "152.4 cm".
    var value: String
    /// What ↵ copies: "152.4".
    var copy: String
    /// The row's subtitle: what was understood ("5 ft → cm").
    var detail: String
    var kind: Kind
}

enum CalculatorOutcome: Equatable, Sendable {
    case answer(CalculatorAnswer)
    /// A currency conversion ("100 USD → INR"), but no rates have been fetched yet.
    case needsRates(String)
}

/// Tries every kind of answer in turn: base conversion, units, currency, time zones,
/// dates, plain maths.
struct CalculatorEngine: Sendable {
    var style = NumberStyle()
    var calendar = CalendarContext.current()
    var rates: ExchangeRates?
    var defaultCurrency = "USD"

    /// - Parameter scoped: typed after `=`, so a bare number or constant is fine. In
    ///   root search only answers to real calculations show.
    func evaluate(_ raw: String, scoped: Bool) -> CalculatorOutcome? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 200 else { return nil }
        if let answer = baseConversion(text) {
            return .answer(answer)
        }
        if let conversion = UnitConversion.convert(text) {
            return .answer(unitAnswer(conversion))
        }
        if let currency = currency(text) {
            return currency
        }
        if let time = TimeZoneMath.evaluate(text, in: calendar) {
            return .answer(timeAnswer(time, query: text))
        }
        if let date = DateMath.evaluate(text, in: calendar) {
            return .answer(dateAnswer(date, query: text))
        }
        return math(text, scoped: scoped).map(CalculatorOutcome.answer)
    }

    // MARK: Kinds

    private func math(_ text: String, scoped: Bool) -> CalculatorAnswer? {
        guard let expression = try? MathExpression.evaluate(text) else { return nil }
        if !scoped {
            guard expression.isCalculation, text.contains(where: \.isNumber), !Self.looksLikeADate(text) else { return nil }
        }
        return CalculatorAnswer(
            value: style.format(expression.value),
            copy: style.plain(expression.value),
            detail: text,
            kind: .math
        )
    }

    /// "2026-01-31" is a date, not 1994.
    static func looksLikeADate(_ text: String) -> Bool {
        let parts = text.split(separator: "-")
        return parts.count == 3 && parts[0].count == 4 && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }

    private func unitAnswer(_ conversion: UnitConversion.Result) -> CalculatorAnswer {
        let number = style.format(conversion.value)
        let separator = conversion.to.symbol.hasPrefix("°") ? "" : " "
        return CalculatorAnswer(
            value: number + separator + conversion.to.symbol,
            copy: style.plain(conversion.value),
            detail: "\(style.format(conversion.amount)) \(conversion.from.symbol) → \(conversion.to.symbol)",
            kind: .unit
        )
    }

    /// "0xff in dec", "255 to hex", "0b1010 as oct".
    private func baseConversion(_ text: String) -> CalculatorAnswer? {
        let targets: [String: Int] = [
            "hex": 16, "hexadecimal": 16, "dec": 10, "decimal": 10,
            "bin": 2, "binary": 2, "oct": 8, "octal": 8,
        ]
        for (left, right) in ConversionSplitter.candidates(text) {
            guard let radix = targets[right.lowercased()],
                  let value = MathExpression.value(of: left),
                  value == value.rounded(), Swift.abs(value) < 9.0e15
            else { continue }
            let integer = Int(value)
            let digits = String(Swift.abs(integer), radix: radix).uppercased()
            let prefix = radix == 16 ? "0x" : radix == 2 ? "0b" : radix == 8 ? "0o" : ""
            let result = (integer < 0 ? "-" : "") + prefix + digits
            return CalculatorAnswer(value: result, copy: result, detail: "\(left) → \(right.lowercased())", kind: .base)
        }
        return nil
    }

    private func currency(_ text: String) -> CalculatorOutcome? {
        let known: (String) -> Bool = { code in rates?.knows(code) ?? false }
        guard let query = CurrencyQuery.parse(text, known: known),
              let amount = MathExpression.value(of: query.amountText)
        else { return nil }
        let target = query.to ?? defaultCurrency
        guard target != query.from else { return nil }
        let summary = "\(style.format(amount)) \(query.from) → \(target)"
        guard let rates else { return .needsRates(summary) }
        guard let converted = rates.convert(amount, from: query.from, to: target) else { return nil }
        let decimals = Swift.abs(converted) < 1 ? 4 : 2
        let updated = DateFormatter.localizedString(from: rates.updated, dateStyle: .medium, timeStyle: .none)
        return .answer(CalculatorAnswer(
            value: "\(style.format(converted, fixedDecimals: decimals)) \(target)",
            copy: style.plain(converted, fixedDecimals: decimals),
            detail: String(localized: "\(summary) · rates from \(updated)"),
            kind: .currency
        ))
    }

    private func timeAnswer(_ time: ZonedTime, query: String) -> CalculatorAnswer {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale
        formatter.timeZone = time.zone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        let clock = formatter.string(from: time.date)
        var value = "\(clock) \(time.place)"
        // The day too, when it isn't today here.
        var targetCalendar = calendar.calendar
        targetCalendar.timeZone = time.zone
        let there = targetCalendar.dateComponents([.year, .month, .day], from: time.date)
        let here = calendar.calendar.dateComponents([.year, .month, .day], from: calendar.now)
        if there != here {
            formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
            value += " · \(formatter.string(from: time.date))"
        }
        return CalculatorAnswer(value: value, copy: clock, detail: query, kind: .time)
    }

    private func dateAnswer(_ answer: DateAnswer, query: String) -> CalculatorAnswer {
        switch answer {
        case .date(let date, let includesTime):
            let formatter = DateFormatter()
            formatter.locale = calendar.locale
            formatter.timeZone = calendar.timeZone
            formatter.calendar = calendar.calendar
            formatter.dateStyle = .full
            formatter.timeStyle = includesTime ? .short : .none
            let text = formatter.string(from: date)
            return CalculatorAnswer(value: text, copy: text, detail: query, kind: .date)
        case .span(let amount, let unit):
            let number = style.format(amount)
            let units: String
            switch unit {
            case .minute: units = amount == 1 ? String(localized: "minute") : String(localized: "minutes")
            case .hour: units = amount == 1 ? String(localized: "hour") : String(localized: "hours")
            case .weekOfYear: units = amount == 1 ? String(localized: "week") : String(localized: "weeks")
            case .month: units = amount == 1 ? String(localized: "month") : String(localized: "months")
            case .year: units = amount == 1 ? String(localized: "year") : String(localized: "years")
            default: units = amount == 1 ? String(localized: "day") : String(localized: "days")
            }
            return CalculatorAnswer(value: "\(number) \(units)", copy: style.plain(amount), detail: query, kind: .date)
        }
    }
}
