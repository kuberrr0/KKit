import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import Observation

/// Volume, mute and device switching on top of `AudioService`, with the volume limit,
/// step size, HUDs and auto-switching from settings.
@MainActor
@Observable
final class VolumeController {
    private(set) var state: AudioState

    private let audio: any AudioService
    private let settings: FeatureSettings
    private let now: () -> Date

    /// Shows an Island HUD. Set by the feature while it runs.
    @ObservationIgnored var onHUD: (@MainActor (IslandHUD) -> Void)?
    @ObservationIgnored private var scroll = ScrollAccumulator()
    @ObservationIgnored private var knownDeviceUIDs: Set<String>?
    /// Changes KKit itself makes arrive back as updates; don't show the
    /// "system change" HUD for them.
    @ObservationIgnored private var ownChangeUntil = Date.distantPast

    init(audio: any AudioService, settings: FeatureSettings, now: @escaping () -> Date = { Date() }) {
        self.audio = audio
        self.settings = settings
        self.now = now
        self.state = audio.state
    }

    var limit: Double { min(max(settings[VolumeSettings.volumeLimit], 0.1), 1) }
    var step: Double { min(max(settings[VolumeSettings.step], 0.01), 0.25) }

    /// The output volume as the user perceives it: 0 while muted.
    var effectiveOutputVolume: Double? {
        state.outputVolume.map { state.outputMuted ? 0 : $0 }
    }

    // MARK: Changing things

    enum Source {
        /// A command or a scroll on the Island: shows the HUD.
        case command
        /// The menu slider: the slider is the feedback.
        case slider
    }

    func setVolume(_ volume: Double, source: Source = .command) {
        guard state.outputVolume != nil else { return }
        let target = VolumeMath.clamp(volume, limit: limit)
        markOwnChange()
        audio.setVolume(target, for: .output)
        if target > 0, state.outputMuted {
            audio.setMuted(false, for: .output)
        }
        refresh()
        if source == .command {
            showVolumeHUD()
        }
    }

    /// `fromKey`: a volume key, so the HUD shows even with "Show HUD" off, since KKit
    /// replaced macOS's.
    func stepVolume(up: Bool, fine: Bool = false, fromKey: Bool = false) {
        guard let current = effectiveOutputVolume else {
            showNoVolumeControlHUD()
            return
        }
        setVolume(VolumeMath.stepped(current, step: step, up: up, fine: fine, limit: limit), source: .slider)
        showVolumeHUD(force: fromKey)
    }

    func toggleMute() {
        markOwnChange()
        audio.setMuted(!state.outputMuted, for: .output)
        refresh()
        showVolumeHUD()
    }

    var isMicMuted: Bool { state.inputMuted }

    func setMicMuted(_ muted: Bool) {
        guard state.defaultInput != nil else { return }
        markOwnChange()
        audio.setMuted(muted, for: .input)
        refresh()
        if settings[VolumeSettings.soundOnMicMute] {
            NSSound(named: muted ? "Pop" : "Tink")?.play()
        }
        guard settings[VolumeSettings.showHUD] else { return }
        onHUD?(IslandHUD(
            id: "mic",
            symbol: muted ? "mic.slash.fill" : "mic.fill",
            title: muted ? String(localized: "Microphone muted") : String(localized: "Microphone on"),
            detail: state.defaultInput?.name,
            tint: muted ? .critical : .normal
        ))
    }

    func toggleMicMute() {
        setMicMuted(!state.inputMuted)
    }

    // MARK: Per-app volume

    func audioApps() -> [AudioApp] {
        audio.audioApps()
    }

    func appVolume(for bundleID: String) -> Double {
        settings[VolumeSettings.appVolumes][bundleID] ?? 1
    }

    /// Sets and remembers an app's volume.
    func setAppVolume(_ volume: Double, for bundleID: String) {
        let clamped = min(max(volume, 0), 1)
        if clamped >= 0.995 {
            settings[VolumeSettings.appVolumes][bundleID] = nil
            audio.setAppVolume(1, for: bundleID)
        } else {
            settings[VolumeSettings.appVolumes][bundleID] = clamped
            audio.setAppVolume(clamped, for: bundleID)
        }
    }

    /// Puts back the remembered volumes, at start.
    func applySavedAppVolumes() {
        for (bundleID, volume) in settings[VolumeSettings.appVolumes] where volume < 1 {
            audio.setAppVolume(volume, for: bundleID)
        }
    }

    /// Every app back to full volume, at stop. The remembered volumes stay.
    func releaseAppVolumes() {
        for bundleID in settings[VolumeSettings.appVolumes].keys {
            audio.setAppVolume(1, for: bundleID)
        }
    }

