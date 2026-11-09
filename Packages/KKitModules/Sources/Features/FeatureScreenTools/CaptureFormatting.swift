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

/// A colour as text in each `ColorFormat`.
enum ColorFormatter {
    static func string(_ color: RGBAColor, as format: ColorFormat) -> String {
        let r = byte(color.red), g = byte(color.green), b = byte(color.blue)
        let opaque = color.alpha >= 0.999
        switch format {
        case .hex:
            return color.hex
        case .rgb:
            return opaque ? "rgb(\(r), \(g), \(b))" : "rgba(\(r), \(g), \(b), \(decimal(color.alpha, places: 2)))"
        case .hsl:
            let (h, s, l) = hsl(color)
            let base = "\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%"
            return opaque ? "hsl(\(base))" : "hsla(\(base), \(decimal(color.alpha, places: 2)))"
        case .css:
            let alpha = opaque ? "" : " / \(Int((color.alpha * 100).rounded()))%"
            return "rgb(\(r) \(g) \(b)\(alpha))"
        case .swiftUI:
            let alpha = opaque ? "" : ", opacity: \(decimal(color.alpha, places: 3))"
            return "Color(red: \(decimal(color.red, places: 3)), green: \(decimal(color.green, places: 3)), blue: \(decimal(color.blue, places: 3))\(alpha))"
        case .nsColor:
            return "NSColor(srgbRed: \(decimal(color.red, places: 3)), green: \(decimal(color.green, places: 3)), blue: \(decimal(color.blue, places: 3)), alpha: \(decimal(color.alpha, places: 3)))"
        }
    }

    /// Hue 0…360, saturation and lightness 0…1.
    static func hsl(_ color: RGBAColor) -> (Double, Double, Double) {
        let r = clamp(color.red), g = clamp(color.green), b = clamp(color.blue)
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let lightness = (maxValue + minValue) / 2
        let delta = maxValue - minValue
        guard delta > 0.000_01 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        if maxValue == r {
            hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxValue == g {
            hue = 60 * ((b - r) / delta + 2)
        } else {
            hue = 60 * ((r - g) / delta + 4)
        }
        if hue < 0 { hue += 360 }
        return (hue, min(saturation, 1), lightness)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func byte(_ value: Double) -> Int {
        Int((clamp(value) * 255).rounded())
    }

    /// Up to `places` decimals, without trailing zeros: 0.5, 1, 0.502.
    static func decimal(_ value: Double, places: Int) -> String {
        let text = String(format: "%.\(places)f", value)
        guard text.contains(".") else { return text }
        var trimmed = text
        while trimmed.hasSuffix("0") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix(".") {
            trimmed.removeLast()
        }
        return trimmed
    }
}
