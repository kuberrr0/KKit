import Foundation
import KKitCore

/// Answers in the Floating Bar: `=` for anything, and in root search when the query
/// looks like a calculation. ↵ copies the answer.
@MainActor
final class CalculatorProvider: SearchProvider {
    nonisolated static let prefixText = "="

    let id = "calculator"
    let displayName = String(localized: "Calculator")
    let symbol = "equal.circle"
    let prefix: String? = CalculatorProvider.prefixText
    private let settings: FeatureSettings
    private let rates: ExchangeRateStore
    /// For tests: a fixed clock and locale.
    var makeCalendar: @MainActor () -> CalendarContext = { CalendarContext.current() }
    var locale: Locale = .current

    init(settings: FeatureSettings, rates: ExchangeRateStore) {
        self.settings = settings
        self.rates = rates
    }

    var includeInRootSearch: Bool {
        settings[CalculatorSettings.autoDetect]
    }

    func results(for query: SearchQuery) -> AsyncStream<[SearchResult]> {
        let text = query.trimmed
        guard !text.isEmpty else { return .single([]) }
        let scoped = query.isScoped
        let configured = CalculatorEngine(
            style: NumberStyle(
                decimalPlaces: settings[CalculatorSettings.decimalPlaces],
                grouping: settings[CalculatorSettings.grouping],
                locale: locale
            ),
            calendar: makeCalendar(),
            rates: nil,
            defaultCurrency: CalculatorSettings.currency(settings)
        )
        let refreshDaily = settings[CalculatorSettings.refreshRates]
        let store = rates
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                var engine = configured
                engine.rates = await store.current()
                switch engine.evaluate(text, scoped: scoped) {
                case nil:
                    continuation.yield([])
                case .answer(let answer):
                    continuation.yield([Self.result(answer, query: text, scoped: scoped)])
                    if answer.kind == .currency, refreshDaily, await store.isStale() {
                        // Next time's answer uses fresh rates.
                        Task.detached { await store.refresh() }
                    }
                case .needsRates(let summary):
                    continuation.yield([Self.placeholder(summary, query: text)])
                    engine.rates = await store.refresh()
                    guard !Task.isCancelled else { break }
                    if case .answer(let answer) = engine.evaluate(text, scoped: scoped) {
                        continuation.yield([Self.result(answer, query: text, scoped: scoped)])
                    } else {
                        continuation.yield([Self.unavailable(summary, query: text)])
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Rows

    nonisolated static func result(_ answer: CalculatorAnswer, query: String, scoped: Bool) -> SearchResult {
        SearchResult(
            id: "calc:\(query)",
            title: "= \(answer.value)",
            subtitle: answer.detail,
            icon: .glyph(glyph(for: answer.kind)),
            // Above everything else when it's clearly a calculation.
            score: scoped ? 1 : 0.97,
            kind: .text(answer.copy),
            accessory: accessory(for: answer.kind),
            actionTitle: String(localized: "Copy")
        )
    }

    nonisolated static func placeholder(_ summary: String, query: String) -> SearchResult {
        SearchResult(
            id: "calc:\(query)",
            title: String(localized: "Getting exchange rates…"),
            subtitle: summary,
            icon: .glyph("¤"),
            score: 0.97,
            kind: .custom,
            perform: {}
        )
    }

    nonisolated static func unavailable(_ summary: String, query: String) -> SearchResult {
        SearchResult(
            id: "calc:\(query)",
            title: String(localized: "Exchange rates aren't available"),
            subtitle: String(localized: "\(summary) · check your internet connection"),
            icon: .glyph("¤"),
            score: 0.97,
            kind: .custom,
            perform: {}
        )
    }

    nonisolated static func glyph(for kind: CalculatorAnswer.Kind) -> String {
        switch kind {
        case .math, .base: "="
        case .unit: "⇄"
        case .currency: "¤"
        case .date: "📅"
        case .time: "🕒"
        }
    }

    nonisolated static func accessory(for kind: CalculatorAnswer.Kind) -> String {
        switch kind {
        case .math: String(localized: "Calculator")
        case .base: String(localized: "Base")
        case .unit: String(localized: "Units")
        case .currency: String(localized: "Currency")
        case .date: String(localized: "Date")
        case .time: String(localized: "Time Zone")
        }
    }
}
