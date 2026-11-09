import Foundation

/// A typed setting. `name` is short ("intensity"); `FeatureSettings` stores it as
/// "<featureID>.intensity".
///
/// ```swift
/// enum NightShiftSettings {
///     static let intensity = SettingKey("intensity", default: 0.7)
/// }
/// ```
public struct SettingKey<Value: Codable & Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}
