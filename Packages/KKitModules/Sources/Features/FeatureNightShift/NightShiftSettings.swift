import KKitCore
import KKitServicesAPI

enum NightShiftMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Classic warm tint.
    case warm
    /// Stronger: cuts blue faster.
    case amber
    /// Red only, for night use.
    case darkroom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: String(localized: "Warm")
        case .amber: String(localized: "Amber")
        case .darkroom: String(localized: "Darkroom")
        }
    }
}

enum NightShiftScheduleKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case manual
    case custom
    case sunset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: String(localized: "Off (manual)")
        case .custom: String(localized: "Custom times")
        case .sunset: String(localized: "Sunset to sunrise")
        }
    }
}

enum NightShiftSettings {
    /// The on/off switch when the schedule is manual. Remembered across launches.
    static let isOn = SettingKey("isOn", default: false)
    /// 0…2: above 1 goes beyond what macOS Night Shift allows.
    static let intensity = SettingKey("intensity", default: 0.7)
    static let mode = SettingKey("mode", default: NightShiftMode.warm)
    /// 0…0.8: darkens everything, below the minimum brightness.
    static let extraDim = SettingKey("extraDim", default: 0.0)
    static let schedule = SettingKey("schedule", default: NightShiftScheduleKind.manual)
    /// Minutes after midnight.
    static let customStart = SettingKey("customStart", default: 22 * 60)
    static let customEnd = SettingKey("customEnd", default: 7 * 60)
    /// For sunset and sunrise times.
    static let coordinate = SettingKey("coordinate", default: Coordinate?.none)
    /// Seconds to fade in and out.
    static let transitionSeconds = SettingKey("transitionSeconds", default: 1.0)
    /// `DisplayInfo.stableID`s left untinted.
    static let disabledDisplays = SettingKey("disabledDisplays", default: [String]())
    /// Bundle ids that pause the tint while frontmost (photo editors).
    static let disabledApps = SettingKey("disabledApps", default: [String]())
}
