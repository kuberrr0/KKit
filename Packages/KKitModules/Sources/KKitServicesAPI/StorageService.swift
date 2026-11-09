import Foundation
import KKitCore

/// Per-feature files under ~/Library/Application Support/KKit/<featureID>/.
///
/// Thread-safe, so features can read and write from actors and background tasks.
/// SQLite (GRDB) databases are added here when Clipboard History needs them (M3).
public protocol StorageService: Sendable {
    /// The feature's folder, created if needed.
    func directory(for feature: FeatureID) throws -> URL
    /// Reads `<name>.json`; `nil` if it doesn't exist.
    func readJSON<Value: Decodable>(_ type: Value.Type, named name: String, for feature: FeatureID) throws -> Value?
    /// Writes `<name>.json` atomically.
    func writeJSON<Value: Encodable>(_ value: Value, named name: String, for feature: FeatureID) throws
    func removeJSON(named name: String, for feature: FeatureID) throws
}

/// A feature's handle on its storage.
public struct FeatureStorage: Sendable {
    public let featureID: FeatureID
    public let service: any StorageService

    public init(featureID: FeatureID, service: any StorageService) {
        self.featureID = featureID
        self.service = service
    }

    public func directory() throws -> URL {
        try service.directory(for: featureID)
    }

    public func read<Value: Decodable>(_ type: Value.Type, named name: String) throws -> Value? {
        try service.readJSON(type, named: name, for: featureID)
    }

    public func write<Value: Encodable>(_ value: Value, named name: String) throws {
        try service.writeJSON(value, named: name, for: featureID)
    }

    public func remove(named name: String) throws {
        try service.removeJSON(named: name, for: featureID)
    }
}
