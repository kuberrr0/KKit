import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureCalculator

private func value(_ text: String) -> Double? {
    MathExpression.value(of: text)
}

private func close(_ a: Double?, _ b: Double, tolerance: Double = 1e-9) -> Bool {
    guard let a else { return false }
    return Swift.abs(a - b) <= tolerance * max(1, Swift.abs(b))
}

struct ExpressionTests {
    @Test func arithmeticAndPrecedence() {
        #expect(value("1 + 2 * 3") == 7)
        #expect(value("(1920/1080)*100") == 1920.0 / 1080.0 * 100)
        #expect(value("2^10") == 1024)
        #expect(value("2**3**2") == 512)
        #expect(value("-2^2") == -4)
        #expect(value("2^-1") == 0.5)
        #expect(value("10 ÷ 4 × 2") == 5)
        #expect(value("3 x 4") == 12)
        #expect(value("7 mod 3") == 1)
        #expect(value("10 % 3") == 1)
        #expect(value("5!") == 120)
        #expect(value("2+2=") == 4)
    }

    @Test func percentages() {
        #expect(close(value("50%"), 0.5))
        #expect(close(value("200 + 10%"), 220))
        #expect(close(value("200 - 25%"), 150))
        #expect(close(value("15% of 80"), 12))
        #expect(close(value("10% * 50"), 5))
    }

    @Test func functionsConstantsAndImplicitMultiplication() {
        #expect(close(value("sqrt 2"), 2.0.squareRoot()))
        #expect(close(value("sqrt(16) + cbrt(27)"), 7))
        #expect(close(value("2pi"), 2 * .pi))
        #expect(close(value("3(4+5)"), 27))
        #expect(close(value("sin(30°)"), 0.5))
        #expect(close(value("log(1000)"), 3))
        #expect(close(value("log(8, 2)"), 3))
        #expect(close(value("ln e"), 1))
        #expect(value("max(3, 9, 4)") == 9)
        #expect(close(value("2e3"), 2000))
        #expect(close(value("2e"), 2 * M_E))
        #expect(close(value("sqrt(2"), 2.0.squareRoot()))
    }

    @Test func numberLiterals() {
        #expect(value("0xff") == 255)
        #expect(value("0b1010 + 1") == 11)
        #expect(value("0o17") == 15)
        #expect(value("1,000 * 3") == 3000)
        #expect(value("1,000,000 / 4") == 250_000)
        // Inside parentheses a comma separates arguments.
        #expect(value("max(1,000)") == 1)
    }

    @Test func rejectsNonsense() {
        #expect(value("") == nil)
        #expect(value("2 +") == nil)
        #expect(value("night 150") == nil)
        #expect(value("hello") == nil)
        #expect(value("1/0") == nil)
        #expect(value("sqrt(-1)") == nil)
        #expect(value("200!") == nil)
        #expect(value("2 3") == nil)
    }

    @Test func knowsWhatIsACalculation() throws {
        let bare = try MathExpression.evaluate("42")
        #expect(!bare.isCalculation)
        let sum = try MathExpression.evaluate("40 + 2")
        #expect(sum.isCalculation)
        let hex = try MathExpression.evaluate("0x2a")
        #expect(hex.isCalculation)
    }
}

struct UnitTests {
    @Test func convertsLengthsAndTemperatures() {
        #expect(close(UnitConversion.convert("5 ft in cm")?.value, 152.4))
        #expect(close(UnitConversion.convert("5ft to m")?.value, 1.524))
        #expect(close(UnitConversion.convert("12 in to cm")?.value, 30.48))
        #expect(close(UnitConversion.convert("72 F to C")?.value, 22.222222222, tolerance: 1e-6))
        #expect(close(UnitConversion.convert("0 °C in °F")?.value, 32, tolerance: 1e-9))
        #expect(close(UnitConversion.convert("300 kelvin to celsius")?.value, 26.85, tolerance: 1e-9))
    }

