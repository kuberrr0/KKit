import Foundation
import KKitCore
import KKitServicesAPI
import SwiftUI

/// Records what features put in the Island.
@MainActor
public final class FakeIslandService: IslandService {
    @MainActor
    public final class Handle: IslandHandle {
        public private(set) var activity: IslandActivity
        public let owner: FeatureID
        public private(set) var isActive = true
        public var isExpanded = false
        weak var service: FakeIslandService?

        init(activity: IslandActivity, owner: FeatureID, service: FakeIslandService) {
            self.activity = activity
            self.owner = owner
            self.service = service
        }

        public func update(_ activity: IslandActivity) {
            guard isActive else { return }
            self.activity = activity
        }

        public func dismiss() {
            isActive = false
            service?.handles.removeAll { $0 === self }
        }
    }

    public private(set) var handles: [Handle] = []
    public private(set) var huds: [IslandHUD] = []
    public private(set) var scrollHandlers: [FeatureID: @MainActor (IslandScrollEvent) -> Void] = [:]
    public private(set) var expansions: [(owner: FeatureID, page: String?, activity: String?)] = []

    public init() {}

    /// Live activities' ids.
    public var activityIDs: [String] { handles.map(\.activity.id) }

    public func activity(_ id: String) -> IslandActivity? {
        handles.first { $0.activity.id == id }?.activity
    }

    @discardableResult
    public func present(_ activity: IslandActivity, owner: FeatureID) -> any IslandHandle {
        handles.filter { $0.owner == owner && $0.activity.id == activity.id }.forEach { $0.dismiss() }
        let handle = Handle(activity: activity, owner: owner, service: self)
        handles.append(handle)
        return handle
    }

    public func showHUD(_ hud: IslandHUD, owner: FeatureID) {
        huds.append(hud)
    }

    public func dismissAll(owner: FeatureID) {
        handles.filter { $0.owner == owner }.forEach { $0.dismiss() }
    }

    public func setScrollHandler(_ handler: (@MainActor (IslandScrollEvent) -> Void)?, owner: FeatureID) {
        scrollHandlers[owner] = handler
    }

    public func expand(page: String?, activityID: String?, owner: FeatureID) {
        expansions.append((owner, page, activityID))
    }

    /// Simulates scrolling over the Island.
    public func scroll(_ event: IslandScrollEvent) {
        scrollHandlers.values.first?(event)
    }
}

/// Audio state you set by hand.
@MainActor
public final class FakeAudioService: AudioService {
    public var state: AudioState {
        didSet { broadcast.send(state) }
    }

    private let broadcast = Broadcast<AudioState>()

    public init(state: AudioState = FakeAudioService.sampleState) {
        self.state = state
    }

    public static let speakers = AudioDevice(id: 1, uid: "speakers", name: "MacBook Pro Speakers", hasOutput: true, hasInput: false, isBuiltIn: true)
    public static let microphone = AudioDevice(id: 2, uid: "mic", name: "MacBook Pro Microphone", hasOutput: false, hasInput: true, isBuiltIn: true)
    public static let airPods = AudioDevice(id: 3, uid: "airpods", name: "AirPods Pro", hasOutput: true, hasInput: true)

    public static let sampleState = AudioState(
        devices: [speakers, microphone],
        defaultOutput: speakers,
        defaultInput: microphone,
        outputVolume: 0.5,
        outputMuted: false,
        inputVolume: 0.8,
        inputMuted: false
    )

    public func updates() -> AsyncStream<AudioState> {
        broadcast.stream(initial: state)
    }

    public func setVolume(_ volume: Double, for scope: AudioScope) {
        let clamped = min(max(volume, 0), 1)
        switch scope {
        case .output:
            state.outputVolume = clamped
            if clamped > 0 { state.outputMuted = false }
        case .input:
            state.inputVolume = clamped
        }
    }

    public func setMuted(_ muted: Bool, for scope: AudioScope) {
        switch scope {
        case .output: state.outputMuted = muted
        case .input: state.inputMuted = muted
        }
    }

    public func setDefaultDevice(_ deviceID: UInt32, for scope: AudioScope) {
        guard let device = state.devices.first(where: { $0.id == deviceID }) else { return }
        switch scope {
        case .output: state.defaultOutput = device
        case .input: state.defaultInput = device
        }
    }

    public var apps: [AudioApp] = []
    public private(set) var appVolumes: [String: Double] = [:]

    public func audioApps() -> [AudioApp] { apps }

    public func appVolume(for bundleID: String) -> Double {
        appVolumes[bundleID] ?? 1
    }

    public func setAppVolume(_ volume: Double, for bundleID: String) {
        appVolumes[bundleID] = volume >= 0.999 ? nil : min(max(volume, 0), 1)
    }
}

@MainActor
public final class FakeDeviceUsageService: DeviceUsageService {
    public var usage: DeviceUsage {
        didSet { broadcast.send(usage) }
    }

    private let broadcast = Broadcast<DeviceUsage>()

    public init(usage: DeviceUsage = .idle) {
        self.usage = usage
    }

    public var subscriberCount: Int { broadcast.subscriberCount }

    public func updates() -> AsyncStream<DeviceUsage> {
        broadcast.stream(initial: usage)
    }
}

