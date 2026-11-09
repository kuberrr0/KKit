import Foundation

/// What a unit measures. Only units of the same dimension convert.
enum UnitDimension: String, Sendable {
    case length, mass, temperature, volume, area, data, time, speed, angle, energy, power, pressure
}

/// A unit: `value × factor + offset` is the value in the dimension's base unit (metres,
/// kilograms, kelvin, litres, square metres, bytes, seconds, m/s, radians, joules,
/// watts, pascals).
struct UnitDefinition: Sendable, Hashable {
    let symbol: String
    let dimension: UnitDimension
    let factor: Double
    let offset: Double
    /// Lowercased names it's typed as, including the symbol.
    let aliases: [String]

    init(_ symbol: String, _ dimension: UnitDimension, _ factor: Double, offset: Double = 0, _ aliases: [String]) {
        self.symbol = symbol
        self.dimension = dimension
        self.factor = factor
        self.offset = offset
        // Plurals for spelled-out names: "meter" → "meters".
        var all = [symbol.lowercased()]
        for alias in aliases {
            all.append(alias)
            if alias.count > 3, alias.allSatisfy(\.isLetter), !alias.hasSuffix("s") {
                all.append(alias + "s")
            }
        }
        var seen = Set<String>()
        self.aliases = all.filter { seen.insert($0).inserted }
    }

    func toBase(_ value: Double) -> Double {
        value * factor + offset
    }

    func fromBase(_ value: Double) -> Double {
        (value - offset) / factor
    }
}