    @Test func convertsDataSpeedAndVolume() {
        #expect(close(UnitConversion.convert("3 GB in MB")?.value, 3000))
        #expect(close(UnitConversion.convert("1 GiB in MiB")?.value, 1024))
        #expect(close(UnitConversion.convert("100 km/h in mph")?.value, 62.137119224, tolerance: 1e-6))
        #expect(close(UnitConversion.convert("2 cups in ml")?.value, 473.176473, tolerance: 1e-6))
        #expect(close(UnitConversion.convert("16 fl oz to ml")?.value, 473.176473, tolerance: 1e-6))
        #expect(close(UnitConversion.convert("2*3 km as miles")?.value, 3.728227153, tolerance: 1e-6))
    }

    @Test func refusesMismatchedDimensions() {
        #expect(UnitConversion.convert("5 kg in cm") == nil)
        #expect(UnitConversion.convert("5 cm in cm") == nil)
        #expect(UnitConversion.convert("5 in") == nil)
        #expect(UnitConversion.convert("tea in cups") == nil)
    }

    @Test func aliasesAreUniqueToOneUnit() {
        #expect(UnitTable.unit(named: "b")?.symbol == "B")
        #expect(UnitTable.unit(named: "mbps")?.symbol == "Mbit")
        #expect(UnitTable.unit(named: "meters")?.symbol == "m")
        #expect(UnitTable.unit(named: "FL OZ")?.symbol == "fl oz")
    }
}

struct CurrencyTests {
    private let rates = ExchangeRates(
        base: "USD",
        rates: ["EUR": 0.9, "INR": 83, "GBP": 0.8, "JPY": 150],
        updated: Date(timeIntervalSince1970: 1_700_000_000),
        fetched: Date(timeIntervalSince1970: 1_700_000_000)
    )

    @Test func parsesTheWaysPeopleWriteAmounts() {
        let known: (String) -> Bool = { _ in false }
        #expect(CurrencyQuery.parse("100 usd in inr", known: known) == CurrencyQuery(amountText: "100", from: "USD", to: "INR"))
        #expect(CurrencyQuery.parse("€50 to usd", known: known) == CurrencyQuery(amountText: "50", from: "EUR", to: "USD"))
        #expect(CurrencyQuery.parse("100$ in eur", known: known) == CurrencyQuery(amountText: "100", from: "USD", to: "EUR"))
        #expect(CurrencyQuery.parse("1,000 rupees in dollars", known: known) == CurrencyQuery(amountText: "1,000", from: "INR", to: "USD"))
        #expect(CurrencyQuery.parse("25 euros", known: known) == CurrencyQuery(amountText: "25", from: "EUR", to: nil))
        #expect(CurrencyQuery.parse("100usd", known: known) == CurrencyQuery(amountText: "100", from: "USD", to: nil))
        #expect(CurrencyQuery.parse("top 10", known: known) == nil)
        #expect(CurrencyQuery.parse("5 m", known: known) == nil)
    }

    @Test func convertsThroughTheBase() {
        #expect(close(rates.convert(100, from: "USD", to: "INR"), 8300))
        #expect(close(rates.convert(90, from: "EUR", to: "GBP"), 80))
        #expect(rates.convert(1, from: "USD", to: "XYZ") == nil)
    }

