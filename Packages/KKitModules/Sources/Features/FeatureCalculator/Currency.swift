import Foundation
import KKitServicesAPI

/// Exchange rates against one base currency.
struct ExchangeRates: Codable, Sendable, Equatable {
    var base: String
    /// Code → units of that currency per one `base`.
    var rates: [String: Double]
    /// When the provider last updated them.
    var updated: Date
    /// When KKit fetched them.
    var fetched: Date

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let fromRate = rate(for: from), let toRate = rate(for: to), fromRate > 0 else { return nil }
        return amount / fromRate * toRate
    }

    private func rate(for code: String) -> Double? {
        code == base ? 1 : rates[code]
    }

    func knows(_ code: String) -> Bool {
        code == base || rates[code] != nil
    }
}

/// Where rates come from. Injected so tests never touch the network.
protocol ExchangeRateSource: Sendable {
    func fetch() async throws -> ExchangeRates
}

/// open.er-api.com: free, no key, daily updates, ~160 currencies.
struct OpenExchangeRateSource: ExchangeRateSource {
    static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!

    private struct Response: Decodable {
        let result: String
        let base_code: String
        let time_last_update_unix: TimeInterval
        let rates: [String: Double]
    }

    func fetch() async throws -> ExchangeRates {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.decode(data, now: Date())
    }

    static func decode(_ data: Data, now: Date) throws -> ExchangeRates {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard decoded.result == "success", !decoded.rates.isEmpty else { throw URLError(.cannotParseResponse) }
        return ExchangeRates(
            base: decoded.base_code,
            rates: decoded.rates,
            updated: Date(timeIntervalSince1970: decoded.time_last_update_unix),
            fetched: now
        )
    }
}

/// The last rates, kept in the feature's storage so conversions work offline. Fetched
/// when missing, and again when older than a day if refreshing is on.
actor ExchangeRateStore {
    static let fileName = "rates"
    static let maxAge: TimeInterval = 24 * 3600

    private let source: any ExchangeRateSource
    private let storage: FeatureStorage?
    private var cached: ExchangeRates?
    private var didLoad = false
    private var fetchTask: Task<ExchangeRates?, Never>?
    private var lastFailure: Date?

    init(source: any ExchangeRateSource, storage: FeatureStorage?, initial: ExchangeRates? = nil) {
        self.source = source
        self.storage = storage
        self.cached = initial
        self.didLoad = initial != nil
    }

    /// What's cached (from memory or disk), without fetching.
    func current() -> ExchangeRates? {
        loadIfNeeded()
        return cached
    }

    func isStale(now: Date = Date()) -> Bool {
        guard let cached = current() else { return true }
        return now.timeIntervalSince(cached.fetched) > Self.maxAge
    }

    /// Fetches unless a fetch failed in the last minute. Returns the newest rates.
    @discardableResult
    func refresh() async -> ExchangeRates? {
        if let fetchTask {
            return await fetchTask.value
        }
        if let lastFailure, Date().timeIntervalSince(lastFailure) < 60 {
            return current()
        }
        let source = source
        let task = Task<ExchangeRates?, Never> {
            try? await source.fetch()
        }
        fetchTask = task
        let fetched = await task.value
        fetchTask = nil
        if let fetched {
            cached = fetched
            lastFailure = nil
            try? storage?.write(fetched, named: Self.fileName)
        } else {
            lastFailure = Date()
        }
        return cached
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        cached = try? storage?.read(ExchangeRates.self, named: Self.fileName)
    }
}

/// Currency names people type.
enum CurrencyNames {
    /// Recognised without an explicit target ("100 eur" converts to your currency).
    static let common: Set<String> = [
        "USD", "EUR", "GBP", "JPY", "INR", "CNY", "CAD", "AUD", "NZD", "CHF", "SEK", "NOK",
        "DKK", "PLN", "CZK", "HUF", "RON", "TRY", "RUB", "UAH", "BRL", "MXN", "ARS", "CLP",
        "COP", "ZAR", "NGN", "EGP", "KES", "AED", "SAR", "ILS", "QAR", "KWD", "SGD", "HKD",
        "TWD", "KRW", "THB", "MYR", "IDR", "PHP", "VND", "PKR", "BDT", "LKR", "NPR", "ISK",
        "BTC",
    ]

