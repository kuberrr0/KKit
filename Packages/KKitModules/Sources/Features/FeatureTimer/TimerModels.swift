import Foundation

/// A countdown. Running when `endDate` is set, paused when `pausedRemaining` is.
struct Countdown: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    var label: String?
    var duration: TimeInterval
    var endDate: Date?
    var pausedRemaining: TimeInterval?

    init(duration: TimeInterval, label: String? = nil, start: Date) {
        self.duration = duration
        self.label = label
        self.endDate = start.addingTimeInterval(duration)
    }

    var isRunning: Bool { endDate != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return pausedRemaining ?? duration
    }

    /// 0 at the start, 1 when done.
    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(max(1 - remaining(at: date) / duration, 0), 1)
    }

    func isFinished(at date: Date) -> Bool {
        guard let endDate else { return false }
        return endDate <= date
    }

    mutating func pause(at date: Date) {
        guard isRunning else { return }
        pausedRemaining = remaining(at: date)
        endDate = nil
    }

    mutating func resume(at date: Date) {
        guard !isRunning else { return }
        endDate = date.addingTimeInterval(pausedRemaining ?? duration)
        pausedRemaining = nil
    }

    mutating func add(_ seconds: TimeInterval, at date: Date) {
        let remaining = remaining(at: date) + seconds
        duration = max(duration + seconds, remaining)
        if isRunning {
            endDate = date.addingTimeInterval(max(0, remaining))
        } else {
            pausedRemaining = max(0, remaining)
        }
    }

    var title: String { label ?? String(localized: "Timer") }
}

enum PomodoroPhase: String, Codable, Sendable {
    case work
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .work: String(localized: "Focus")
        case .shortBreak: String(localized: "Break")
        case .longBreak: String(localized: "Long break")
        }
    }

    var symbol: String {
        switch self {
        case .work: "brain.head.profile"
        case .shortBreak, .longBreak: "cup.and.saucer"
        }
    }
}

struct PomodoroLengths: Sendable, Equatable {
    var work: TimeInterval
    var shortBreak: TimeInterval
    var longBreak: TimeInterval
    var longBreakEvery: Int

    static let standard = PomodoroLengths(work: 25 * 60, shortBreak: 5 * 60, longBreak: 15 * 60, longBreakEvery: 4)

    func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .work: work
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}

/// A Pomodoro cycle: work, break, work, … with a long break every `longBreakEvery`.
struct Pomodoro: Codable, Sendable, Equatable {
    var phase: PomodoroPhase
    /// Work intervals finished in this cycle.
    var completedWork: Int
    var phaseDuration: TimeInterval
    var endDate: Date?
    var pausedRemaining: TimeInterval?

    static func start(_ lengths: PomodoroLengths, at date: Date) -> Pomodoro {
        Pomodoro(phase: .work, completedWork: 0, phaseDuration: lengths.work, endDate: date.addingTimeInterval(lengths.work))
    }

    var isRunning: Bool { endDate != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return pausedRemaining ?? phaseDuration
    }

    func progress(at date: Date) -> Double {
        guard phaseDuration > 0 else { return 1 }
        return min(max(1 - remaining(at: date) / phaseDuration, 0), 1)
    }

    func isFinished(at date: Date) -> Bool {
        guard let endDate else { return false }
        return endDate <= date
    }

    /// The phase after the current one.
    func nextPhase(_ lengths: PomodoroLengths) -> PomodoroPhase {
        guard phase == .work else { return .work }
        let every = max(lengths.longBreakEvery, 1)
        return (completedWork + 1) % every == 0 ? .longBreak : .shortBreak
    }

    /// Moves to the next phase, running if `autoStart`, otherwise paused at its full length.
    mutating func advance(_ lengths: PomodoroLengths, autoStart: Bool, at date: Date) {
        let next = nextPhase(lengths)
        if phase == .work {
            completedWork += 1
        }
        phase = next
        phaseDuration = lengths.duration(of: next)
        if autoStart {
            endDate = date.addingTimeInterval(phaseDuration)
            pausedRemaining = nil
        } else {
            endDate = nil
            pausedRemaining = phaseDuration
        }
    }

    mutating func pause(at date: Date) {
        guard isRunning else { return }
        pausedRemaining = remaining(at: date)
        endDate = nil
    }

