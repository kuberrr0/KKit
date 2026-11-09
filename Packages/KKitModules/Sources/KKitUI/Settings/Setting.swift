import KKitCore
import SwiftUI

public extension EnvironmentValues {
    /// The settings of the feature whose pane is being shown. The Settings host sets it.
    var featureSettings: FeatureSettings? {
        get { self[FeatureSettingsKey.self] }
        set { self[FeatureSettingsKey.self] = newValue }
    }
}

private struct FeatureSettingsKey: EnvironmentKey {
    static var defaultValue: FeatureSettings? { nil }
}

/// Reads and writes one of the current feature's settings from a SwiftUI view.
///
/// ```swift
/// @Setting(NightShiftSettings.intensity) var intensity
/// Slider(value: $intensity, in: 0...2)
/// ```
///
/// Outside a feature's settings pane (no `featureSettings` in the environment) it reads
/// the default value and ignores writes.
@MainActor
@propertyWrapper
public struct Setting<Value: Codable & Sendable>: DynamicProperty {
    @Environment(\.featureSettings) private var settings
    private let key: SettingKey<Value>

    public init(_ key: SettingKey<Value>) {
        self.key = key
    }

    public var wrappedValue: Value {
        get { settings?[key] ?? key.defaultValue }
        nonmutating set { settings?[key] = newValue }
    }

    public var projectedValue: Binding<Value> {
        let settings = settings
        let key = key
        return Binding(
            get: { settings?[key] ?? key.defaultValue },
            set: { settings?[key] = $0 }
        )
    }
}