    /// Longest first where one is a prefix of another ("R$" before "$").
    static let symbols: [(String, String)] = [
        ("US$", "USD"), ("A$", "AUD"), ("C$", "CAD"), ("NZ$", "NZD"), ("HK$", "HKD"),
        ("S$", "SGD"), ("R$", "BRL"), ("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("¥", "JPY"),
        ("₹", "INR"), ("₩", "KRW"), ("₽", "RUB"), ("₺", "TRY"), ("฿", "THB"), ("₪", "ILS"),
        ("₫", "VND"), ("₱", "PHP"), ("₴", "UAH"), ("zł", "PLN"), ("₦", "NGN"), ("₿", "BTC"),
    ]

    static let words: [String: String] = [
        "dollar": "USD", "dollars": "USD", "bucks": "USD", "usd": "USD",
        "euro": "EUR", "euros": "EUR",
        "quid": "GBP", "sterling": "GBP",
        "yen": "JPY",
        "rupee": "INR", "rupees": "INR", "rs": "INR",
        "yuan": "CNY", "rmb": "CNY", "renminbi": "CNY",
        "franc": "CHF", "francs": "CHF",
        "won": "KRW",
        "rouble": "RUB", "roubles": "RUB", "ruble": "RUB", "rubles": "RUB",
        "lira": "TRY", "baht": "THB", "peso": "MXN", "pesos": "MXN", "real": "BRL", "reais": "BRL",
        "rand": "ZAR", "dirham": "AED", "riyal": "SAR", "shekel": "ILS", "shekels": "ILS",
        "zloty": "PLN", "ringgit": "MYR", "rupiah": "IDR", "dong": "VND", "bitcoin": "BTC",
    ]

    /// A typed code, symbol or name → ISO code. Three-letter codes count only if `known`
    /// (the rates have them) or they're common.
    static func code(for raw: String, known: (String) -> Bool) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if let symbol = symbols.first(where: { $0.0 == text }) {
            return symbol.1
        }
        let lower = text.lowercased()
        if let word = words[lower] {
            return word
        }
        let upper = text.uppercased()
        if upper.count == 3, upper.allSatisfy(\.isLetter), common.contains(upper) || known(upper) {
            return upper
        }
        return nil
    }
}

/// "100 usd in inr", "€50 to usd", "100$ in eur", "25 euros" (to your currency).
struct CurrencyQuery: Equatable {
    let amountText: String
    let from: String
    /// `nil`: convert to the default currency.
    let to: String?

    static func parse(_ text: String, known: (String) -> Bool) -> CurrencyQuery? {
        for (left, right) in ConversionSplitter.candidates(text) {
            guard let to = CurrencyNames.code(for: right, known: known),
                  let source = splitAmount(left, known: known)
            else { continue }
            return CurrencyQuery(amountText: source.amount, from: source.code, to: to)
        }
        // No target: only clear amounts of common currencies.
        guard let source = splitAmount(text.trimmingCharacters(in: .whitespaces), known: { _ in false }) else { return nil }
        return CurrencyQuery(amountText: source.amount, from: source.code, to: nil)
    }

    /// "100 usd", "usd 100", "$100", "100$", "1,000 rupees".
    private static func splitAmount(_ text: String, known: (String) -> Bool) -> (amount: String, code: String)? {
        for (symbol, code) in CurrencyNames.symbols {
            if text.hasPrefix(symbol) {
                let amount = String(text.dropFirst(symbol.count)).trimmingCharacters(in: .whitespaces)
                if isAmount(amount) { return (amount, code) }
            }
            if text.hasSuffix(symbol) {
                let amount = String(text.dropLast(symbol.count)).trimmingCharacters(in: .whitespaces)
                if isAmount(amount) { return (amount, code) }
            }
        }
        let words = text.split(separator: " ").map(String.init)
        guard words.count >= 2 else {
            // "100usd"
            let letters = text.reversed().prefix { $0.isLetter }
            guard letters.count >= 2, letters.count < text.count else { return nil }
            let name = String(letters.reversed())
            let amount = String(text.dropLast(letters.count))
            guard let code = CurrencyNames.code(for: name, known: known), isAmount(amount) else { return nil }
            return (amount, code)
        }
        if let code = CurrencyNames.code(for: words.last!, known: known) {
            let amount = words.dropLast().joined(separator: " ")
            if isAmount(amount) { return (amount, code) }
        }
        if let code = CurrencyNames.code(for: words.first!, known: known) {
            let amount = words.dropFirst().joined(separator: " ")
            if isAmount(amount) { return (amount, code) }
        }
        return nil
    }

    private static func isAmount(_ text: String) -> Bool {
        !text.isEmpty && text.contains(where: \.isNumber) && MathExpression.value(of: text) != nil
    }
}
