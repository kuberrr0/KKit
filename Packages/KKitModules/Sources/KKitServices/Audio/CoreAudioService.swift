import AudioToolbox
import CoreAudio
import Foundation
import KKitCore
import KKitServicesAPI

/// Devices, default devices, volume and mute through CoreAudio. Volume and mute
/// changes from anywhere (keys, Control Centre, other apps) arrive through property
/// listeners, so nothing polls.
@MainActor
public final class CoreAudioService: AudioService {
    public private(set) var state = AudioState()

    private let broadcast = Broadcast<AudioState>()
    private var systemListeners: [CoreAudioListener] = []
    private var deviceListeners: [CoreAudioListener] = []
    private var listenedDevices: (output: AudioObjectID?, input: AudioObjectID?) = (nil, nil)
    /// Input volume saved by the "mute by volume 0" fallback, per device uid.
    private var savedInputVolumes: [String: Double] = [:]
    private var reloadScheduled = false
    private let mixer = ProcessTapMixer()
    private let log = KKitLog.logger("audio")

    public init() {
        reload()
        let system = CA.systemObject
        for selector in [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
        ] {
            systemListeners.append(CoreAudioListener(object: system, address: CA.address(selector)) { [weak self] in
                self?.scheduleReload()
            })
        }
        updateDeviceListeners()
    }

    public func updates() -> AsyncStream<AudioState> {
        broadcast.stream(initial: state)
    }

    public func setVolume(_ volume: Double, for scope: AudioScope) {
        guard let device = state.defaultDevice(for: scope) else { return }
        let caScope = Self.caScope(scope)
        if !CA.setVolume(volume, device: device.id, scope: caScope) {
            log.info("\(device.name, privacy: .public) has no settable volume")
        }
        // Raising the volume unmutes, as the volume keys do.
        if scope == .output, volume > 0, CA.isMuted(device.id, scope: caScope) == true {
            CA.setMuted(false, device: device.id, scope: caScope)
        }
        reload()
    }

    public func setMuted(_ muted: Bool, for scope: AudioScope) {
        guard let device = state.defaultDevice(for: scope) else { return }
        let caScope = Self.caScope(scope)
        if CA.canMute(device.id, scope: caScope) {
            CA.setMuted(muted, device: device.id, scope: caScope)
        } else if scope == .input {
            // No mute control: mute by setting the input volume to 0.
            if muted {
                if savedInputVolumes[device.uid] == nil {
                    savedInputVolumes[device.uid] = CA.volume(device.id, scope: caScope) ?? 1
                }
                CA.setVolume(0, device: device.id, scope: caScope)
            } else {
                let restored = savedInputVolumes.removeValue(forKey: device.uid) ?? 1
                CA.setVolume(restored, device: device.id, scope: caScope)
            }
        } else {
            log.info("\(device.name, privacy: .public) can't be muted")
        }
        reload()
    }

    public func setDefaultDevice(_ deviceID: UInt32, for scope: AudioScope) {
        let system = CA.systemObject
        switch scope {
        case .output:
            CA.setUInt32(system, CA.address(kAudioHardwarePropertyDefaultOutputDevice), deviceID)
            // Alerts and sound effects follow the output device.
            CA.setUInt32(system, CA.address(kAudioHardwarePropertyDefaultSystemOutputDevice), deviceID)
        case .input:
            CA.setUInt32(system, CA.address(kAudioHardwarePropertyDefaultInputDevice), deviceID)
        }
        reload()
    }

    // MARK: Per-app volume

    public func audioApps() -> [AudioApp] {
        mixer.apps()
    }

    public func appVolume(for bundleID: String) -> Double {
        mixer.volume(for: bundleID)
    }

    public func setAppVolume(_ volume: Double, for bundleID: String) {
        mixer.setVolume(volume, for: bundleID)
    }

    // MARK: Private

    private static func caScope(_ scope: AudioScope) -> AudioObjectPropertyScope {
        scope == .output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
    }

    /// Listener callbacks often come in bursts; coalesce them into one reload.
    private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.reloadScheduled = false
            self.reload()
        }
    }

    private func reload() {
        let devices = CA.allDeviceIDs().compactMap(CA.device)
            // The per-app volume mixer's own aggregate devices.
            .filter { $0.name != ProcessTapMixer.aggregateName }
            .map {
                AudioDevice(id: $0.id, uid: $0.uid, name: $0.name, hasOutput: $0.hasOutput, hasInput: $0.hasInput, isBuiltIn: $0.isBuiltIn)
            }
        let outputID = CA.defaultDevice(input: false)
        let inputID = CA.defaultDevice(input: true)
        let output = devices.first { $0.id == outputID }
        let input = devices.first { $0.id == inputID }

        var updated = AudioState(devices: devices, defaultOutput: output, defaultInput: input)
        if let output {
            updated.outputVolume = CA.volume(output.id, scope: kAudioObjectPropertyScopeOutput)
            updated.outputMuted = CA.isMuted(output.id, scope: kAudioObjectPropertyScopeOutput) ?? false
        }
        if let input {
            let volume = CA.volume(input.id, scope: kAudioObjectPropertyScopeInput)
            updated.inputVolume = volume
            if let muted = CA.isMuted(input.id, scope: kAudioObjectPropertyScopeInput),
               CA.canMute(input.id, scope: kAudioObjectPropertyScopeInput) {
                updated.inputMuted = muted
            } else {
                updated.inputMuted = savedInputVolumes[input.uid] != nil && (volume ?? 0) == 0
            }
        }

        if updated != state {
            state = updated
            broadcast.send(updated)
        }
        mixer.outputDeviceChanged(uid: output?.uid)
        updateDeviceListeners()
    }

    /// Volume and mute listeners follow the current default devices.
    private func updateDeviceListeners() {
        let output = state.defaultOutput?.id
        let input = state.defaultInput?.id
        guard output != listenedDevices.output || input != listenedDevices.input || deviceListeners.isEmpty else { return }
        deviceListeners.forEach { $0.remove() }
        deviceListeners = []
        listenedDevices = (output, input)

        func listen(_ device: AudioObjectID?, scope: AudioObjectPropertyScope) {
            guard let device else { return }
            var addresses = [
                CA.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope),
                CA.address(kAudioDevicePropertyVolumeScalar, scope: scope),
                CA.address(kAudioDevicePropertyMute, scope: scope),
            ]
            for channel in [UInt32(1), UInt32(2)] {
                addresses.append(CA.address(kAudioDevicePropertyVolumeScalar, scope: scope, element: channel))
            }
            for address in addresses where CA.has(device, address) {
                deviceListeners.append(CoreAudioListener(object: device, address: address) { [weak self] in
                    self?.scheduleReload()
                })
            }
        }
        listen(output, scope: kAudioObjectPropertyScopeOutput)
        listen(input, scope: kAudioObjectPropertyScopeInput)
    }
}
