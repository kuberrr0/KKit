import Foundation

/// Sunrise and sunset from latitude and longitude (NOAA's simplified algorithm,
/// accurate to a minute or two away from the poles).
enum SolarCalculator {
    struct SunTimes: Equatable {
        var sunrise: Date
        var sunset: Date
    }

    /// Sun times for the calendar day containing `date` in `timeZone`. `nil` during polar
    /// day or night.
    static func sunTimes(on date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> SunTimes? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }
        let startOfDay = calendar.startOfDay(for: date)

        guard let rise = utcMinutes(dayOfYear: dayOfYear, latitude: latitude, longitude: longitude, sunrise: true),
              let set = utcMinutes(dayOfYear: dayOfYear, latitude: latitude, longitude: longitude, sunrise: false)
        else { return nil }

        // UTC minutes after midnight → local dates on this calendar day.
        let offset = Double(timeZone.secondsFromGMT(for: startOfDay)) / 60
        func localDate(_ utcMinutes: Double) -> Date {
            var minutes = utcMinutes + offset
            minutes = (minutes.truncatingRemainder(dividingBy: 1440) + 1440).truncatingRemainder(dividingBy: 1440)
            return startOfDay.addingTimeInterval(minutes * 60)
        }
        return SunTimes(sunrise: localDate(rise), sunset: localDate(set))
    }

    /// Minutes after UTC midnight of sunrise or sunset, or `nil` if the sun doesn't cross
    /// the horizon that day.
    private static func utcMinutes(dayOfYear: Int, latitude: Double, longitude: Double, sunrise: Bool) -> Double? {
        let zenith = 90.833 * .pi / 180
        let gamma = 2 * .pi / 365 * Double(dayOfYear - 1)
        let equationOfTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let lat = latitude * .pi / 180
        let cosHourAngle = cos(zenith) / (cos(lat) * cos(declination)) - tan(lat) * tan(declination)
        guard (-1...1).contains(cosHourAngle) else { return nil }
        let hourAngle = acos(cosHourAngle) * 180 / .pi
        let angle = sunrise ? hourAngle : -hourAngle
        return 720 - 4 * (longitude + angle) - equationOfTime
    }
}
