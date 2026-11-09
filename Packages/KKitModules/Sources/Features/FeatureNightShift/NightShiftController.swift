import Foundation
import KKitCore
import KKitServicesAPI
import Observation

/// Decides whether the tint is on (manual switch, schedule, pause, excluded apps),
/// fades it in and out, and applies it to each display through `DisplayService`.
@MainActor
@Observable
final class NightShiftController {
    /// A manual toggle while a schedule runs; lasts until the schedule's next change.
    struct Override: Equatable {
        var isOn: Bool
        var until: Date?
    }

    private(set) var override: Override?
    private(set) var pausedUntil: Date?
    private(set) var frontmostBundleID: String?
    /// 0…1: how far the tint is faded in right now.
    private(set) var strength: Double = 0

    private let display: any DisplayService
    private let settings: FeatureSettings
    private let now: () -> Date
    @ObservationIgnored private var fadeTask: Task<Void, Never>?
    @ObservationIgnored private var appliedStrength: Double = -1

    init(display: any DisplayService, settings: FeatureSettings, now: @escaping () -> Date = { Date() }) {
        self.display = display
        self.settings = settings
        self.now = now
    }

    var schedule: NightShiftSchedule {
        NightShiftSchedule(
            kind: settings[NightShiftSettings.schedule],
            startMinutes: settings[NightShiftSettings.customStart],
            endMinutes: settings[NightShiftSettings.customEnd],
            coordinate: settings[NightShiftSettings.coordinate]
        )
    }

    /// The user's (or schedule's) choice, before pauses and excluded apps.
    var isOn: Bool {
        let date = now()
        if let scheduled = schedule.isActive(at: date) {
            if let override, override.until.map({ date < $0 }) ?? true {
                return override.isOn
            }
            return scheduled
        }
        return settings[NightShiftSettings.isOn]
    }

    var isPaused: Bool {
        guard let pausedUntil else { return false }
        return now() < pausedUntil
    }

    var isSuppressedByApp: Bool {
        guard let frontmostBundleID else { return false }
        return settings[NightShiftSettings.disabledApps].contains(frontmostBundleID)
    }

    /// Whether the tint should be showing right now.
    var isActive: Bool { isOn && !isPaused && !isSuppressedByApp }

    var settingsIntensity: Double { settings[NightShiftSettings.intensity] }

    var target: ColorAdjustment {
        NightShiftColor.adjustment(
            mode: settings[NightShiftSettings.mode],
            intensity: settings[NightShiftSettings.intensity],
            extraDim: settings[NightShiftSettings.extraDim]
        )
    }

    // MARK: Actions

    func setOn(_ on: Bool) {
        let date = now()
        pausedUntil = nil
        if schedule.isActive(at: date) != nil {
            override = Override(isOn: on, until: schedule.nextChange(after: date))
        } else {
            settings[NightShiftSettings.isOn] = on
        }
        update(animated: true)
    }

    func toggle() {
        setOn(!isActive)
    }

    func setIntensity(_ value: Double) {
        settings[NightShiftSettings.intensity] = min(max(value, 0), 2)
        if !isActive {
            setOn(true)
        } else {
            apply(force: true)
        }
    }

    func adjustIntensity(by delta: Double) {
        setIntensity(settings[NightShiftSettings.intensity] + delta)
    }

    func pause(for seconds: TimeInterval) {
        pausedUntil = now().addingTimeInterval(seconds)
        update(animated: true)
    }

    func resume() {
        pausedUntil = nil
        update(animated: true)
    }

    func frontmostAppChanged(_ bundleID: String?) {
        frontmostBundleID = bundleID
        update(animated: true)
    }

    /// Re-evaluates the schedule and pause, e.g. once a minute.
    func tick() {
        let date = now()
        if let until = override?.until, date >= until {
            override = nil
        }
        if let pausedUntil, date >= pausedUntil {
            self.pausedUntil = nil
        }
        update(animated: true)
    }

    /// When the next `tick` is due.
    func nextTickDelay() -> TimeInterval {
        let date = now()
        var candidates: [Date] = [date.addingTimeInterval(60)]
        if let change = schedule.nextChange(after: date) { candidates.append(change) }
        if let pausedUntil { candidates.append(pausedUntil) }
        if let until = override?.until { candidates.append(until) }
        let next = candidates.min() ?? date.addingTimeInterval(60)
        return max(1, next.timeIntervalSince(date) + 0.5)
    }

    // MARK: Applying

    /// Fades (or jumps) to the current target.
    func update(animated: Bool) {
        let goal: Double = isActive ? 1 : 0
        fadeTask?.cancel()
        let duration = settings[NightShiftSettings.transitionSeconds]
        guard animated, duration > 0, goal != strength else {
            strength = goal
            apply()
            return
        }
        let start = strength
        let steps = max(1, Int(duration * 30))
        fadeTask = Task { [weak self] in
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(Int(duration * 1000) / steps))
                guard !Task.isCancelled, let self else { return }
                let t = Double(step) / Double(steps)
                // Ease in-out.
                let eased = t * t * (3 - 2 * t)
                self.strength = start + (goal - start) * eased
                self.apply(force: true)
            }
        }
    }

    /// Writes gamma tables for every display.
    func apply(force: Bool = false) {
        guard force || appliedStrength != strength else { return }
        appliedStrength = strength
        let adjustment = NightShiftColor.blend(target, progress: strength)
        let disabled = Set(settings[NightShiftSettings.disabledDisplays])
        for info in display.displays {
            display.setColorAdjustment(disabled.contains(info.stableID) ? .identity : adjustment, for: info.id)
        }
    }

    func shutdown() {
        fadeTask?.cancel()
        fadeTask = nil
        strength = 0
        appliedStrength = -1
        display.resetColorAdjustments()
    }
}
