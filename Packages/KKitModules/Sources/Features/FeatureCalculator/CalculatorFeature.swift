import Foundation
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Maths, units, currency, dates, time zones and bases in the Floating Bar. DESIGN.md §3.17.
@MainActor
public final class CalculatorFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "calculator",
        name: String(localized: "Calculator"),
        symbol: "equal.circle",
        summary: String(localized: "Maths, units, currency, dates and time zones, right in the Floating Bar."),
        category: .productivity,
        enabledByDefault: true
    )

    private let context: FeatureContext
    let rates: ExchangeRateStore
    let provider: CalculatorProvider

    public init(context: FeatureContext) {
        self.init(context: context, source: OpenExchangeRateSource())
    }

    init(context: FeatureContext, source: any ExchangeRateSource) {
        self.context = context
        rates = ExchangeRateStore(source: source, storage: context.storage)
        provider = CalculatorProvider(settings: context.settings, rates: rates)
    }

    public func start() async throws {}

    public func stop() async {}

    // MARK: Contributions

    public var searchProviders: [any SearchProvider] {
        [provider]
    }

    public var commands: [Command] {
        [
            Command(
                id: "calculator.open",
                title: String(localized: "Calculator"),
                subtitle: String(localized: "Maths, units, currency, dates and time zones"),
                symbol: "equal.circle",
                keywords: ["calculate", "convert", "units", "currency", "maths", "math"]
            ) { [weak self] _ in
                self?.context.floatingBar.show(query: CalculatorProvider.prefixText)
            },
            Command(
                id: "calculator.refreshRates",
                title: String(localized: "Refresh Exchange Rates"),
                symbol: "arrow.clockwise",
                keywords: ["currency", "exchange"]
            ) { [weak self] _ in
                await self?.refreshRates()
            },
        ]
    }

    public var settingsPane: SettingsPane? {
        let rates = rates
        return SettingsPane {
            CalculatorSettingsView(rates: rates)
        }
    }

    private func refreshRates() async {
        let before = await rates.current()?.fetched
        let after = await rates.refresh()?.fetched
        let refreshed = after != nil && after != before
        context.island.showHUD(IslandHUD(
            id: "calculator.rates",
            symbol: refreshed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            title: refreshed ? String(localized: "Exchange rates updated") : String(localized: "Couldn't update exchange rates"),
            tint: refreshed ? .accent : .warning,
            duration: 2
        ))
    }
}
