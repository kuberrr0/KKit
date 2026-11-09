import Foundation

public struct DisplayInfo: Identifiable, Hashable, Sendable {
    /// `CGDirectDisplayID`. Can change when displays are reconnected.
    public var id: UInt32
    /// Vendor, model and serial: stable across reconnects, for remembering settings.
    public var stableID: String
    public var name: String
    public var isBuiltIn: Bool

    public init(id: UInt32, stableID: String, name: String, isBuiltIn: Bool) {
        self.id = id
        self.stableID = stableID
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}

/// Per-channel multipliers applied on top of the display's own colour profile.
/// `1, 1, 1` is no change; `1, 0.6, 0.3` is warm; `1, 0, 0` is red only.
public struct ColorAdjustment: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let identity = ColorAdjustment(red: 1, green: 1, blue: 1)

    public var isIdentity: Bool { self == .identity }
}

/// Displays and their gamma tables. The implementation re-applies adjustments when
/// displays change and after wake, because macOS resets gamma tables then.
@MainActor
public protocol DisplayService: AnyObject {
    var displays: [DisplayInfo] { get }
    /// Applies `adjustment` to one display (`.identity` restores it).
    func setColorAdjustment(_ adjustment: ColorAdjustment, for displayID: UInt32)
    /// Restores every display's own colour profile.
    func resetColorAdjustments()
}
