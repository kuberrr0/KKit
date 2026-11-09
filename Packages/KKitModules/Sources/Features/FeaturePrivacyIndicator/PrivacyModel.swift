import Foundation
import KKitServicesAPI
import Observation

/// What the Privacy Indicator shows: device usage, the input mute state, and the log.
@MainActor
@Observable
final class PrivacyModel {
    private(set) var usage: DeviceUsage = .idle
    private(set) var inputMuted = false
    private(set) var inputDeviceName: String?
    private(set) var log = UsageLog()

    /// Whether the log changed since it was last saved.
    @ObservationIgnored private(set) var logIsDirty = false

    init() {}

    func update(usage: DeviceUsage, keepLog: Bool, at date: Date) {
        self.usage = usage
        guard keepLog else { return }
        if log.record(usage, at: date) {
            log.prune(now: date)
            logIsDirty = true
        }
    }

    func update(audio: AudioState) {
        inputMuted = audio.inputMuted
        inputDeviceName = audio.defaultInput?.name
    }

    func loadLog(_ log: UsageLog) {
        self.log = log
    }

    func closeLog(at date: Date) {
        log.closeAll(at: date)
        logIsDirty = true
    }

    func clearLog() {
        log.clear()
        logIsDirty = true
    }

    func markSaved() {
        logIsDirty = false
    }

    /// What the compact Island shows, given the settings. `nil` = nothing to show.
    func indicator(showMic: Bool, showCamera: Bool, showAppNames: Bool) -> PrivacyIndicator? {
        let mic = showMic && usage.micInUse
        let camera = showCamera && usage.cameraInUse
        guard mic || camera else { return nil }
        let mutedMic = mic && inputMuted

        var symbols: [String] = []
        if mic { symbols.append(mutedMic ? "mic.slash.fill" : "mic.fill") }
        if camera { symbols.append("video.fill") }

        let label: String
        if mutedMic {
            label = String(localized: "Muted")
        } else if mic, showAppNames, let name = usage.micUsers.first?.name {
            label = usage.micUsers.count > 1 ? "\(name) +\(usage.micUsers.count - 1)" : name
        } else if mic && camera {
            label = String(localized: "Mic · Cam")
        } else if mic {
            label = String(localized: "Mic")
        } else {
            label = String(localized: "Camera")
        }
        return PrivacyIndicator(symbols: symbols, label: label, micInUse: mic, cameraInUse: camera, micMuted: mutedMic)
    }
}

/// The compact Island content.
struct PrivacyIndicator: Equatable {
    var symbols: [String]
    var label: String
    var micInUse: Bool
    var cameraInUse: Bool
    /// The red ear: an app is using the mic while it's muted.
    var micMuted: Bool
}
