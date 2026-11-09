import Foundation
import KKitCore

/// How long history is kept.
enum ClipboardRetention: String, Codable, Sendable, CaseIterable, Identifiable {
    case day
    case week
    case month
    case threeMonths
    case forever

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: String(localized: "1 day")
        case .week: String(localized: "1 week")
        case .month: String(localized: "1 month")
        case .threeMonths: String(localized: "3 months")
        case .forever: String(localized: "Until the limit is reached")
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .threeMonths: 90 * 86_400
        case .forever: nil
        }
    }
}

enum ClipboardSettings {
    /// Most items kept (pinned items don't count).
    static let maxItems = SettingKey("maxItems", default: 500)
    static let retention = SettingKey("retention", default: ClipboardRetention.month)
    static let keepRichText = SettingKey("keepRichText", default: true)
    static let keepImages = SettingKey("keepImages", default: true)
    static let keepFiles = SettingKey("keepFiles", default: true)
    /// Bundle ids whose copies are never saved. Starts with the password managers.
    static let ignoredApps = SettingKey("ignoredApps", default: ClipboardFilter.defaultIgnoredApps.sorted())
    /// Recording paused (Quick Toggle).
    static let paused = SettingKey("paused", default: false)
    static let clearOnQuit = SettingKey("clearOnQuit", default: false)
    /// A small "Copied" flash in the Island for every copy.
    static let flashInIsland = SettingKey("flashInIsland", default: false)
    /// ↵ in the picker pastes (instead of only copying).
    static let pasteOnSelect = SettingKey("pasteOnSelect", default: true)

    @MainActor
    static func rules(_ settings: FeatureSettings) -> ClipboardRules {
        ClipboardRules(
            ignoredBundleIDs: Set(settings[ignoredApps]),
            keepsRichText: settings[keepRichText],
            keepsImages: settings[keepImages],
            keepsFiles: settings[keepFiles]
        )
    }
}
