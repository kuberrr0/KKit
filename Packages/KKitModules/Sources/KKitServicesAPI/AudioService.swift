import Foundation

/// An audio device as CoreAudio reports it.
public struct AudioDevice: Identifiable, Hashable, Sendable {
    /// `AudioObjectID`. Changes between launches and reconnects; use `uid` to remember a device.
    public var id: UInt32
    /// Stable across launches.
    public var uid: String
    public var name: String
    public var hasOutput: Bool
    public var hasInput: Bool
    public var isBuiltIn: Bool

    public init(id: UInt32, uid: String, name: String, hasOutput: Bool, hasInput: Bool, isBuiltIn: Bool = false) {
        self.id = id
        self.uid = uid
        self.name = name
        self.hasOutput = hasOutput
        self.hasInput = hasInput
        self.isBuiltIn = isBuiltIn
    }
}

public enum AudioScope: Sendable, Hashable {
    case output
    case input
}

/// The audio state KKit cares about: devices, defaults, volume and mute.
public struct AudioState: Sendable, Equatable {
    public var devices: [AudioDevice]
    public var defaultOutput: AudioDevice?
    public var defaultInput: AudioDevice?
    /// 0…1; `nil` when the device has no software volume (e.g. some HDMI outputs).
    public var outputVolume: Double?
    public var outputMuted: Bool
    public var inputVolume: Double?
    public var inputMuted: Bool

    public init(
        devices: [AudioDevice] = [],
        defaultOutput: AudioDevice? = nil,
        defaultInput: AudioDevice? = nil,
        outputVolume: Double? = nil,
        outputMuted: Bool = false,
        inputVolume: Double? = nil,
        inputMuted: Bool = false
    ) {
        self.devices = devices
        self.defaultOutput = defaultOutput
        self.defaultInput = defaultInput
        self.outputVolume = outputVolume
        self.outputMuted = outputMuted
        self.inputVolume = inputVolume
        self.inputMuted = inputMuted
    }

    public var outputDevices: [AudioDevice] { devices.filter(\.hasOutput) }
    public var inputDevices: [AudioDevice] { devices.filter(\.hasInput) }

    public func volume(for scope: AudioScope) -> Double? {
        scope == .output ? outputVolume : inputVolume
    }

    public func isMuted(_ scope: AudioScope) -> Bool {
        scope == .output ? outputMuted : inputMuted
    }

    public func defaultDevice(for scope: AudioScope) -> AudioDevice? {
        scope == .output ? defaultOutput : defaultInput
    }
}

/// Devices, default output/input, volume and mute (CoreAudio).
///
/// Per-app volume (process taps) arrives with M4.
@MainActor
public protocol AudioService: AnyObject {
    var state: AudioState { get }
    /// The current state, then every change (volume keys, device plugged in…).
    func updates() -> AsyncStream<AudioState>
    func setVolume(_ volume: Double, for scope: AudioScope)
    /// Input devices without a mute control are "muted" by setting their volume to 0
    /// and restoring it afterwards.
    func setMuted(_ muted: Bool, for scope: AudioScope)
    func setDefaultDevice(_ deviceID: UInt32, for scope: AudioScope)
}
