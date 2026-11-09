import Foundation

public enum SleepAssertionKind: Sendable, Hashable {
    /// Keep the Mac awake; the display may sleep.
    case system
    /// Keep the display (and so the Mac) awake.
    case display
}

/// A held "don't sleep" assertion. Always `release()` it when done.
@MainActor
public protocol SleepAssertion: AnyObject {
    var kind: SleepAssertionKind { get }
    func release()
}

/// The current power source.
public struct PowerSourceInfo: Sendable, Equatable {
    public var hasBattery: Bool
    public var isOnAC: Bool
    public var isCharging: Bool
    /// 0…1
    public var batteryLevel: Double?
    /// Minutes; `nil` while macOS is still estimating.
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?

    public init(
        hasBattery: Bool = false,
        isOnAC: Bool = true,
        isCharging: Bool = false,
        batteryLevel: Double? = nil,
        minutesToEmpty: Int? = nil,
        minutesToFull: Int? = nil
    ) {
        self.hasBattery = hasBattery
        self.isOnAC = isOnAC
        self.isCharging = isCharging
        self.batteryLevel = batteryLevel
        self.minutesToEmpty = minutesToEmpty
        self.minutesToFull = minutesToFull
    }
}

/// Battery details from the `AppleSmartBattery` IORegistry entry.
public struct BatteryHealth: Sendable, Equatable {
    public var cycleCount: Int?
    /// Full-charge capacity ÷ design capacity, 0…1.
    public var health: Double?
    /// Positive while charging, negative while discharging.
    public var powerWatts: Double?
    public var temperatureCelsius: Double?

    public init(cycleCount: Int? = nil, health: Double? = nil, powerWatts: Double? = nil, temperatureCelsius: Double? = nil) {
        self.cycleCount = cycleCount
        self.health = health
        self.powerWatts = powerWatts
        self.temperatureCelsius = temperatureCelsius
    }
}

/// Sleep assertions and power source information (IOKit). It also posts
/// `AppEvent.powerSourceChanged`.
@MainActor
public protocol PowerService: AnyObject {
    /// `nil` if macOS refused the assertion.
    func preventSleep(_ kind: SleepAssertionKind, reason: String) -> (any SleepAssertion)?
    var powerSource: PowerSourceInfo { get }
    /// The current power source, then every change.
    func powerSourceUpdates() -> AsyncStream<PowerSourceInfo>
    /// `nil` on Macs without a battery.
    func batteryHealth() async -> BatteryHealth?
}
