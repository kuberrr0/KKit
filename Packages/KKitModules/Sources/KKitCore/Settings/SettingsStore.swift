import Foundation
import Observation

/// The app's settings, backed by `UserDefaults`. Values are stored JSON-encoded under
/// their full key ("nightShift.intensity").
///
/// It's `@Observable`: a SwiftUI view that reads a value re-renders when any setting
/// changes. Logic can `await` changes of one key with `changes(of:default:)`.
///
/// Large or list-like data (clipboard history, frecency) doesn't belong here; use the
/// feature's storage instead.
@MainActor
@Observable
public final class SettingsStore {
    private let defaults: UserDefaults
    /// Bumped on every write so Observation picks up changes.
    private var revision = 0
    @ObservationIgnored private var listeners: [String: [UUID: (Data?) -> Void]] = [:]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func value<Value: Codable & Sendable>(for key: String, default defaultValue: Value) -> Value {
        _ = revision
        return Self.decode(defaults.data(forKey: key), default: defaultValue)
    }

    public func set<Value: Codable & Sendable>(_ value: Value, for key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        if defaults.data(forKey: key) == data { return }
        defaults.set(data, forKey: key)
        didChange(key, data)
    }

    /// Removes the stored value so reads return the default again.
    public func reset(_ key: String) {
        guard defaults.object(forKey: key) != nil else { return }
        defaults.removeObject(forKey: key)
        didChange(key, nil)
    }

    public func hasValue(for key: String) -> Bool {
        _ = revision
        return defaults.object(forKey: key) != nil
    }

    /// The current value, then every new value of `key`, until the task is cancelled.
    public func changes<Value: Codable & Sendable>(
        of key: String,
        default defaultValue: Value
    ) -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Value.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let id = UUID()
        continuation.yield(value(for: key, default: defaultValue))
        listeners[key, default: [:]][id] = { data in
            continuation.yield(Self.decode(data, default: defaultValue))
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.removeListener(id, for: key) }
        }
        return stream
    }

    private func removeListener(_ id: UUID, for key: String) {
        listeners[key]?[id] = nil
        if listeners[key]?.isEmpty == true {
            listeners[key] = nil
        }
    }

    private func didChange(_ key: String, _ data: Data?) {
        revision &+= 1
        for listener in (listeners[key] ?? [:]).values {
            listener(data)
        }
    }

    nonisolated private static func decode<Value: Decodable>(_ data: Data?, default defaultValue: Value) -> Value {
        guard let data, let value = try? JSONDecoder().decode(Value.self, from: data) else {
            return defaultValue
        }
        return value
    }
}

/// A feature's view of the settings store: keys are prefixed with the feature id.
@MainActor
public struct FeatureSettings: Sendable {
    public let featureID: FeatureID
    public let store: SettingsStore

    public init(featureID: FeatureID, store: SettingsStore) {
        self.featureID = featureID
        self.store = store
    }

    public func fullKey<Value>(_ key: SettingKey<Value>) -> String {
        "\(featureID.rawValue).\(key.name)"
    }

    public subscript<Value>(key: SettingKey<Value>) -> Value {
        get { store.value(for: fullKey(key), default: key.defaultValue) }
        nonmutating set { store.set(newValue, for: fullKey(key)) }
    }

    public func reset<Value>(_ key: SettingKey<Value>) {
        store.reset(fullKey(key))
    }

    /// The current value, then every new value.
    public func changes<Value>(of key: SettingKey<Value>) -> AsyncStream<Value> {
        store.changes(of: fullKey(key), default: key.defaultValue)
    }
}
