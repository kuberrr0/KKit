import AudioToolbox
import CoreAudio
import Foundation

/// Small typed wrappers around the CoreAudio property API.
enum CA {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func has(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(object, &address)
    }

    static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(object, &address) else { return false }
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    static func uint32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    static func int32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Int32? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Int32 = 0
        var size = UInt32(MemoryLayout<Int32>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    static func float32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Float32? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    @discardableResult
    static func setUInt32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: UInt32) -> Bool {
        var address = address
        var value = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    @discardableResult
    static func setFloat32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: Float32) -> Bool {
        var address = address
        var value = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    static func string(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func objectIDs(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> [AudioObjectID] {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    static func hasStreams(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var streams = address(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == noErr && size > 0
    }

    // MARK: Devices

    static func allDeviceIDs() -> [AudioObjectID] {
        objectIDs(systemObject, address(kAudioHardwarePropertyDevices))
    }

    static func device(_ id: AudioObjectID) -> AudioDeviceRecord? {
        guard let uid = string(id, address(kAudioDevicePropertyDeviceUID)) else { return nil }
        let name = string(id, address(kAudioObjectPropertyName)) ?? uid
        let transport = uint32(id, address(kAudioDevicePropertyTransportType))
        return AudioDeviceRecord(
            id: id,
            uid: uid,
            name: name,
            hasOutput: hasStreams(id, scope: kAudioObjectPropertyScopeOutput),
            hasInput: hasStreams(id, scope: kAudioObjectPropertyScopeInput),
            isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn
        )
    }

    static func defaultDevice(input: Bool) -> AudioObjectID? {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        guard let id = uint32(systemObject, address(selector)), id != kAudioObjectUnknown else { return nil }
        return id
    }

    // MARK: Volume and mute

    /// The device's overall volume: the virtual main volume if it has one, otherwise the
    /// main element, otherwise the average of channels 1 and 2.
    static func volume(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Double? {
        if let value = float32(device, address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope)) {
            return Double(value)
        }
        if let value = float32(device, address(kAudioDevicePropertyVolumeScalar, scope: scope)) {
            return Double(value)
        }
        let channels = [UInt32(1), UInt32(2)].compactMap {
            float32(device, address(kAudioDevicePropertyVolumeScalar, scope: scope, element: $0))
        }
        guard !channels.isEmpty else { return nil }
        return Double(channels.reduce(0, +)) / Double(channels.count)
    }

    @discardableResult
    static func setVolume(_ volume: Double, device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        let value = Float32(min(max(volume, 0), 1))
        let main = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope)
        if isSettable(device, main), setFloat32(device, main, value) {
            return true
        }
        let element = address(kAudioDevicePropertyVolumeScalar, scope: scope)
        if isSettable(device, element), setFloat32(device, element, value) {
            return true
        }
        var any = false
        for channel in [UInt32(1), UInt32(2)] {
            let channelAddress = address(kAudioDevicePropertyVolumeScalar, scope: scope, element: channel)
            if isSettable(device, channelAddress), setFloat32(device, channelAddress, value) {
                any = true
            }
        }
        return any
    }

    static func muteAddress(scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        address(kAudioDevicePropertyMute, scope: scope)
    }

    static func canMute(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        isSettable(device, muteAddress(scope: scope))
    }

    static func isMuted(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool? {
        uint32(device, muteAddress(scope: scope)).map { $0 != 0 }
    }

    @discardableResult
    static func setMuted(_ muted: Bool, device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        setUInt32(device, muteAddress(scope: scope), muted ? 1 : 0)
    }

    static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        (uint32(device, address(kAudioDevicePropertyDeviceIsRunningSomewhere)) ?? 0) != 0
    }
}

struct AudioDeviceRecord: Sendable {
    var id: AudioObjectID
    var uid: String
    var name: String
    var hasOutput: Bool
    var hasInput: Bool
    var isBuiltIn: Bool
}

/// A CoreAudio property listener that can be removed again. Listeners run on the main
/// queue and call `handler` there.
@MainActor
final class CoreAudioListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock
    private var isInstalled = false

    init(object: AudioObjectID, address: AudioObjectPropertyAddress, handler: @escaping @MainActor () -> Void) {
        self.object = object
        self.address = address
        self.block = Self.makeBlock(handler)
        isInstalled = AudioObjectAddPropertyListenerBlock(object, &self.address, DispatchQueue.main, block) == noErr
    }

    func remove() {
        guard isInstalled else { return }
        AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        isInstalled = false
    }

    /// Built outside the main actor so the block itself has no actor isolation; it hops
    /// back with `assumeIsolated`, which is safe because CoreAudio calls it on the main queue.
    nonisolated private static func makeBlock(_ handler: @escaping @MainActor () -> Void) -> AudioObjectPropertyListenerBlock {
        let box = MainActorHandler(handler)
        return { _, _ in
            MainActor.assumeIsolated {
                box.handler()
            }
        }
    }
}

/// Carries a main-actor closure into a non-isolated callback.
final class MainActorHandler: @unchecked Sendable {
    let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }
}