/// KKit's own unit table, so names like "ft", "fl oz", "km/h" and "°F" parse the way
/// people type them. (Foundation's `Measurement` formats units but doesn't parse names.)
enum UnitTable {
    static let units: [UnitDefinition] = {
        let inch = 0.0254
        let foot = 0.3048
        let mile = 1609.344
        let pound = 0.45359237
        let gallon = 3.785411784
        let fluidOunce = 0.0295735295625
        let day = 86_400.0
        return [
            // Length (metres)
            UnitDefinition("mm", .length, 0.001, ["millimeter", "millimetre"]),
            UnitDefinition("cm", .length, 0.01, ["centimeter", "centimetre"]),
            UnitDefinition("m", .length, 1, ["meter", "metre"]),
            UnitDefinition("km", .length, 1000, ["kilometer", "kilometre", "kms"]),
            UnitDefinition("µm", .length, 1e-6, ["um", "micrometer", "micrometre", "micron"]),
            UnitDefinition("nm", .length, 1e-9, ["nanometer", "nanometre"]),
            UnitDefinition("in", .length, inch, ["inch", "inches", "\""]),
            UnitDefinition("ft", .length, foot, ["foot", "feet", "'"]),
            UnitDefinition("yd", .length, 0.9144, ["yard"]),
            UnitDefinition("mi", .length, mile, ["mile"]),
            UnitDefinition("nmi", .length, 1852, ["nautical mile", "nautical miles"]),
            UnitDefinition("ly", .length, 9.4607304725808e15, ["light year", "light years", "lightyear"]),
            UnitDefinition("au", .length, 1.495978707e11, ["astronomical unit"]),
            // Mass (kilograms)
            UnitDefinition("mg", .mass, 1e-6, ["milligram", "milligramme"]),
            UnitDefinition("g", .mass, 0.001, ["gram", "gramme", "gr"]),
            UnitDefinition("kg", .mass, 1, ["kilogram", "kilogramme", "kilo", "kgs"]),
            UnitDefinition("t", .mass, 1000, ["tonne", "metric ton", "metric tons"]),
            UnitDefinition("oz", .mass, pound / 16, ["ounce"]),
            UnitDefinition("lb", .mass, pound, ["lbs", "pound"]),
            UnitDefinition("st", .mass, pound * 14, ["stone"]),
            // Temperature (kelvin)
            UnitDefinition("°C", .temperature, 1, offset: 273.15, ["c", "celsius", "centigrade", "degc", "deg c"]),
            UnitDefinition("°F", .temperature, 5.0 / 9.0, offset: 273.15 - 32 * 5.0 / 9.0, ["f", "fahrenheit", "degf", "deg f"]),
            UnitDefinition("K", .temperature, 1, ["kelvin"]),
            // Volume (litres)
            UnitDefinition("ml", .volume, 0.001, ["milliliter", "millilitre", "cc"]),
            UnitDefinition("cl", .volume, 0.01, ["centiliter", "centilitre"]),
            UnitDefinition("dl", .volume, 0.1, ["deciliter", "decilitre"]),
            UnitDefinition("l", .volume, 1, ["liter", "litre", "ltr"]),
            UnitDefinition("m³", .volume, 1000, ["m3", "cubic meter", "cubic metre", "cubic meters", "cubic metres"]),
            UnitDefinition("tsp", .volume, 0.00492892159375, ["teaspoon"]),
            UnitDefinition("tbsp", .volume, 0.01478676478125, ["tablespoon"]),
            UnitDefinition("fl oz", .volume, fluidOunce, ["floz", "fluid ounce", "fluid ounces"]),
            UnitDefinition("cup", .volume, 0.2365882365, ["cups"]),
            UnitDefinition("pt", .volume, 0.473176473, ["pint"]),
            UnitDefinition("qt", .volume, 0.946352946, ["quart"]),
            UnitDefinition("gal", .volume, gallon, ["gallon", "us gallon", "us gallons"]),
            UnitDefinition("imp gal", .volume, 4.54609, ["imperial gallon", "imperial gallons", "uk gallon", "uk gallons"]),
            // Area (square metres)
            UnitDefinition("mm²", .area, 1e-6, ["mm2", "sq mm", "square millimeter", "square millimeters"]),
            UnitDefinition("cm²", .area, 1e-4, ["cm2", "sq cm", "square centimeter", "square centimeters"]),
            UnitDefinition("m²", .area, 1, ["m2", "sq m", "sqm", "square meter", "square metre", "square meters", "square metres"]),
            UnitDefinition("km²", .area, 1e6, ["km2", "sq km", "square kilometer", "square kilometers"]),
            UnitDefinition("ft²", .area, foot * foot, ["ft2", "sq ft", "sqft", "square foot", "square feet"]),
            UnitDefinition("in²", .area, inch * inch, ["in2", "sq in", "square inch", "square inches"]),
            UnitDefinition("mi²", .area, mile * mile, ["mi2", "sq mi", "square mile", "square miles"]),
            UnitDefinition("acre", .area, 4046.8564224, ["acres", "ac"]),
            UnitDefinition("ha", .area, 10_000, ["hectare"]),
            // Data (bytes): kB, MB… are decimal, KiB, MiB… binary.
            UnitDefinition("bit", .data, 0.125, ["bits"]),
            UnitDefinition("B", .data, 1, ["b", "byte"]),
            UnitDefinition("kB", .data, 1e3, ["kilobyte", "kbyte"]),
            UnitDefinition("MB", .data, 1e6, ["megabyte", "mbyte"]),
            UnitDefinition("GB", .data, 1e9, ["gigabyte", "gbyte", "gig", "gigs"]),
            UnitDefinition("TB", .data, 1e12, ["terabyte"]),
            UnitDefinition("PB", .data, 1e15, ["petabyte"]),
            UnitDefinition("KiB", .data, 1024, ["kibibyte"]),
            UnitDefinition("MiB", .data, 1_048_576, ["mebibyte"]),
            UnitDefinition("GiB", .data, 1_073_741_824, ["gibibyte"]),
            UnitDefinition("TiB", .data, 1_099_511_627_776, ["tebibyte"]),
            UnitDefinition("kbit", .data, 125, ["kilobit", "kb/s", "kbps"]),
            UnitDefinition("Mbit", .data, 125_000, ["megabit", "mbps"]),
            UnitDefinition("Gbit", .data, 125_000_000, ["gigabit", "gbps"]),
            // Time (seconds)
            UnitDefinition("ns", .time, 1e-9, ["nanosecond"]),
            UnitDefinition("µs", .time, 1e-6, ["us", "microsecond"]),
            UnitDefinition("ms", .time, 0.001, ["millisecond"]),
            UnitDefinition("s", .time, 1, ["sec", "secs", "second"]),
            UnitDefinition("min", .time, 60, ["mins", "minute"]),
            UnitDefinition("h", .time, 3600, ["hr", "hrs", "hour"]),
            UnitDefinition("d", .time, day, ["day"]),
            UnitDefinition("wk", .time, day * 7, ["week", "wks"]),
            UnitDefinition("mo", .time, day * 30.436875, ["month"]),
            UnitDefinition("yr", .time, day * 365.2425, ["year", "yrs"]),
            // Speed (metres per second)
            UnitDefinition("m/s", .speed, 1, ["mps", "meters per second", "metres per second"]),
            UnitDefinition("km/h", .speed, 1000 / 3600.0, ["kmh", "kph", "kmph", "km per hour"]),
            UnitDefinition("mph", .speed, mile / 3600, ["mi/h", "miles per hour"]),
            UnitDefinition("kn", .speed, 1852 / 3600.0, ["knot", "kt", "kts"]),
            UnitDefinition("ft/s", .speed, foot, ["fps", "feet per second"]),
            // Angle (radians)
            UnitDefinition("°", .angle, Double.pi / 180, ["deg", "degree"]),
            UnitDefinition("rad", .angle, 1, ["radian"]),
            UnitDefinition("grad", .angle, Double.pi / 200, ["gon", "gradian"]),
            UnitDefinition("turn", .angle, 2 * Double.pi, ["rev", "revolution"]),
            // Energy (joules)
            UnitDefinition("J", .energy, 1, ["joule"]),
            UnitDefinition("kJ", .energy, 1000, ["kilojoule"]),
            UnitDefinition("cal", .energy, 4.184, ["calorie"]),
            UnitDefinition("kcal", .energy, 4184, ["kilocalorie", "kcals"]),
            UnitDefinition("Wh", .energy, 3600, ["watt hour", "watt hours"]),
            UnitDefinition("kWh", .energy, 3_600_000, ["kilowatt hour", "kilowatt hours"]),
            UnitDefinition("eV", .energy, 1.602176634e-19, ["electronvolt"]),
            UnitDefinition("BTU", .energy, 1055.05585262, ["btus"]),
            // Power (watts)
            UnitDefinition("W", .power, 1, ["watt"]),
            UnitDefinition("kW", .power, 1000, ["kilowatt"]),
            UnitDefinition("MW", .power, 1e6, ["megawatt"]),
            UnitDefinition("hp", .power, 745.69987158227022, ["horsepower"]),
            // Pressure (pascals)
            UnitDefinition("Pa", .pressure, 1, ["pascal"]),
            UnitDefinition("kPa", .pressure, 1000, ["kilopascal"]),
            UnitDefinition("bar", .pressure, 100_000, ["bars"]),
            UnitDefinition("atm", .pressure, 101_325, ["atmosphere"]),
            UnitDefinition("psi", .pressure, 6894.757293168, ["pounds per square inch"]),
            UnitDefinition("mmHg", .pressure, 133.322387415, ["torr"]),
        ]
    }()

