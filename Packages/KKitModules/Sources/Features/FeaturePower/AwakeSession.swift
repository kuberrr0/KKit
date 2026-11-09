import Foundation

/// A manual "keep awake" request.
struct AwakeSession: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case indefinite
        case until(Date)
    }

    var mode: Mode
    var started: Date

    static func indefinite(now: Date) -> AwakeSession {
        AwakeSession(mode: .indefinite, started: now)
    }

    static func duration(_ seconds: TimeInterval, now: Date) -> AwakeSession {
        AwakeSession(mode: .until(now.addingTimeInterval(max(seconds, 1))), started: now)
    }

    var endDate: Date? {
        if case .until(let end) = mode { end } else { nil }
    }

    /// Seconds left; `nil` for indefinite.
    func remaining(at now: Date) -> TimeInterval? {
        endDate.map { max(0, $0.timeIntervalSince(now)) }
    }

    func isExpired(at now: Date) -> Bool {
        guard let endDate else { return false }
        return now >= endDate
    }
}

/// Why the Mac is being kept awake.
enum AwakeReason: Hashable, Sendable {
    case manual
    case powerAdapter
    case externalDisplay
    case app(String)
}

/// The inputs the automatic rules look at.
struct AwakeConditions: Equatable, Sendable {
    var isOnAC: Bool
    var batteryLevel: Double?
    var hasExternalDisplay: Bool
    var runningBundleIDs: Set<String>
}

/// The rule settings.
struct AwakeRules: Equatable, Sendable {
    var onPowerAdapter: Bool
    var withExternalDisplay: Bool
    var whileApps: [String]
    /// Percent, 0 = off.
    var batteryCutoff: Int

    /// Reasons the automatic rules give for staying awake right now.
    func reasons(for conditions: AwakeConditions) -> Set<AwakeReason> {
        var reasons: Set<AwakeReason> = []
        if onPowerAdapter, conditions.isOnAC {
            reasons.insert(.powerAdapter)
        }
        if withExternalDisplay, conditions.hasExternalDisplay {
            reasons.insert(.externalDisplay)
        }
        for app in whileApps where conditions.runningBundleIDs.contains(app) {
            reasons.insert(.app(app))
        }
        if isBelowCutoff(conditions) {
            // On battery below the cut-off nothing keeps the Mac awake.
            return []
        }
        return reasons
    }

    func isBelowCutoff(_ conditions: AwakeConditions) -> Bool {
        guard batteryCutoff > 0, !conditions.isOnAC, let level = conditions.batteryLevel else { return false }
        return level * 100 < Double(batteryCutoff)
    }
}

/// Parses "17:30", "5:30pm", "5pm" into the next such time after `now`.
enum ClockTimeParser {
    static func nextDate(from text: String, after now: Date, calendar: Calendar = .current) -> Date? {
        var input = text.lowercased().trimmingCharacters(in: .whitespaces)
        var pm: Bool?
        if input.hasSuffix("pm") {
            pm = true
            input.removeLast(2)
        } else if input.hasSuffix("am") {
            pm = false
            input.removeLast(2)
        }
        let parts = input.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let first = parts.first, var hour = Int(first), parts.count <= 2 else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) : 0
        guard let minute, (0..<60).contains(minute) else { return nil }
        if let pm {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (pm ? 12 : 0)
        }
        guard (0..<24).contains(hour) else { return nil }
        return calendar.nextDate(
            after: now,
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime
        )
    }
}
