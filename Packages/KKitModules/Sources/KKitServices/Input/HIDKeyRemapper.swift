import Foundation
import KKitServicesAPI

/// Caps Lock → another key with `hidutil` (the same mechanism as System Settings ›
/// Keyboard › Modifier Keys, per login session). Mappings other apps or the user set
/// are read first and kept.
actor HIDKeyRemapper {
    struct Mapping: Hashable, Sendable {
        var source: UInt64
        var destination: UInt64
    }

    private static let tool = "/usr/bin/hidutil"

    func setCapsLock(to destination: UInt64?) async throws {
        let current = Self.parse(try await ProcessRunner.run(Self.tool, ["property", "--get", "UserKeyMapping"]))
        var updated = current.filter { $0.source != CapsLockRemap.capsLockUsage }
        if let destination {
            updated.append(Mapping(source: CapsLockRemap.capsLockUsage, destination: destination))
        }
        guard updated != current else { return }
        try await ProcessRunner.run(Self.tool, ["property", "--set", Self.json(updated)])
    }

    /// `hidutil property --get UserKeyMapping` prints an old-style plist:
    /// `( { HIDKeyboardModifierMappingDst = 30064771181; HIDKeyboardModifierMappingSrc = 30064771129; } )`
    /// or `(null)`.
    static func parse(_ output: String) -> [Mapping] {
        var mappings: [Mapping] = []
        let entries = output.components(separatedBy: "}")
        for entry in entries {
            guard let source = number(after: "HIDKeyboardModifierMappingSrc", in: entry),
                  let destination = number(after: "HIDKeyboardModifierMappingDst", in: entry) else { continue }
            mappings.append(Mapping(source: source, destination: destination))
        }
        return mappings
    }

    static func json(_ mappings: [Mapping]) -> String {
        let items = mappings.map {
            "{\"HIDKeyboardModifierMappingSrc\":\($0.source),\"HIDKeyboardModifierMappingDst\":\($0.destination)}"
        }
        return "{\"UserKeyMapping\":[\(items.joined(separator: ","))]}"
    }

    private static func number(after key: String, in text: String) -> UInt64? {
        guard let range = text.range(of: key) else { return nil }
        let rest = text[range.upperBound...].drop { $0 == " " || $0 == "=" || $0 == "\t" }
        // Some versions print hex: 0x700000039.
        if rest.hasPrefix("0x") {
            let hex = rest.dropFirst(2).prefix { $0.isHexDigit }
            return UInt64(hex, radix: 16)
        }
        let digits = rest.prefix { $0.isNumber }
        return digits.isEmpty ? nil : UInt64(digits)
    }
}
