import Foundation
import KKitCore
import KKitServicesAPI
import Observation

/// Keeps the Mac awake: a manual session plus automatic rules, backed by one IOKit
/// assertion that's held exactly while there's a reason to stay awake.
@MainActor
@Observable
final class PowerController {
    private(set) var session: AwakeSession?
    private(set) var ruleReasons: Set<AwakeReason> = []
    /// Set when the battery cut-off ended a session, for the UI.
    private(set) var stoppedForBattery = false

    private let power: any PowerService
    private let settings: FeatureSettings
    private let now: () -> Date
    @ObservationIgnored private var assertion: (any SleepAssertion)?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private(set) var conditions: AwakeConditions

    init(power: any PowerService, settings: FeatureSettings, now: @escaping () -> Date = { Date() }) {
        self.power = power
        self.settings = settings
        self.now = now
        let source = power.powerSource
        self.conditions = AwakeConditions(
            isOnAC: source.isOnAC,
            batteryLevel: source.batteryLevel,
            hasExternalDisplay: false,
            runningBundleIDs: []
        )
    }

    var isAwake: Bool { session != nil || !ruleReasons.isEmpty }

    var reasons: Set<AwakeReason> {
        session == nil ? ruleReasons : ruleReasons.union([.manual])
    }

    var heldAssertionKind: SleepAssertionKind? { assertion?.kind }

    private var rules: AwakeRules {
        AwakeRules(
            onPowerAdapter: settings[PowerSettings.awakeOnPowerAdapter],
            withExternalDisplay: settings[PowerSettings.awakeWithExternalDisplay],
            whileApps: settings[PowerSettings.awakeWhileApps],
            batteryCutoff: settings[PowerSettings.batteryCutoff]
        )
    }

    // MARK: Manual

    func keepAwake(for seconds: TimeInterval?) {
        if let seconds {
            begin(.duration(seconds, now: now()))
        } else {
            begin(.indefinite(now: now()))
        }
    }

    func keepAwake(until date: Date) {
        begin(.duration(date.timeIntervalSince(now()), now: now()))
    }

    /// Toggles a session of the default length.
    func toggle() {
        if session != nil {
            allowSleep()
        } else {
            let minutes = settings[PowerSettings.defaultMinutes]
            keepAwake(for: minutes > 0 ? TimeInterval(minutes * 60) : nil)
        }
    }

    func allowSleep() {
        session = nil
        expiryTask?.cancel()
        expiryTask = nil
        updateAssertion()
    }

    /// Adds `seconds` to a timed session (or starts one).
    func extend(by seconds: TimeInterval) {
        if let end = session?.endDate {
            begin(AwakeSession(mode: .until(end.addingTimeInterval(seconds)), started: session?.started ?? now()))
        } else if session == nil {
            keepAwake(for: seconds)
        }
    }

    private func begin(_ newSession: AwakeSession) {
        stoppedForBattery = false
        if rules.isBelowCutoff(conditions) {
            stoppedForBattery = true
            return
        }
        session = newSession
        scheduleExpiry()
        updateAssertion()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let remaining = session?.remaining(at: now()) else {
            expiryTask = nil
            return
        }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self else { return }
            self.checkExpiry()
        }
    }

    func checkExpiry() {
        guard let session, session.isExpired(at: now()) else { return }
        allowSleep()
    }

    // MARK: Rules

    func update(conditions: AwakeConditions) {
        self.conditions = conditions
        reevaluate()
    }

    /// Re-applies rules and settings (call when a setting changes).
    func reevaluate() {
        let rules = self.rules
        if session != nil, rules.isBelowCutoff(conditions) {
            session = nil
            expiryTask?.cancel()
            stoppedForBattery = true
        }
        let reasons = rules.reasons(for: conditions)
        if reasons != ruleReasons {
            ruleReasons = reasons
        }
        updateAssertion()
    }

    // MARK: Assertion

    /// Holds one assertion of the right kind while awake; releases it otherwise.
    func updateAssertion() {
        let wantedKind: SleepAssertionKind? = isAwake
            ? (settings[PowerSettings.keepDisplayAwake] ? .display : .system)
            : nil
        guard assertion?.kind != wantedKind else { return }
        assertion?.release()
        assertion = nil
        if let wantedKind {
            assertion = power.preventSleep(wantedKind, reason: String(localized: "KKit: Keep Awake"))
        }
    }

    func shutdown() {
        expiryTask?.cancel()
        expiryTask = nil
        session = nil
        ruleReasons = []
        assertion?.release()
        assertion = nil
    }

    // MARK: Display

    /// "1h 20m", "On", or `nil` when not awake.
    func statusText(at date: Date) -> String? {
        if let remaining = session?.remaining(at: date) {
            return KKitDuration.short(remaining)
        }
        if session != nil {
            return String(localized: "On")
        }
        if !ruleReasons.isEmpty {
            return String(localized: "Auto")
        }
        return nil
    }
}

/// Local copy of the short duration format, so the controller doesn't need KKitUI.
enum KKitDuration {
    static func short(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600 + 59) / 60
        if hours > 0 {
            return minutes > 0 && minutes < 60 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return minutes > 0 ? "\(minutes)m" : "<1m"
    }
}
