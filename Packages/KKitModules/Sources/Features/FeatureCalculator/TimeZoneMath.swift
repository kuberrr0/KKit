import Foundation

/// A time in a place.
struct ZonedTime: Equatable {
    let date: Date
    let zone: TimeZone
    /// "Tokyo", "IST": how the user named the place.
    let place: String
}

/// "time in tokyo", "tokyo time", "5pm PST in IST", "17:30 london to new york",
/// "9am in sydney" (from here), "noon EST" (to here).
enum TimeZoneMath {
    static func evaluate(_ raw: String, in context: CalendarContext) -> ZonedTime? {
        let text = FuzzyNormalize.collapse(raw.lowercased())
        if let now = currentTime(text, in: context) {
            return now
        }
        for (left, right) in ConversionSplitter.candidates(text) {
            guard let target = zone(named: right) else { continue }
            guard let source = timeAndZone(left, in: context) else { continue }
            return ZonedTime(date: source, zone: target, place: displayName(right, zone: target))
        }
        // "5pm pst": to here.
        if let source = timeAndZone(text, in: context, requireZone: true) {
            return ZonedTime(date: source, zone: context.timeZone, place: String(localized: "here"))
        }
        return nil
    }

    /// "time in tokyo", "time tokyo", "tokyo time", "now in london".
    private static func currentTime(_ text: String, in context: CalendarContext) -> ZonedTime? {
        var place: String?
        for prefix in ["what time is it in ", "current time in ", "time in ", "time at ", "now in ", "time "] where text.hasPrefix(prefix) {
            place = String(text.dropFirst(prefix.count))
            break
        }
        if place == nil, text.hasSuffix(" time") {
            place = String(text.dropLast(" time".count))
        }
        guard let place, let zone = zone(named: place) else { return nil }
        return ZonedTime(date: context.now, zone: zone, place: displayName(place, zone: zone))
    }

    /// "5pm pst", "17:30 london", "noon" (here). The date is today in that zone.
    private static func timeAndZone(_ text: String, in context: CalendarContext, requireZone: Bool = false) -> Date? {
        let words = text.split(separator: " ").map(String.init)
        // The time is the first one or two words ("5 pm"), the zone the rest.
        for count in [2, 1] where words.count >= count {
            let timeText = words.prefix(count).joined()
            guard let time = parseTime(timeText) else { continue }
            let zoneText = words.dropFirst(count).joined(separator: " ")
            let zone: TimeZone
            if zoneText.isEmpty {
                guard !requireZone else { return nil }
                zone = context.timeZone
            } else {
                guard let named = self.zone(named: zoneText) else { continue }
                zone = named
            }
            var calendar = context.calendar
            calendar.timeZone = zone
            var components = calendar.dateComponents([.year, .month, .day], from: context.now)
            components.hour = time.hour
            components.minute = time.minute
            return calendar.date(from: components)
        }
        return nil
    }

