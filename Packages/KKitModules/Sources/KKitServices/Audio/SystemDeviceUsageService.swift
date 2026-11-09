import AppKit
import CoreAudio
import CoreMediaIO
import Foundation
import KKitCore
import KKitServicesAPI

/// Microphone and camera use, from CoreAudio's "is running somewhere" property on
/// every input device, CoreMediaIO's equivalent for cameras, and (macOS 14+) the audio
/// process objects for which apps are capturing. Listeners only exist while someone
/// subscribes.
@MainActor
public final class SystemDeviceUsageService: DeviceUsageService {
    public private(set) var usage = DeviceUsage.idle

    private let broadcast = Broadcast<DeviceUsage>()
    private var audioListeners: [CoreAudioListener] = []
    private var cameraListeners: [CoreMediaIOListener] = []
    /// While the mic is in use, re-check which apps use it (a second app joining
    /// doesn't change the device state).
    private var usersPoll: Task<Void, Never>?

    public init() {
        broadcast.onFirstSubscriber = { [weak self] in self?.startListening() }
        broadcast.onLastSubscriberGone = { [weak self] in self?.stopListening() }
    }

    public func updates() -> AsyncStream<DeviceUsage> {
        if !broadcast.hasSubscribers {
            usage = Self.currentUsage()
        }
        return broadcast.stream(initial: usage)
    }

    // MARK: Private

    private func startListening() {
        installAudioListeners()
        installCameraListeners()
        refresh()
    }

    private func stopListening() {
        audioListeners.forEach { $0.remove() }
        audioListeners = []
        cameraListeners.forEach { $0.remove() }
        cameraListeners = []
        usersPoll?.cancel()
        usersPoll = nil
    }

    private func installAudioListeners() {
        audioListeners.forEach { $0.remove() }
        audioListeners = []
        let system = CA.systemObject
        audioListeners.append(CoreAudioListener(object: system, address: CA.address(kAudioHardwarePropertyDevices)) { [weak self] in
            self?.installAudioListeners()
            self?.refresh()
        })
        audioListeners.append(CoreAudioListener(object: system, address: CA.address(kAudioHardwarePropertyProcessObjectList)) { [weak self] in
            self?.refresh()
        })
        for device in Self.inputDeviceIDs() {
            audioListeners.append(CoreAudioListener(object: device, address: CA.address(kAudioDevicePropertyDeviceIsRunningSomewhere)) { [weak self] in
                self?.refresh()
            })
        }
    }

    private func installCameraListeners() {
        cameraListeners.forEach { $0.remove() }
        cameraListeners = []
        cameraListeners.append(CoreMediaIOListener(object: CMIO.systemObject, selector: CMIO.devicesSelector) { [weak self] in
            self?.installCameraListeners()
            self?.refresh()
        })
        for camera in CMIO.deviceIDs() {
            cameraListeners.append(CoreMediaIOListener(object: camera, selector: CMIO.runningSomewhereSelector) { [weak self] in
                self?.refresh()
            })
        }
    }

    private func refresh() {
        let updated = Self.currentUsage()
        if updated != usage {
            usage = updated
            broadcast.send(updated)
        }
        if updated.micInUse, usersPoll == nil, broadcast.hasSubscribers {
            usersPoll = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled, let self else { return }
                    self.refresh()
                }
            }
        } else if !updated.micInUse {
            usersPoll?.cancel()
            usersPoll = nil
        }
    }

    private static func inputDeviceIDs() -> [AudioObjectID] {
        CA.allDeviceIDs().filter { CA.hasStreams($0, scope: kAudioObjectPropertyScopeInput) }
    }

    private static func currentUsage() -> DeviceUsage {
        let micInUse = inputDeviceIDs().contains { CA.isRunningSomewhere($0) }
        let cameraInUse = CMIO.deviceIDs().contains { CMIO.isRunningSomewhere($0) }
        return DeviceUsage(micInUse: micInUse, cameraInUse: cameraInUse, micUsers: micInUse ? micUsers() : [])
    }

    /// Apps whose audio process object says they're capturing input.
    private static func micUsers() -> [DeviceUser] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let processes = CA.objectIDs(CA.systemObject, CA.address(kAudioHardwarePropertyProcessObjectList))
        var users: [DeviceUser] = []
        for process in processes {
            guard (CA.uint32(process, CA.address(kAudioProcessPropertyIsRunningInput)) ?? 0) != 0,
                  let pid = CA.int32(process, CA.address(kAudioProcessPropertyPID)),
                  pid != ownPID
            else { continue }
            let bundleID = CA.string(process, CA.address(kAudioProcessPropertyBundleID))
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName ?? bundleID ?? "PID \(pid)"
            users.append(DeviceUser(pid: pid, name: name, bundleID: bundleID ?? app?.bundleIdentifier))
        }
        return users.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Typed wrappers around the CoreMediaIO property API, for cameras.
enum CMIO {
    static let systemObject = CMIOObjectID(kCMIOObjectSystemObject)
    static let devicesSelector = CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices)
    static let runningSomewhereSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)

    static func address(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    static func deviceIDs() -> [CMIOObjectID] {
        var devices = address(devicesSelector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(systemObject, &devices, 0, nil, &size) == 0, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(systemObject, &devices, 0, nil, size, &used, &ids) == 0 else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    static func isRunningSomewhere(_ device: CMIOObjectID) -> Bool {
        var running = address(runningSomewhereSelector)
        guard CMIOObjectHasProperty(device, &running) else { return false }
        var value: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
        return status == 0 && value != 0
    }
}

/// A CoreMediaIO property listener on the main queue.
@MainActor
final class CoreMediaIOListener {
    private let object: CMIOObjectID
    private var address: CMIOObjectPropertyAddress
    private let block: CMIOObjectPropertyListenerBlock
    private var isInstalled = false

    init(object: CMIOObjectID, selector: CMIOObjectPropertySelector, handler: @escaping @MainActor () -> Void) {
        self.object = object
        self.address = CMIO.address(selector)
        self.block = Self.makeBlock(handler)
        isInstalled = CMIOObjectAddPropertyListenerBlock(object, &self.address, DispatchQueue.main, block) == 0
    }

    func remove() {
        guard isInstalled else { return }
        CMIOObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        isInstalled = false
    }

    nonisolated private static func makeBlock(_ handler: @escaping @MainActor () -> Void) -> CMIOObjectPropertyListenerBlock {
        let box = MainActorHandler(handler)
        return { _, _ in
            MainActor.assumeIsolated {
                box.handler()
            }
        }
    }
}