@MainActor
public final class FakePowerService: PowerService {
    @MainActor
    public final class Assertion: SleepAssertion {
        public let kind: SleepAssertionKind
        public private(set) var isReleased = false

        init(kind: SleepAssertionKind) {
            self.kind = kind
        }

        public func release() {
            isReleased = true
        }
    }

    public var powerSource: PowerSourceInfo {
        didSet { broadcast.send(powerSource) }
    }

    public private(set) var assertions: [Assertion] = []
    public var health: BatteryHealth?
    private let broadcast = Broadcast<PowerSourceInfo>()

    public init(powerSource: PowerSourceInfo = PowerSourceInfo(hasBattery: true, isOnAC: false, batteryLevel: 0.8)) {
        self.powerSource = powerSource
    }

    /// Assertions not yet released.
    public var heldAssertions: [Assertion] { assertions.filter { !$0.isReleased } }

    public func preventSleep(_ kind: SleepAssertionKind, reason: String) -> (any SleepAssertion)? {
        let assertion = Assertion(kind: kind)
        assertions.append(assertion)
        return assertion
    }

    public func powerSourceUpdates() -> AsyncStream<PowerSourceInfo> {
        broadcast.stream(initial: powerSource)
    }

    public func batteryHealth() async -> BatteryHealth? {
        health
    }
}

@MainActor
public final class FakeDisplayService: DisplayService {
    public var displays: [DisplayInfo] = [
        DisplayInfo(id: 1, stableID: "builtin", name: "Built-in Retina Display", isBuiltIn: true),
    ]
    public private(set) var adjustments: [UInt32: ColorAdjustment] = [:]

    public init() {}

    public func setColorAdjustment(_ adjustment: ColorAdjustment, for displayID: UInt32) {
        adjustments[displayID] = adjustment.isIdentity ? nil : adjustment
    }

    public func resetColorAdjustments() {
        adjustments.removeAll()
    }

    /// Displays KKit can set the brightness of, and their level.
    public var brightnessLevels: [UInt32: Double] = [1: 0.5]

    public func brightness(of displayID: UInt32) -> Double? {
        brightnessLevels[displayID]
    }

    public func setBrightness(_ brightness: Double, for displayID: UInt32) {
        guard brightnessLevels[displayID] != nil else { return }
        brightnessLevels[displayID] = min(max(brightness, 0), 1)
    }
}

@MainActor
public final class FakeSystemInfoService: SystemInfoService {
    private let broadcast = Broadcast<SystemSample>()

    public init() {}

    public var subscriberCount: Int { broadcast.subscriberCount }

    public func samples(every interval: Duration, includeProcesses: Bool) -> AsyncStream<SystemSample> {
        broadcast.stream()
    }

    public func send(_ sample: SystemSample) {
        broadcast.send(sample)
    }

    public let pressure = Broadcast<MemoryPressure>()

    public func memoryPressureUpdates() -> AsyncStream<MemoryPressure> {
        pressure.stream(initial: .normal)
    }
}

@MainActor
public final class FakeNotificationService: NotificationService {
    public private(set) var delivered: [(id: String, title: String, body: String?)] = []

    public init() {}

    public func deliver(id: String, title: String, body: String?) {
        delivered.append((id, title, body))
    }
}

@MainActor
public final class FakeSystemActionsService: SystemActionsService {
    public var isDarkMode = false
    public var isDockAutohide = false
    public var isMenuBarAutohide = false
    public var showsHiddenFiles = false
    public var isWiFiOn: Bool? = true
    public private(set) var actions: [String] = []
    public var failure: SystemActionError?

    public init() {}

    private func record(_ action: String) throws {
        if let failure { throw failure }
        actions.append(action)
    }

    public func setDarkMode(_ on: Bool) async throws { try record("darkMode=\(on)"); isDarkMode = on }
    public func setDockAutohide(_ on: Bool) async throws { try record("dockAutohide=\(on)"); isDockAutohide = on }
    public func setMenuBarAutohide(_ on: Bool) async throws { try record("menuBarAutohide=\(on)"); isMenuBarAutohide = on }
    public func setShowsHiddenFiles(_ on: Bool) async throws { try record("hiddenFiles=\(on)"); showsHiddenFiles = on }
    public func setWiFi(_ on: Bool) async throws { try record("wifi=\(on)"); isWiFiOn = on }
    public func ejectAllDisks() async throws -> Int { try record("eject"); return 0 }
    public func emptyTrash() async throws { try record("emptyTrash") }
    public func lockScreen() async throws { try record("lock") }
    public func sleepDisplays() async throws { try record("sleepDisplays") }
    public func startScreenSaver() async throws { try record("screenSaver") }
    public func desktopImageURL(forDisplay displayID: UInt32) -> URL? { nil }
}

@MainActor
public final class FakeLocationService: LocationService {
    public var coordinate: Coordinate?

    public init(coordinate: Coordinate? = Coordinate(latitude: 51.5, longitude: -0.12)) {
        self.coordinate = coordinate
    }

    public func currentCoordinate() async throws -> Coordinate {
        guard let coordinate else { throw SystemActionError("No location") }
        return coordinate
    }
}