    @Test func decodesTheProviderResponse() throws {
        let json = """
        {"result":"success","base_code":"USD","time_last_update_unix":1700000000,"rates":{"USD":1,"EUR":0.92}}
        """
        let decoded = try OpenExchangeRateSource.decode(Data(json.utf8), now: Date(timeIntervalSince1970: 5))
        #expect(decoded.rates["EUR"] == 0.92)
        #expect(decoded.updated == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(throws: (any Error).self) {
            try OpenExchangeRateSource.decode(Data(#"{"result":"error"}"#.utf8), now: Date())
        }
    }

    @Test func storeSavesRatesAndReadsThemBack() async throws {
        let storage = FeatureStorage(featureID: "calculator", service: InMemoryStorageService())
        let store = ExchangeRateStore(source: FixedRates(rates: rates), storage: storage)
        #expect(await store.current() == nil)
        #expect(await store.isStale())
        let fetched = await store.refresh()
        #expect(fetched == rates)
        let reopened = ExchangeRateStore(source: FailingRates(), storage: storage)
        #expect(await reopened.current() == rates)
    }
}

struct FixedRates: ExchangeRateSource {
    let rates: ExchangeRates
    func fetch() async throws -> ExchangeRates { rates }
}

struct FailingRates: ExchangeRateSource {
    func fetch() async throws -> ExchangeRates { throw URLError(.notConnectedToInternet) }
}

struct DateAndTimeTests {
    /// Monday 9 November 2026, 10:00 UTC.
    private let context: CalendarContext = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 10))!
        return CalendarContext(now: now, calendar: calendar, timeZone: calendar.timeZone, locale: Locale(identifier: "en_US_POSIX"))
    }()

    private func day(_ answer: DateAnswer?) -> DateComponents? {
        guard case .date(let date, _) = answer else { return nil }
        return context.calendar.dateComponents([.year, .month, .day], from: date)
    }

    @Test func addsToDates() {
        #expect(day(DateMath.evaluate("today + 45 days", in: context)) == DateComponents(year: 2026, month: 12, day: 24))
        #expect(day(DateMath.evaluate("tomorrow", in: context)) == DateComponents(year: 2026, month: 11, day: 10))
        #expect(day(DateMath.evaluate("3 weeks from now", in: context)) == DateComponents(year: 2026, month: 11, day: 30))
        #expect(day(DateMath.evaluate("10 days ago", in: context)) == DateComponents(year: 2026, month: 10, day: 30))
        #expect(day(DateMath.evaluate("dec 25 - 1 week", in: context)) == DateComponents(year: 2026, month: 12, day: 18))
        #expect(DateMath.evaluate("dec 25", in: context) == nil)
    }

    @Test func countsDays() {
        #expect(DateMath.evaluate("days until dec 25", in: context) == .span(46, unit: .day))
        #expect(DateMath.evaluate("how many days until christmas", in: context) == .span(46, unit: .day))
        #expect(DateMath.evaluate("days since 2026-01-01", in: context) == .span(312, unit: .day))
        #expect(DateMath.evaluate("days since nov 1", in: context) == .span(8, unit: .day))
    }

    @Test func parsesTimes() {
        func time(_ text: String) -> [Int]? {
            TimeZoneMath.parseTime(text).map { [$0.hour, $0.minute] }
        }
        #expect(time("5pm") == [17, 0])
        #expect(time("5:30am") == [5, 30])
        #expect(time("530pm") == [17, 30])
        #expect(time("12am") == [0, 0])
        #expect(time("17:45") == [17, 45])
        #expect(time("noon") == [12, 0])
        #expect(time("5") == nil)
        #expect(time("25:00") == nil)
    }

    @Test func convertsBetweenZones() throws {
        let converted = try #require(TimeZoneMath.evaluate("5pm PST in IST", in: context))
        // 9 Nov 2026 is winter time: 17:00 PST is 01:00 UTC on the 10th, 06:30 in India.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = converted.zone
        let parts = calendar.dateComponents([.day, .hour, .minute], from: converted.date)
        #expect(parts == DateComponents(day: 10, hour: 6, minute: 30))
        #expect(converted.place == "IST")
        let now = try #require(TimeZoneMath.evaluate("time in tokyo", in: context))
        #expect(now.zone.identifier == "Asia/Tokyo")
        #expect(now.place == "Tokyo")
        #expect(TimeZoneMath.evaluate("time machine", in: context) == nil)
    }
}