    /// Alias → unit. Where two units share an alias the first in the table wins.
    static let byAlias: [String: UnitDefinition] = {
        var map: [String: UnitDefinition] = [:]
        for unit in units {
            for alias in unit.aliases where map[alias] == nil {
                map[alias] = unit
            }
        }
        return map
    }()

    /// Longest first, so "fl oz" wins over "oz" and "km/h" over "h".
    static let aliasesByLength: [String] = byAlias.keys.sorted { $0.count > $1.count }

    static func unit(named name: String) -> UnitDefinition? {
        byAlias[name.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// "5 ft", "5ft", "1.5 fl oz", "2*3 km" → (amount text, unit).
    static func splitAmount(_ text: String) -> (amount: String, unit: UnitDefinition)? {
        let lower = text.lowercased()
        for alias in aliasesByLength where lower.hasSuffix(alias) {
            let amount = String(text.dropLast(alias.count)).trimmingCharacters(in: .whitespaces)
            guard !amount.isEmpty, let unit = byAlias[alias] else { continue }
            // "5 cft" isn't "5 c": a letter before a letter-initial alias means a longer word.
            if let last = amount.last, last.isLetter, alias.first?.isLetter == true, !lower.hasSuffix(" " + alias) {
                continue
            }
            return (amount, unit)
        }
        return nil
    }
}

/// "5 ft in cm", "72 F to C", "3 GB in MB", "10 km/h as mph".
enum UnitConversion {
    struct Result: Equatable {
        let value: Double
        let from: UnitDefinition
        let to: UnitDefinition
        let amount: Double
    }

    static func convert(_ text: String) -> Result? {
        for (left, right) in ConversionSplitter.candidates(text) {
            guard let target = UnitTable.unit(named: right), let split = UnitTable.splitAmount(left) else { continue }
            let source = split.unit
            guard source.dimension == target.dimension, source != target,
                  let amount = MathExpression.value(of: split.amount)
            else { continue }
            let value = target.fromBase(source.toBase(amount))
            guard value.isFinite else { continue }
            return Result(value: value, from: source, to: target, amount: amount)
        }
        return nil
    }
}

/// Splits "A in B" / "A to B" / "A as B" / "A = B" / "A → B" into candidates, from the
/// last connector back: "12 in to cm" tries "12 in" | "cm" before "12" | "to cm".
enum ConversionSplitter {
    static let connectors = [" in ", " to ", " into ", " as ", " = ", " → ", " -> ", " => "]

    static func candidates(_ text: String) -> [(String, String)] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        var found: [(String.Index, Int)] = []
        for connector in connectors {
            var searchStart = lower.startIndex
            while let range = lower.range(of: connector, range: searchStart..<lower.endIndex) {
                found.append((range.lowerBound, connector.count))
                searchStart = lower.index(after: range.lowerBound)
            }
        }
        found.sort { $0.0 > $1.0 }
        return found.compactMap { start, length in
            let offset = lower.distance(from: lower.startIndex, to: start)
            let leftEnd = trimmed.index(trimmed.startIndex, offsetBy: offset)
            let rightStart = trimmed.index(leftEnd, offsetBy: length)
            let left = String(trimmed[..<leftEnd]).trimmingCharacters(in: .whitespaces)
            let right = String(trimmed[rightStart...]).trimmingCharacters(in: .whitespaces)
            guard !left.isEmpty, !right.isEmpty else { return nil }
            return (left, right)
        }
    }
}
