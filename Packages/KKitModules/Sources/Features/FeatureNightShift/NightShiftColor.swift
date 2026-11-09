import Foundation
import KKitServicesAPI

/// Turns mode + intensity + dim into per-channel gamma multipliers.
enum NightShiftColor {
    /// The neutral white point. Intensity 0 maps here, i.e. no change.
    static let neutralKelvin = 6500.0
    /// Intensity 2 (200%) maps here; intensity 1 lands near 2800 K, macOS's warmest.
    static let warmestKelvin = 1200.0

    static func adjustment(mode: NightShiftMode, intensity: Double, extraDim: Double) -> ColorAdjustment {
        let intensity = min(max(intensity, 0), 2)
        var color: (r: Double, g: Double, b: Double)
        switch mode {
        case .warm:
            color = warm(intensity)
        case .amber:
            let base = warm(intensity)
            let cut = min(intensity, 1)
            color = (base.r, base.g * (1 - 0.15 * cut), base.b * (1 - 0.6 * cut))
        case .darkroom:
            if intensity <= 1 {
                // Fade from neutral to pure red.
                color = (1, 1 - intensity, 1 - intensity)
            } else {
                // Beyond 100%, dim the red itself.
                color = (1 - 0.35 * (intensity - 1), 0, 0)
            }
        }
        let dim = 1 - min(max(extraDim, 0), 0.8)
        return ColorAdjustment(red: color.r * dim, green: color.g * dim, blue: color.b * dim)
    }

    /// Mixes from no change (`progress` 0) to `target` (1), for fades.
    static func blend(_ target: ColorAdjustment, progress: Double) -> ColorAdjustment {
        let p = min(max(progress, 0), 1)
        return ColorAdjustment(
            red: 1 + (target.red - 1) * p,
            green: 1 + (target.green - 1) * p,
            blue: 1 + (target.blue - 1) * p
        )
    }

    static func kelvin(forIntensity intensity: Double) -> Double {
        neutralKelvin * pow(warmestKelvin / neutralKelvin, min(max(intensity, 0), 2) / 2)
    }

    private static func warm(_ intensity: Double) -> (r: Double, g: Double, b: Double) {
        let target = rgb(kelvin: kelvin(forIntensity: intensity))
        let neutral = rgb(kelvin: neutralKelvin)
        return (
            min(1, target.r / neutral.r),
            min(1, target.g / neutral.g),
            min(1, target.b / neutral.b)
        )
    }

    /// Tanner Helland's black-body approximation, 0…1 per channel.
    static func rgb(kelvin: Double) -> (r: Double, g: Double, b: Double) {
        let t = kelvin / 100
        let red: Double = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let green: Double = t <= 66
            ? 99.4708025861 * log(t) - 161.1195681661
            : 288.1221695283 * pow(t - 60, -0.0755148492)
        let blue: Double
        if t >= 66 {
            blue = 255
        } else if t <= 19 {
            blue = 0
        } else {
            blue = 138.5177312231 * log(t - 10) - 305.0447927307
        }
        func unit(_ value: Double) -> Double { min(max(value, 0), 255) / 255 }
        return (unit(red), unit(green), unit(blue))
    }
}