    mutating func resume(at date: Date) {
        guard !isRunning else { return }
        endDate = date.addingTimeInterval(pausedRemaining ?? phaseDuration)
        pausedRemaining = nil
    }
}

/// A stopwatch with laps.
struct Stopwatch: Codable, Sendable, Equatable {
    /// Running since; `nil` when paused or reset.
    var startDate: Date?
    /// Time banked before the current run.
    var accumulated: TimeInterval = 0
    /// Total elapsed time at each lap, oldest first.
    var laps: [TimeInterval] = []

    var isRunning: Bool { startDate != nil }
    /// Running, or paused with time on it.
    var isActive: Bool { isRunning || accumulated > 0 }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startDate.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    mutating func start(at date: Date) {
        guard !isRunning else { return }
        startDate = date
    }

    mutating func pause(at date: Date) {
        guard isRunning else { return }
        accumulated = elapsed(at: date)
        startDate = nil
    }

    mutating func lap(at date: Date) {
        guard isActive else { return }
        laps.append(elapsed(at: date))
    }

    mutating func reset() {
        self = Stopwatch()
    }

    /// Each lap's own length, oldest first.
    var lapDurations: [TimeInterval] {
        laps.enumerated().map { index, total in
            index == 0 ? total : total - laps[index - 1]
        }
    }
}

/// Everything that's saved, so timers survive a relaunch.
struct TimerSnapshot: Codable, Sendable, Equatable {
    var countdowns: [Countdown] = []
    var pomodoro: Pomodoro?
    var stopwatch = Stopwatch()
}

/// Something that just ended, to announce.
enum TimerEvent: Equatable {
    case countdownFinished(Countdown)
    case pomodoroPhaseEnded(finished: PomodoroPhase, next: PomodoroPhase)
}

/// Parses what's typed after `timer`: "10m tea", "1h30m", "90s", "1:30", "25".
enum TimerInputParser {
    struct Result: Equatable {
        var seconds: TimeInterval
        var label: String?
    }

    static func parse(_ text: String) -> Result? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var seconds: TimeInterval = 0
        var consumed = 0
        var index = 0
        while index < words.count {
            let word = words[index].lowercased()
            if let number = Double(word), index + 1 < words.count, let unit = unitSeconds(words[index + 1].lowercased()) {
                // "25 min"
                seconds += number * unit
                consumed += 2
                index += 2
            } else if let value = duration(word) {
                seconds += value
                consumed += 1
                index += 1
            } else {
                break
            }
        }
        guard consumed > 0, seconds > 0 else { return nil }
        let label = words.dropFirst(consumed).joined(separator: " ")
        return Result(seconds: seconds, label: label.isEmpty ? nil : label)
    }

    /// One token: "10", "10m", "1h30m", "90s", "1:30", "1:00:00".
    static func duration(_ token: String) -> TimeInterval? {
        if token.contains(":") {
            let parts = token.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
            guard parts.count <= 3, !parts.contains(where: { $0 == nil }) else { return nil }
            return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
        }
        if let minutes = Double(token) {
            return minutes * 60
        }
        var total: TimeInterval = 0
        var number = ""
        var sawUnit = false
        var characters = Array(token)
        // Allow trailing unit words: "10min", "2hours".
        for suffix in ["hours", "hour", "hrs", "hr", "minutes", "minute", "mins", "min", "seconds", "second", "secs", "sec"] where token.hasSuffix(suffix) {
            let short = suffix.first.map(String.init) ?? ""
            characters = Array(token.dropLast(suffix.count) + short)
            break
        }
        for character in characters {
            if character.isNumber || character == "." {
                number.append(character)
            } else if let unit = unitSeconds(String(character)), let value = Double(number) {
                total += value * unit
                number = ""
                sawUnit = true
            } else {
                return nil
            }
        }
        guard sawUnit, number.isEmpty else { return nil }
        return total
    }

    private static func unitSeconds(_ unit: String) -> TimeInterval? {
        switch unit {
        case "h", "hr", "hrs", "hour", "hours": 3600
        case "m", "min", "mins", "minute", "minutes": 60
        case "s", "sec", "secs", "second", "seconds": 1
        default: nil
        }
    }
}
