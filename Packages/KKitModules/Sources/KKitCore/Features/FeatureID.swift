import Foundation

/// A feature's stable identifier, in lowerCamelCase: `"nightShift"`, `"timer"`.
///
/// It prefixes the feature's command ids (`nightShift.toggle`), namespaces its settings
/// (`nightShift.intensity`), names its storage folder and its log category. Never
/// change it once a feature has shipped.
public struct FeatureID: Hashable, Sendable, Codable, Comparable,
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

    public static func < (lhs: FeatureID, rhs: FeatureID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The owner id used for KKit's own commands and settings (not a feature).
    public static let app: FeatureID = "app"

    /// `true` for lowerCamelCase ids made of ASCII letters and digits.
    public var isValid: Bool {
        guard let first = rawValue.unicodeScalars.first,
              CharacterSet.lowercaseLetters.contains(first)
        else { return false }
        return rawValue.unicodeScalars.allSatisfy {
            $0.isASCII && CharacterSet.alphanumerics.contains($0)
        }
    }

    public init(from decoder: any Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