    // MARK: Keys

    /// A volume media key. Returns whether it was used.
    func handleMediaKey(_ media: MediaKeyEvent, modifiers: Shortcut.Modifiers) -> Bool {
        switch VolumeKeyAction.action(for: media, modifiers: modifiers) {
        case .step(let up, let fine):
            stepVolume(up: up, fine: fine, fromKey: true)
            return true
        case .toggleMute:
            markOwnChange()
            audio.setMuted(!state.outputMuted, for: .output)
            refresh()
            showVolumeHUD(force: true)
            return true
        case .swallow:
            return true
        case .pass:
            return false
        }
    }

    /// Push-to-talk and push-to-mute: the mic follows the key, quietly (no HUD for every
    /// press; the Island's mic indicator shows it).
    func setMicMutedByKey(_ muted: Bool) {
        guard state.defaultInput != nil, state.inputMuted != muted else { return }
        markOwnChange()
        audio.setMuted(muted, for: .input)
        refresh()
        if settings[VolumeSettings.soundOnMicMute] {
            NSSound(named: muted ? "Pop" : "Tink")?.play()
        }
    }

    func setDefault(_ device: AudioDevice, for scope: AudioScope) {
        markOwnChange()
        audio.setDefaultDevice(device.id, for: scope)
        refresh()
        guard settings[VolumeSettings.showHUD] else { return }
        onHUD?(IslandHUD(
            id: scope == .output ? "output" : "input",
            symbol: scope == .output ? "hifispeaker.fill" : "mic.fill",
            title: device.name,
            tint: .accent
        ))
    }

    func nextOutput() {
        guard let device = AudioDevicePicker.next(after: state.defaultOutput, in: state.outputDevices) else { return }
        setDefault(device, for: .output)
    }

    func handleScroll(_ event: IslandScrollEvent) {
        let steps = scroll.steps(for: event)
        guard steps != 0, let current = effectiveOutputVolume else { return }
        var volume = current
        for _ in 0..<abs(steps) {
            volume = VolumeMath.stepped(volume, step: step, up: steps > 0, fine: event.isFine, limit: limit)
        }
        setVolume(volume)
    }

    // MARK: Updates from CoreAudio

    func receive(_ newState: AudioState) {
        let old = state
        state = newState

        // Volume limit: pull back changes made with the volume keys.
        if let volume = newState.outputVolume, volume > limit + 0.001 {
            markOwnChange()
            audio.setVolume(limit, for: .output)
            refresh()
        }

        let changed = old.outputVolume != state.outputVolume || old.outputMuted != state.outputMuted
        if changed, now() > ownChangeUntil, settings[VolumeSettings.hudForSystemChanges] {
            showVolumeHUD(force: true)
        }

        autoSwitchIfNeeded()
    }

    /// When a device appears or disappears, switch to the most-preferred connected one.
    func autoSwitchIfNeeded() {
        let uids = Set(state.devices.map(\.uid))
        defer { knownDeviceUIDs = uids }
        guard let known = knownDeviceUIDs, known != uids else { return }
        if settings[VolumeSettings.autoSwitchOutput],
           let device = AudioDevicePicker.preferred(in: state.outputDevices, priority: settings[VolumeSettings.outputPriority]),
           device.uid != state.defaultOutput?.uid {
            setDefault(device, for: .output)
        }
        if settings[VolumeSettings.autoSwitchInput],
           let device = AudioDevicePicker.preferred(in: state.inputDevices, priority: settings[VolumeSettings.inputPriority]),
           device.uid != state.defaultInput?.uid {
            setDefault(device, for: .input)
        }
    }

    // MARK: Private

    private func refresh() {
        state = audio.state
    }

    private func markOwnChange() {
        ownChangeUntil = now().addingTimeInterval(0.5)
    }

    private func showVolumeHUD(force: Bool = false) {
        guard force || settings[VolumeSettings.showHUD] else { return }
        let volume = effectiveOutputVolume
        onHUD?(IslandHUD(
            id: "volume",
            symbol: VolumeMath.speakerSymbol(volume: state.outputVolume, muted: state.outputMuted),
            title: state.defaultOutput?.name,
            level: volume ?? 0,
            detail: state.outputMuted ? String(localized: "Muted") : volume.map(KKFormat.percent)
        ))
    }

    private func showNoVolumeControlHUD() {
        onHUD?(IslandHUD(
            id: "volume",
            symbol: "speaker.badge.exclamationmark.fill",
            title: String(localized: "No volume control"),
            detail: state.defaultOutput?.name,
            tint: .warning
        ))
    }
}

