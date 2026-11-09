import Foundation
import KKitServicesAPI

/// When the schedule says Night Shift should be on.
struct NightShiftSchedule: Equatable, Sendable {
    var kind: NightShiftScheduleKind
    /// Minutes after midnight.
    var startMinutes: Int
    var endMinutes: Int
    var coordinate: Coordinate?

    /// `nil` for the manual schedule.
    func isActive(at date: Date, calendar: Calendar = .current) -> Bool? {
        switch kind {
        case .manual:
            return nil
        case .custom:
            return Self.isWithin(minutes: Self.minutes(of: date, calendar: calendar), start: startMinutes, end: endMinutes)
        case .sunset:
            guard let coordinate,
                  let sun = SolarCalculator.sunTimes(on: date, latitude: coordinate.latitude, longitude: coordinate.longitude, timeZone: calendar.timeZone)
            else {
                // No location yet, or polar day/night: fall back to the custom times.
                return Self.isWithin(minutes: Self.minutes(of: date, calendar: calendar), start: startMinutes, end: endMinutes)
            }
            return date >= sun.sunset || date < sun.sunrise
        }
    }

    /// The next time `isActive` may flip after `date`, so the controller can sleep until then.
    func nextChange(after date: Date, calendar: Calendar = .current) -> Date? {
        switch kind {
        case .manual:
            return nil
        case .custom:
            return Self.nextMinutes([startMinutes, endMinutes], after: date, calendar: calendar)
        case .sunset:
            guard let coordinate else {
                return Self.nextMinutes([startMinutes, endMinutes], after: date, calendar: calendar)
            }
            var candidates: [Date] = []
            for dayOffset in 0...1 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: date),
                      let sun = SolarCalculator.sunTimes(on: day, latitude: coordinate.latitude, longitude: coordinate.longitude, timeZone: calendar.timeZone)
                else { continue }
                candidates.append(contentsOf: [sun.sunrise, sun.sunset])
            }
            return candidates.filter { $0 > date }.min()
                ?? Self.nextMinutes([startMinutes, endMinutes], after: date, calendar: calendar)
        }
    }

    static func minutes(of date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Whether `minutes` falls in [start, end), wrapping past midnight when end < start.
    static func isWithin(minutes: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        if start < end {
            return minutes >= start && minutes < end
        }
        return minutes >= start || minutes < end
    }

    private static func nextMinutes(_ values: [Int], after date: Date, calendar: Calendar) -> Date? {
        values.compactMap { value in
            calendar.nextDate(
                after: date,
                matching: DateComponents(hour: value / 60, minute: value % 60, second: 0),
                matchingPolicy: .nextTime
            )
        }.min()
    }
}
