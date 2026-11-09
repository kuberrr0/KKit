import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import KKitCore
import KKitServicesAPI

/// Sleep assertions and power source information through IOKit. Power source changes
/// arrive through an IOKit run loop source (no polling) and are also posted as
/// `AppEvent.powerSourceChanged`.
@MainActor
public final class IOKitPowerService: PowerService {
    public private(set) var powerSource: PowerSourceInfo

    private let events: EventBus
    private let broadcast = Broadcast<PowerSourceInfo>()
    private var runLoopSource: CFRunLoopSource?
    private let log = KKitLog.logger("power")

    public init(events: EventBus) {
        self.events = events
        self.powerSource = Self.readPowerSource()
        installNotification()
    }

    public func preventSleep(_ kind: SleepAssertionKind, reason: String) -> (any SleepAssertion)? {
        let type = kind == .display ? "PreventUserIdleDisplaySleep" : "PreventUserIdleSystemSleep"
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            log.error("IOPMAssertionCreateWithName failed: \(result)")
            return nil
        }
        return IOKitSleepAssertion(kind: kind, id: id)
    }

    public func powerSourceUpdates() -> AsyncStream<PowerSourceInfo> {
        broadcast.stream(initial: powerSource)
    }

    public func batteryHealth() async -> BatteryHealth? {
        await Task.detached(priority: .utility) {
            Self.readBatteryHealth()
        }.value
    }

    // MARK: Private

    fileprivate func refresh() {
        let updated = Self.readPowerSource()
        guard updated != powerSource else { return }
        let sourceChanged = updated.isOnAC != powerSource.isOnAC
        powerSource = updated
        broadcast.send(updated)
        if sourceChanged {
            events.publish(.powerSourceChanged(isOnAC: updated.isOnAC))
        }
    }

    private func installNotification() {
        // The service lives as long as the app, so an unretained pointer is fine.
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(Self.makeCallback(), context)?.takeRetainedValue() else {
            log.error("Couldn't watch power source changes")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    /// IOKit calls this on the main run loop.
    nonisolated private static func makeCallback() -> IOPowerSourceCallbackType {
        { context in
            guard let context else { return }
            let service = Unmanaged<IOKitPowerService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                service.refresh()
            }
        }
    }

    nonisolated static func readPowerSource() -> PowerSourceInfo {
        var info = PowerSourceInfo(hasBattery: false, isOnAC: true)
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return info }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (description["Type"] as? String) == "InternalBattery"
            else { continue }
            info.hasBattery = true
            let current = description["Current Capacity"] as? Int ?? 0
            let maximum = description["Max Capacity"] as? Int ?? 100
            info.batteryLevel = maximum > 0 ? min(1, Double(current) / Double(maximum)) : nil
            info.isCharging = description["Is Charging"] as? Bool ?? false
            if let state = description["Power Source State"] as? String {
                info.isOnAC = state == "AC Power"
            }
            if let minutes = description["Time to Empty"] as? Int, minutes > 0 {
                info.minutesToEmpty = minutes
            }
            if let minutes = description["Time to Full Charge"] as? Int, minutes > 0 {
                info.minutesToFull = minutes
            }
        }
        return info
    }

    nonisolated static func readBatteryHealth() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, nil, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }

        var health = BatteryHealth()
        health.cycleCount = dictionary["CycleCount"] as? Int
        let design = dictionary["DesignCapacity"] as? Int ?? 0
        let fullCharge = dictionary["AppleRawMaxCapacity"] as? Int ?? dictionary["NominalChargeCapacity"] as? Int ?? 0
        if design > 0, fullCharge > 0 {
            health.health = min(1.5, Double(fullCharge) / Double(design))
        }
        if let millivolts = dictionary["Voltage"] as? Int,
           let milliamps = dictionary["InstantAmperage"] as? Int ?? dictionary["Amperage"] as? Int {
            health.powerWatts = Double(millivolts) * Double(milliamps) / 1_000_000
        }
        if let temperature = dictionary["Temperature"] as? Int {
            health.temperatureCelsius = Double(temperature) / 100
        }
        return health
    }
}

@MainActor
final class IOKitSleepAssertion: SleepAssertion {
    let kind: SleepAssertionKind
    private let id: IOPMAssertionID
    private var isReleased = false

    init(kind: SleepAssertionKind, id: IOPMAssertionID) {
        self.kind = kind
        self.id = id
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        IOPMAssertionRelease(id)
    }
}
