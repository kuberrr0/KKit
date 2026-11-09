import Foundation
import KKitCore
import KKitServicesAPI

/// Stores each feature's files in `<root>/<featureID>/`.
public final class FileStorageService: StorageService {
    public enum StorageError: LocalizedError {
        case invalidFeatureID(FeatureID)
        case invalidName(String)

        public var errorDescription: String? {
            switch self {
            case .invalidFeatureID(let id): "Invalid feature id “\(id.rawValue)”."
            case .invalidName(let name): "Invalid file name “\(name)”."
            }
        }
    }

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/KKit`.
    public static func applicationSupport() throws -> FileStorageService {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return FileStorageService(root: base.appendingPathComponent("KKit", isDirectory: true))
    }

    public func directory(for feature: FeatureID) throws -> URL {
        guard feature.isValid else { throw StorageError.invalidFeatureID(feature) }
        let url = root.appendingPathComponent(feature.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func readJSON<Value: Decodable>(_ type: Value.Type, named name: String, for feature: FeatureID) throws -> Value? {
        let url = try fileURL(named: name, for: feature)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    public func writeJSON<Value: Encodable>(_ value: Value, named name: String, for feature: FeatureID) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: fileURL(named: name, for: feature), options: .atomic)
    }

    public func removeJSON(named name: String, for feature: FeatureID) throws {
        let url = try fileURL(named: name, for: feature)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(named name: String, for feature: FeatureID) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else {
            throw StorageError.invalidName(name)
        }
        return try directory(for: feature).appendingPathComponent("\(name).json", isDirectory: false)
    }
}
