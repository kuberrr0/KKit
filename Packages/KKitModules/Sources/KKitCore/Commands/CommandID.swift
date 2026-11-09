import Foundation

/// A command's identifier: `<featureID>.<verb>`, e.g. `"nightShift.toggle"`.
public struct CommandID: Hashable, Sendable, Codable, Comparable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }

    /// The part before the first dot. The registry checks it matches the owner.
    public var featureID: FeatureID {
        FeatureID(String(rawValue.prefix { $0 != "." }))
    }

    /// The part after the first dot ("toggle").
    public var verb: String {
        guard let dot = rawValue.firstIndex(of: ".") else { return "" }
        return String(rawValue[rawValue.index(after: dot)...])
    }

    public static func < (lhs: CommandID, rhs: CommandID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: any Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
