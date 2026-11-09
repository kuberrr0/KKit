import Foundation
import KKitCore
import KKitServicesAPI

/// The file format screenshots are saved in.
enum ImageFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case png
    case jpeg
    case heic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }

    /// The UTType identifier ImageIO writes.
    var typeIdentifier: String {
        switch self {
        case .png: "public.png"
        case .jpeg: "public.jpeg"
        case .heic: "public.heic"
        }
    }
}

/// A language to translate into.
struct TranslationLanguage: Identifiable, Hashable, Sendable {
    let id: String

    var name: String {
        Locale.current.localizedString(forIdentifier: id) ?? id
    }

    static let common: [TranslationLanguage] = [
        "en", "es", "fr", "de", "it", "pt", "nl", "pl", "ru", "uk", "tr", "ar", "hi",
        "id", "vi", "th", "ja", "ko", "zh-Hans", "zh-Hant",
    ].map(TranslationLanguage.init(id:))

    /// The user's own language, if it's one of the common ones.
    static var preferred: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return common.contains { $0.id == code } ? code : "en"
    }
}

enum ScreenToolsSettings {
    // Screenshots
    /// Empty means the Desktop.
    static let saveFolder = SettingKey("saveFolder", default: "")
    /// Date formats in braces, like Quick Note's daily note path.
    static let fileNamePattern = SettingKey("fileNamePattern", default: "Screenshot {yyyy-MM-dd} at {HH.mm.ss}")
    static let format = SettingKey("format", default: ImageFormat.png)
    static let jpegQuality = SettingKey("jpegQuality", default: 0.9)
    static let copyAfterCapture = SettingKey("copyAfterCapture", default: true)
    static let saveAfterCapture = SettingKey("saveAfterCapture", default: true)
    static let showInIsland = SettingKey("showInIsland", default: true)
    /// How long the thumbnail stays in the Island.
    static let thumbnailSeconds = SettingKey("thumbnailSeconds", default: 8.0)
    static let showCursor = SettingKey("showCursor", default: false)
    /// Seconds before a timed screenshot.
    static let timerSeconds = SettingKey("timerSeconds", default: 5)

    // Text and codes
    /// A Vision language code ("en-US"); empty detects the language.
    static let ocrLanguage = SettingKey("ocrLanguage", default: "")
    /// Open a scanned link straight away instead of only copying it.
    static let openScannedLinks = SettingKey("openScannedLinks", default: false)
    static let translateTarget = SettingKey("translateTarget", default: TranslationLanguage.preferred)

    // Recording
    static let recordSystemAudio = SettingKey("recordSystemAudio", default: false)
    static let recordMicrophone = SettingKey("recordMicrophone", default: false)
    static let showClicks = SettingKey("showClicks", default: true)
    static let recordFPS = SettingKey("recordFPS", default: 30)
    static let recordingNamePattern = SettingKey("recordingNamePattern", default: "Recording {yyyy-MM-dd} at {HH.mm.ss}")
}
