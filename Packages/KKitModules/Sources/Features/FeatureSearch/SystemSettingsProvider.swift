import Foundation
import KKitCore

/// A System Settings pane, opened with an `x-apple.systempreferences:` link.
struct SystemSettingsPane: Sendable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let keywords: [String]
    /// "Privacy & Security" for its sub-panes.
    let parent: String?

    init(_ id: String, _ title: String, symbol: String, keywords: [String] = [], parent: String? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.keywords = keywords
        self.parent = parent
    }

    var url: URL {
        URL(string: "x-apple.systempreferences:\(id)")!
    }

    /// The panes of macOS 14–15 System Settings. Ids that a macOS version doesn't know
    /// open System Settings on its last pane, so a wrong id is harmless.
    static var all: [SystemSettingsPane] {
        let privacy = String(localized: "Privacy & Security")
        let general = String(localized: "General")
        return [
            SystemSettingsPane("com.apple.wifi-settings-extension", String(localized: "Wi-Fi"), symbol: "wifi", keywords: ["wireless", "network", "internet"]),
            SystemSettingsPane("com.apple.BluetoothSettings", String(localized: "Bluetooth"), symbol: "dot.radiowaves.left.and.right", keywords: ["headphones", "airpods", "devices"]),
            SystemSettingsPane("com.apple.Network-Settings.extension", String(localized: "Network"), symbol: "network", keywords: ["ethernet", "vpn", "dns", "proxy", "firewall"]),
            SystemSettingsPane("com.apple.Notifications-Settings.extension", String(localized: "Notifications"), symbol: "bell.badge", keywords: ["alerts", "banners"]),
            SystemSettingsPane("com.apple.Sound-Settings.extension", String(localized: "Sound"), symbol: "speaker.wave.2", keywords: ["audio", "volume", "output", "input", "microphone", "alert"]),
            SystemSettingsPane("com.apple.Focus-Settings.extension", String(localized: "Focus"), symbol: "moon", keywords: ["do not disturb", "dnd"]),
            SystemSettingsPane("com.apple.Screen-Time-Settings.extension", String(localized: "Screen Time"), symbol: "hourglass", keywords: ["limits", "parental"]),
            SystemSettingsPane("com.apple.systempreferences.GeneralSettings", general, symbol: "gearshape"),
            SystemSettingsPane("com.apple.Appearance-Settings.extension", String(localized: "Appearance"), symbol: "circle.lefthalf.filled", keywords: ["dark mode", "light mode", "accent colour", "accent color", "theme"]),
            SystemSettingsPane("com.apple.Accessibility-Settings.extension", String(localized: "Accessibility"), symbol: "accessibility", keywords: ["voiceover", "zoom", "contrast", "reduce motion"]),
            SystemSettingsPane("com.apple.ControlCenter-Settings.extension", String(localized: "Control Centre"), symbol: "switch.2", keywords: ["control center", "menu bar"]),
            SystemSettingsPane("com.apple.Siri-Settings.extension", String(localized: "Siri & Spotlight"), symbol: "magnifyingglass", keywords: ["siri", "spotlight", "apple intelligence"]),
            SystemSettingsPane("com.apple.settings.PrivacySecurity.extension", privacy, symbol: "hand.raised", keywords: ["privacy", "security", "gatekeeper", "filevault"]),
            SystemSettingsPane("com.apple.Desktop-Settings.extension", String(localized: "Desktop & Dock"), symbol: "dock.rectangle", keywords: ["dock", "mission control", "stage manager", "hot corners", "widgets"]),
            SystemSettingsPane("com.apple.Displays-Settings.extension", String(localized: "Displays"), symbol: "display", keywords: ["monitor", "resolution", "brightness", "night shift", "true tone"]),
            SystemSettingsPane("com.apple.Wallpaper-Settings.extension", String(localized: "Wallpaper"), symbol: "photo", keywords: ["background", "desktop picture"]),
            SystemSettingsPane("com.apple.ScreenSaver-Settings.extension", String(localized: "Screen Saver"), symbol: "sparkles.tv"),
            SystemSettingsPane("com.apple.Battery-Settings.extension", String(localized: "Battery"), symbol: "battery.75percent", keywords: ["energy", "power", "low power mode"]),
            SystemSettingsPane("com.apple.Lock-Screen-Settings.extension", String(localized: "Lock Screen"), symbol: "lock.display", keywords: ["screen saver", "password", "display off"]),
            SystemSettingsPane("com.apple.Touch-ID-Settings.extension", String(localized: "Touch ID & Password"), symbol: "touchid", keywords: ["fingerprint", "login password"]),
            SystemSettingsPane("com.apple.Users-Groups-Settings.extension", String(localized: "Users & Groups"), symbol: "person.2", keywords: ["accounts", "guest"]),
            SystemSettingsPane("com.apple.Passwords-Settings.extension", String(localized: "Passwords"), symbol: "key", keywords: ["keychain", "passkeys"]),
            SystemSettingsPane("com.apple.Internet-Accounts-Settings.extension", String(localized: "Internet Accounts"), symbol: "at", keywords: ["mail", "google", "exchange"]),
            SystemSettingsPane("com.apple.Game-Center-Settings.extension", String(localized: "Game Center"), symbol: "gamecontroller"),
            SystemSettingsPane("com.apple.WalletSettingsExtension", String(localized: "Wallet & Apple Pay"), symbol: "wallet.pass", keywords: ["apple pay", "cards"]),
            SystemSettingsPane("com.apple.Keyboard-Settings.extension", String(localized: "Keyboard"), symbol: "keyboard", keywords: ["shortcuts", "input sources", "dictation", "key repeat"]),
            SystemSettingsPane("com.apple.Trackpad-Settings.extension", String(localized: "Trackpad"), symbol: "rectangle.and.hand.point.up.left", keywords: ["gestures", "tap to click", "scroll"]),
            SystemSettingsPane("com.apple.Mouse-Settings.extension", String(localized: "Mouse"), symbol: "computermouse", keywords: ["scroll", "tracking speed"]),
            SystemSettingsPane("com.apple.Print-Scan-Settings.extension", String(localized: "Printers & Scanners"), symbol: "printer", keywords: ["print", "scan"]),
            SystemSettingsPane("com.apple.SystemProfiler.AboutExtension", String(localized: "About"), symbol: "info.circle", keywords: ["serial", "macos version", "this mac"], parent: general),
            SystemSettingsPane("com.apple.Software-Update-Settings.extension", String(localized: "Software Update"), symbol: "arrow.down.circle", keywords: ["update", "upgrade", "macos"], parent: general),
            SystemSettingsPane("com.apple.settings.Storage", String(localized: "Storage"), symbol: "internaldrive", keywords: ["disk", "space"], parent: general),
            SystemSettingsPane("com.apple.Date-Time-Settings.extension", String(localized: "Date & Time"), symbol: "clock", keywords: ["time zone", "clock"], parent: general),
            SystemSettingsPane("com.apple.Sharing-Settings.extension", String(localized: "Sharing"), symbol: "person.2.wave.2", keywords: ["file sharing", "screen sharing", "remote login", "ssh", "computer name"], parent: general),
            SystemSettingsPane("com.apple.Time-Machine-Settings.extension", String(localized: "Time Machine"), symbol: "clock.arrow.circlepath", keywords: ["backup"], parent: general),
            SystemSettingsPane("com.apple.Startup-Disk-Settings.extension", String(localized: "Startup Disk"), symbol: "externaldrive", parent: general),
            SystemSettingsPane("com.apple.LoginItems-Settings.extension", String(localized: "Login Items & Extensions"), symbol: "list.bullet", keywords: ["startup", "launch at login", "background items"], parent: general),
            SystemSettingsPane("com.apple.Localization-Settings.extension", String(localized: "Language & Region"), symbol: "globe", keywords: ["language", "region", "locale", "units"], parent: general),
            SystemSettingsPane("com.apple.AirDrop-Handoff-Settings.extension", String(localized: "AirDrop & Handoff"), symbol: "airplayaudio", keywords: ["airplay", "continuity"], parent: general),
            SystemSettingsPane("com.apple.Transfer-Reset-Settings.extension", String(localized: "Transfer or Reset"), symbol: "arrow.counterclockwise", keywords: ["erase", "migration"], parent: general),
            SystemSettingsPane("com.apple.preference.security?Privacy_Accessibility", String(localized: "Accessibility Access"), symbol: "accessibility", keywords: ["permission", "privacy accessibility"], parent: privacy),
            SystemSettingsPane("com.apple.preference.security?Privacy_ScreenCapture", String(localized: "Screen & System Audio Recording"), symbol: "rectangle.dashed.badge.record", keywords: ["permission", "screen recording"], parent: privacy),
            SystemSettingsPane("com.apple.preference.security?Privacy_ListenEvent", String(localized: "Input Monitoring"), symbol: "keyboard.badge.eye", keywords: ["permission", "keyboard"], parent: privacy),
            SystemSettingsPane("com.apple.preference.security?Privacy_Microphone", String(localized: "Microphone Access"), symbol: "mic", keywords: ["permission", "privacy microphone"], parent: privacy),
            SystemSettingsPane("com.apple.preference.security?Privacy_Camera", String(localized: "Camera Access"), symbol: "camera", keywords: ["permission", "privacy camera"], parent: privacy),
            SystemSettingsPane("com.apple.preference.security?Privacy_Automation", String(localized: "Automation"), symbol: "gearshape.2", keywords: ["permission", "apple events"], parent: privacy),
            SystemSettingsPane("com.apple.preference.security?Privacy_LocationServices", String(localized: "Location Services"), symbol: "location", keywords: ["permission", "gps"], parent: privacy),
            SystemSettingsPane("com.apple.preference.security?Privacy_AllFiles", String(localized: "Full Disk Access"), symbol: "lock.doc", keywords: ["permission", "files"], parent: privacy),
        ]
    }
}

