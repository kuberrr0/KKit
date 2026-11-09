import Foundation
import KKitServicesAPI
import SwiftUI

/// How a colour is written when it's copied.
enum ColorFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case hex
    case rgb
    case hsl
    case css
    case swiftUI
    case nsColor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hex: "HEX"
        case .rgb: "RGB"
        case .hsl: "HSL"
        case .css: "CSS"
        case .swiftUI: "SwiftUI"
        case .nsColor: "NSColor"
        }
    }
}

/// A colour as text in each `ColorFormat`.
enum ColorFormatter {
    static func string(_ color: RGBAColor, as format: ColorFormat, lowercaseHex: Bool = false) -> String {
        let r = byte(color.red), g = byte(color.green), b = byte(color.blue)
        let opaque = color.alpha >= 0.999
        switch format {
        case .hex:
            return lowercaseHex ? color.hex.lowercased() : color.hex
        case .rgb:
            return opaque ? "rgb(\(r), \(g), \(b))" : "rgba(\(r), \(g), \(b), \(decimal(color.alpha, places: 2)))"
        case .hsl:
            let (h, s, l) = hsl(color)
            let base = "\(Int(h.rounded()) % 360), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%"
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

    static func clamp(_ value: Double) -> Double {
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

/// Reads a colour typed or pasted as text: `#F80`, `#FF8800`, `#FF880080`, `0xFF8800`,
/// `rgb(255, 136, 0)`, `rgba(…)`, `rgb(255 136 0 / 50%)`, `hsl(32, 100%, 50%)`, `hsla(…)`,
/// and SwiftUI/AppKit code (`Color(red: 1, green: 0.53, blue: 0)`,
/// `NSColor(srgbRed: …, alpha: …)`), so every format KKit copies can be read back.
enum ColorParser {
    static func parse(_ raw: String) -> RGBAColor? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty, text.count <= 160 else { return nil }
        if text.hasPrefix("#") {
            return hex(String(text.dropFirst()))
        }
        if text.hasPrefix("0x") {
            let digits = String(text.dropFirst(2))
            return [6, 8].contains(digits.count) ? hex(digits) : nil
        }
        if let arguments = arguments(of: text, functions: ["rgba", "rgb"]) {
            return rgb(arguments)
        }
        if let arguments = arguments(of: text, functions: ["hsla", "hsl"]) {
            return hsl(arguments)
        }
        if text.contains("red:"), text.contains("green:"), text.contains("blue:") {
            return labeled(text)
        }
        return nil
    }

    /// Three, four, six or eight hex digits, without the "#".
    static func hex(_ digits: String) -> RGBAColor? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 4 {
            // #RGBA → #RRGGBBAA
            return RGBAColor(hex: digits.map { "\($0)\($0)" }.joined())
        }
        return RGBAColor(hex: digits)
    }

    // MARK: Functions

    /// The arguments of `name(…)`, split on commas, spaces and "/".
    private static func arguments(of text: String, functions: [String]) -> [String]? {
        for name in functions where text.hasPrefix(name) {
            let rest = text.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("("), rest.hasSuffix(")") else { return nil }
            let inner = rest.dropFirst().dropLast()
            return inner
                .split(whereSeparator: { $0 == "," || $0 == "/" || $0.isWhitespace })
                .map(String.init)
        }
        return nil
    }

    private static func rgb(_ arguments: [String]) -> RGBAColor? {
        guard arguments.count == 3 || arguments.count == 4 else { return nil }
        var channels: [Double] = []
        for argument in arguments.prefix(3) {
            guard let value = channel(argument) else { return nil }
            channels.append(value)
        }
        let alpha = arguments.count == 4 ? self.alpha(arguments[3]) : 1
        guard let alpha else { return nil }
        return RGBAColor(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    private static func hsl(_ arguments: [String]) -> RGBAColor? {
        guard arguments.count == 3 || arguments.count == 4,
              let hue = hue(arguments[0]),
              let saturation = percent(arguments[1]),
              let lightness = percent(arguments[2])
        else { return nil }
        let alpha = arguments.count == 4 ? self.alpha(arguments[3]) : 1
        guard let alpha else { return nil }
        let (r, g, b) = rgb(hue: hue, saturation: saturation, lightness: lightness)
        return RGBAColor(red: r, green: g, blue: b, alpha: alpha)
    }

    /// 0…255, or 0%…100%.
    private static func channel(_ text: String) -> Double? {
        if text.hasSuffix("%") {
            return percent(text)
        }
        guard let value = Double(text), (0...255).contains(value) else { return nil }
        return value / 255
    }

    /// 0…1, or 0%…100%.
    private static func alpha(_ text: String) -> Double? {
        if text.hasSuffix("%") {
            return percent(text)
        }
        guard let value = Double(text), (0...1).contains(value) else { return nil }
        return value
    }

    /// "50%" or "50" (CSS allows both in `hsl()`), as 0…1.
    private static func percent(_ text: String) -> Double? {
        let number = text.hasSuffix("%") ? String(text.dropLast()) : text
        guard let value = Double(number), (0...100).contains(value) else { return nil }
        return value / 100
    }

    /// Degrees ("30", "30deg") or turns ("0.25turn"), as 0..<360.
    private static func hue(_ text: String) -> Double? {
        var degrees: Double?
        if text.hasSuffix("deg") {
            degrees = Double(text.dropLast(3))
        } else if text.hasSuffix("turn") {
            degrees = Double(text.dropLast(4)).map { $0 * 360 }
        } else {
            degrees = Double(text)
        }
        guard let degrees, degrees.isFinite else { return nil }
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    static func rgb(hue: Double, saturation: Double, lightness: Double) -> (Double, Double, Double) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue / 60
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let base: (Double, Double, Double)
        switch sector {
        case 0..<1: base = (chroma, x, 0)
        case 1..<2: base = (x, chroma, 0)
        case 2..<3: base = (0, chroma, x)
        case 3..<4: base = (0, x, chroma)
        case 4..<5: base = (x, 0, chroma)
        default: base = (chroma, 0, x)
        }
        let m = lightness - chroma / 2
        return (ColorFormatter.clamp(base.0 + m), ColorFormatter.clamp(base.1 + m), ColorFormatter.clamp(base.2 + m))
    }

    // MARK: Code

    /// `Color(red: 1, green: 0.5, blue: 0, opacity: 0.5)` or
    /// `NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)`: 0…1 per channel.
    private static func labeled(_ text: String) -> RGBAColor? {
        guard let red = number(after: "red:", in: text),
              let green = number(after: "green:", in: text),
              let blue = number(after: "blue:", in: text)
        else { return nil }
        let alpha = number(after: "opacity:", in: text) ?? number(after: "alpha:", in: text) ?? 1
        let unit = 0.0...1.0
        guard unit.contains(red), unit.contains(green), unit.contains(blue), unit.contains(alpha) else { return nil }
        return RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func number(after label: String, in text: String) -> Double? {
        guard let range = text.range(of: label) else { return nil }
        let digits = text[range.upperBound...]
            .drop { $0.isWhitespace }
            .prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }
}

extension RGBAColor {
    /// For drawing swatches.
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Whether white or black text reads better on top.
    var isLight: Bool {
        0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.6
    }
}
