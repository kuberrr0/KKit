import Foundation
import KKitCore
import KKitUI
import SwiftUI

enum CalculatorSettings {
    static let decimalPlaces = SettingKey("decimalPlaces", default: 6)
    /// Thousands separators in answers ("1,234,567"). Copied answers never have them.
    static let grouping = SettingKey("grouping", default: true)
    /// An ISO code; empty for the region's currency.
    static let defaultCurrency = SettingKey("defaultCurrency", default: "")
    /// Fetch new exchange rates when the saved ones are a day old.
    static let refreshRates = SettingKey("refreshRates", default: true)
    /// Answer in root search when the query looks like a calculation.
    static let autoDetect = SettingKey("autoDetect", default: true)

    @MainActor
    static func currency(_ settings: FeatureSettings) -> String {
        let chosen = settings[defaultCurrency]
        if !chosen.isEmpty {
            return chosen
        }
        return Locale.current.currency?.identifier ?? "USD"
    }
}

struct CalculatorSettingsView: View {
    let rates: ExchangeRateStore

    @Setting(CalculatorSettings.decimalPlaces) private var decimalPlaces
    @Setting(CalculatorSettings.grouping) private var grouping
    @Setting(CalculatorSettings.defaultCurrency) private var defaultCurrency
    @Setting(CalculatorSettings.refreshRates) private var refreshRates
    @Setting(CalculatorSettings.autoDetect) private var autoDetect

    @State private var ratesDate: Date?
    @State private var isRefreshing = false

    var body: some View {
        Group {
            KKSection(
                String(localized: "Answers"),
                footer: String(localized: "Type “=” in the Floating Bar, or just type: “2^10”, “15% of 80”, “5 ft in cm”, “100 usd in inr”, “days until dec 25”, “5pm PST in IST”, “255 in hex”. ↵ copies the answer.")
            ) {
                Toggle(String(localized: "Answer as you type in the Floating Bar"), isOn: $autoDetect)
                Stepper(value: $decimalPlaces, in: 0...12) {
                    Text("Up to \(decimalPlaces) decimal places")
                }
                Toggle(String(localized: "Thousands separators"), isOn: $grouping)
            }
            KKSection(
                String(localized: "Currency"),
                footer: String(localized: "Rates come from open.er-api.com and are saved, so conversions work offline.")
            ) {
                Picker(String(localized: "Your currency"), selection: $defaultCurrency) {
                    Text("From your region (\(Locale.current.currency?.identifier ?? "USD"))").tag("")
                    ForEach(CurrencyNames.common.sorted(), id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                Toggle(String(localized: "Update rates daily"), isOn: $refreshRates)
                KKRow(ratesText, symbol: "arrow.left.arrow.right") {
                    Button(String(localized: "Update Now")) {
                        Task { await refresh() }
                    }
                    .disabled(isRefreshing)
                }
            }
        }
        .task {
            ratesDate = await rates.current()?.updated
        }
    }

    private var ratesText: String {
        guard let ratesDate else { return String(localized: "No rates yet") }
        let date = ratesDate.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "Rates from \(date)")
    }

    private func refresh() async {
        isRefreshing = true
        ratesDate = await rates.refresh()?.updated
        isRefreshing = false
    }
}
