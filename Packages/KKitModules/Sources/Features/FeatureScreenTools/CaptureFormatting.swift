import Foundation
import KKitServicesAPI

/// File names from a pattern: date formats go in braces,
/// "Screenshot {yyyy-MM-dd} at {HH.mm.ss}" → "Screenshot 2026-11-09 at 14.05.09".
enum CaptureFileNamer {
    static func name(pattern: String, date: Date, timeZone: TimeZone = .current) -> String {
        var output = ""
        var rest = Substring(pattern)
        while let open = rest.firstIndex(of: "{") {
            output += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else {
                output += rest[open...]
                rest = ""
                break
            }
            let format = String(rest[rest.index(after: open)..<close])
            output += format.isEmpty ? "" : formatted(date, format, timeZone: timeZone)
            rest = rest[rest.index(after: close)...]
        }
        output += rest
        let cleaned = sanitized(output)
        return cleaned.isEmpty ? "Screenshot" : cleaned
    }

    /// No slashes or colons (Finder shows ":" as "/"), no leading dots.
    static func sanitized(_ name: String) -> String {
        var result = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        while result.hasPrefix(".") {
            result.removeFirst()
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `folder/name.ext`, or `name (2).ext` and so on if that's taken.
    static func uniqueURL(in folder: URL, name: String, fileExtension: String, exists: (URL) -> Bool) -> URL {
        var candidate = folder.appendingPathComponent("\(name).\(fileExtension)")
        var counter = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(name) (\(counter)).\(fileExtension)")
            counter += 1
        }
        return candidate
    }

    private static func formatted(_ date: Date, _ format: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