struct EngineTests {
    private func engine(rates: ExchangeRates? = nil) -> CalculatorEngine {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 10))!
        return CalculatorEngine(
            style: NumberStyle(decimalPlaces: 4, grouping: true, locale: Locale(identifier: "en_US")),
            calendar: CalendarContext(now: now, calendar: calendar, timeZone: calendar.timeZone, locale: Locale(identifier: "en_US_POSIX")),
            rates: rates,
            defaultCurrency: "EUR"
        )
    }

    private func answer(_ text: String, scoped: Bool = false, rates: ExchangeRates? = nil) -> CalculatorAnswer? {
        guard case .answer(let answer) = engine(rates: rates).evaluate(text, scoped: scoped) else { return nil }
        return answer
    }

    @Test func formatsMaths() {
        #expect(answer("1920/1080")?.value == "1.7778")
        #expect(answer("1000 * 1000")?.value == "1,000,000")
        #expect(answer("1000 * 1000")?.copy == "1000000")
        #expect(answer("0.1 + 0.2")?.value == "0.3")
        #expect(answer("2^60")?.value.contains("e") == true)
    }

    @Test func rootSearchOnlyAnswersCalculations() {
        #expect(answer("42") == nil)
        #expect(answer("42", scoped: true)?.value == "42")
        #expect(answer("pi") == nil)
        #expect(answer("2026-01-31") == nil)
        #expect(answer("night 150") == nil)
    }

    @Test func convertsBasesAndUnits() {
        #expect(answer("255 in hex")?.value == "0xFF")
        #expect(answer("0xff in dec")?.value == "255")
        #expect(answer("10 to bin")?.value == "0b1010")
        #expect(answer("5 ft in cm")?.value == "152.4 cm")
        #expect(answer("100 F to C")?.value == "37.7778°C")
    }

    @Test func convertsCurrencyOnceRatesExist() {
        let outcome = engine().evaluate("100 usd in inr", scoped: false)
        #expect(outcome == .needsRates("100 USD → INR"))
        let rates = ExchangeRates(base: "USD", rates: ["INR": 83, "EUR": 0.9], updated: Date(), fetched: Date())
        #expect(answer("100 usd in inr", rates: rates)?.value == "8,300.00 INR")
        #expect(answer("100 usd", rates: rates)?.value == "90.00 EUR")
        #expect(answer("100 usd", rates: rates)?.copy == "90.00")
    }

    @Test func answersDatesAndTimes() {
        #expect(answer("days until dec 25")?.value == "46 days")
        #expect(answer("today + 1 day")?.kind == .date)
        #expect(answer("time in tokyo")?.kind == .time)
    }
}

@MainActor
struct CalculatorProviderTests {
    @Test func providerAnswersAndFetchesRatesWhenNeeded() async {
        let environment = TestEnvironment()
        let rates = ExchangeRates(base: "USD", rates: ["INR": 83], updated: Date(), fetched: Date())
        let store = ExchangeRateStore(source: FixedRates(rates: rates), storage: nil)
        let provider = CalculatorProvider(settings: FeatureSettings(featureID: "calculator", store: environment.settings), rates: store)
        provider.locale = Locale(identifier: "en_US")

        var batches: [[SearchResult]] = []
        for await batch in provider.results(for: SearchQuery(text: "100 usd in inr")) {
            batches.append(batch)
        }
        #expect(batches.count == 2)
        #expect(batches.first?.first?.kind == .custom)
        #expect(batches.last?.first?.title == "= 8,300.00 INR")
        #expect(batches.last?.first?.kind == .text("8300.00"))

        var maths: [SearchResult] = []
        for await batch in provider.results(for: SearchQuery(text: "2+2")) {
            maths = batch
        }
        #expect(maths.first?.title == "= 4")
        #expect(maths.first?.score == 0.97)
    }

    @Test func openCommandShowsTheBar() async throws {
        let environment = TestEnvironment()
        let feature = CalculatorFeature(context: environment.makeContext(for: "calculator"), source: FailingRates())
        let found: Command? = feature.commands.first { $0.id == "calculator.open" }
        let command = try #require(found)
        try await command.perform(CommandInvocation())
        #expect(environment.floatingBar.shownQueries == ["="])
    }
}