/// System Settings panes. `/` lists them all.
@MainActor
final class SystemSettingsProvider: SearchProvider {
    static let prefixText = "/"

    let id = "systemSettings"
    let displayName = String(localized: "System Settings")
    let symbol = "gearshape"
    let prefix: String? = SystemSettingsProvider.prefixText
    private let panes = SystemSettingsPane.all

    func results(for query: SearchQuery) -> AsyncStream<[SearchResult]> {
        .single(Self.match(query.trimmed, scoped: query.isScoped, in: panes))
    }

    nonisolated static func match(_ text: String, scoped: Bool, in panes: [SystemSettingsPane]) -> [SearchResult] {
        if text.isEmpty {
            guard scoped else { return [] }
            return panes
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                .map { result(for: $0, score: 0.5) }
        }
        var results: [SearchResult] = []
        for pane in panes {
            guard let match = FuzzyMatch.score(text, title: pane.title, keywords: pane.keywords) else { continue }
            if !scoped, match < 0.6 {
                continue
            }
            // Below an app or command with the same name ("Displays", "Night Shift").
            results.append(result(for: pane, score: scoped ? match : match * 0.85))
        }
        results.sort { $0.score > $1.score }
        return Array(results.prefix(scoped ? 30 : 4))
    }

    nonisolated static func result(for pane: SystemSettingsPane, score: Double) -> SearchResult {
        let settings = String(localized: "System Settings")
        let subtitle = pane.parent.map { "\(settings) › \($0)" } ?? settings
        return SearchResult(
            id: "settings:\(pane.id)",
            title: pane.title,
            subtitle: subtitle,
            icon: .symbol(pane.symbol),
            score: score,
            kind: .url(pane.url),
            accessory: String(localized: "Settings"),
            actionTitle: String(localized: "Open")
        )
    }
}