    /// "5pm", "5:30pm", "5:30 pm" (joined), "17:00", "1730", "noon", "midnight".
    static func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
        switch text {
        case "noon", "midday": return (12, 0)
        case "midnight": return (0, 0)
        default: break
        }
        var body = text
        var meridiem: String?
        for suffix in ["am", "pm", "a.m.", "p.m.", "a", "p"] where body.hasSuffix(suffix) {
            meridiem = suffix.hasPrefix("a") ? "am" : "pm"
            body = String(body.dropLast(suffix.count))
            break
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        var hour: Int
        var minute = 0
        if parts.count == 2 {
            guard let h = Int(parts[0]), let m = Int(parts[1]), parts[1].count == 2 else { return nil }
            hour = h
            minute = m
        } else if parts.count == 1, let value = Int(body), !body.isEmpty {
            if body.count >= 3 {
                // "1730", "530pm".
                guard body.count <= 4 else { return nil }
                hour = value / 100
                minute = value % 100
            } else {
                hour = value
                // A bare number isn't a time: "5 tokyo" is ambiguous, "5pm tokyo" isn't.
                guard meridiem != nil else { return nil }
            }
        } else {
            return nil
        }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    // MARK: Zones

    /// Common abbreviations, to the zone people mean (DST-aware: "PST" in summer is PDT).
    static let abbreviations: [String: String] = [
        "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "pt": "America/Los_Angeles", "pacific": "America/Los_Angeles",
        "mst": "America/Denver", "mdt": "America/Denver", "mt": "America/Denver", "mountain": "America/Denver",
        "cst": "America/Chicago", "cdt": "America/Chicago", "ct": "America/Chicago", "central": "America/Chicago",
        "est": "America/New_York", "edt": "America/New_York", "et": "America/New_York", "eastern": "America/New_York",
        "akst": "America/Anchorage", "hst": "Pacific/Honolulu",
        "gmt": "GMT", "utc": "UTC", "z": "UTC", "zulu": "UTC",
        "bst": "Europe/London", "wet": "Europe/Lisbon", "cet": "Europe/Paris", "cest": "Europe/Paris",
        "eet": "Europe/Athens", "eest": "Europe/Athens", "msk": "Europe/Moscow",
        "ist": "Asia/Kolkata", "pkt": "Asia/Karachi", "npt": "Asia/Kathmandu", "gst": "Asia/Dubai",
        "sgt": "Asia/Singapore", "hkt": "Asia/Hong_Kong", "cst china": "Asia/Shanghai",
        "jst": "Asia/Tokyo", "kst": "Asia/Seoul", "wib": "Asia/Jakarta", "pht": "Asia/Manila",
        "aest": "Australia/Sydney", "aedt": "Australia/Sydney", "acst": "Australia/Adelaide", "awst": "Australia/Perth",
        "nzst": "Pacific/Auckland", "nzdt": "Pacific/Auckland", "brt": "America/Sao_Paulo", "art": "America/Argentina/Buenos_Aires",
    ]

    /// Places that aren't a zone's city, or are spelled differently.
    static let places: [String: String] = [
        "new york": "America/New_York", "nyc": "America/New_York", "ny": "America/New_York", "boston": "America/New_York",
        "washington": "America/New_York", "miami": "America/New_York", "atlanta": "America/New_York", "toronto": "America/Toronto",
        "san francisco": "America/Los_Angeles", "sf": "America/Los_Angeles", "la": "America/Los_Angeles",
        "seattle": "America/Los_Angeles", "silicon valley": "America/Los_Angeles", "portland": "America/Los_Angeles",
        "austin": "America/Chicago", "dallas": "America/Chicago", "houston": "America/Chicago",
        "india": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "bombay": "Asia/Kolkata", "delhi": "Asia/Kolkata", "new delhi": "Asia/Kolkata",
        "bangalore": "Asia/Kolkata", "bengaluru": "Asia/Kolkata", "chennai": "Asia/Kolkata", "hyderabad": "Asia/Kolkata",
        "pune": "Asia/Kolkata", "kolkata": "Asia/Kolkata", "calcutta": "Asia/Kolkata",
        "china": "Asia/Shanghai", "beijing": "Asia/Shanghai", "shenzhen": "Asia/Shanghai",
        "japan": "Asia/Tokyo", "korea": "Asia/Seoul", "uk": "Europe/London", "england": "Europe/London",
        "france": "Europe/Paris", "germany": "Europe/Berlin", "munich": "Europe/Berlin", "spain": "Europe/Madrid",
        "italy": "Europe/Rome", "netherlands": "Europe/Amsterdam", "switzerland": "Europe/Zurich",
        "australia": "Australia/Sydney", "new zealand": "Pacific/Auckland", "brazil": "America/Sao_Paulo",
        "dubai": "Asia/Dubai", "uae": "Asia/Dubai", "singapore": "Asia/Singapore", "hong kong": "Asia/Hong_Kong",
        "here": "", "local": "",
    ]

    /// City → zone from every IANA identifier ("Asia/Tokyo" → "tokyo").
    static let cities: [String: String] = {
        var map: [String: String] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let city = identifier.split(separator: "/").last else { continue }
            map[city.replacingOccurrences(of: "_", with: " ").lowercased()] = identifier
            map[identifier.lowercased()] = identifier
        }
        return map
    }()

    static func zone(named raw: String) -> TimeZone? {
        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return nil }
        if let identifier = places[name] ?? abbreviations[name] ?? cities[name] {
            return identifier.isEmpty ? TimeZone.current : TimeZone(identifier: identifier)
        }
        return nil
    }

    private static func displayName(_ typed: String, zone: TimeZone) -> String {
        let name = typed.trimmingCharacters(in: .whitespaces)
        if name.count <= 4, abbreviations[name.lowercased()] != nil {
            return name.uppercased()
        }
        return name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
