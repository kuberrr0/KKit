import AppKit
import KKitCore
import KKitUI
import SwiftUI

enum SearchSettings {
    /// Show a few files in root search (three letters or more).
    static let filesInRoot = SettingKey("filesInRoot", default: true)
    /// Search browser bookmarks.
    static let bookmarks = SettingKey("bookmarks", default: true)
    /// A `SearchEngine.id`.
    static let defaultEngine = SettingKey("defaultEngine", default: "google")
    /// The path of the browser for web results; empty for the default browser.
    static let browser = SettingKey("browser", default: "")
    /// "Search Google for …" as the last row of every root search.
    static let webFallback = SettingKey("webFallback", default: true)
}

struct SearchSettingsView: View {
    @Setting(SearchSettings.filesInRoot) private var filesInRoot
    @Setting(SearchSettings.bookmarks) private var bookmarks
    @Setting(SearchSettings.defaultEngine) private var defaultEngine
    @Setting(SearchSettings.browser) private var browser
    @Setting(SearchSettings.webFallback) private var webFallback

    @State private var browsers: [URL] = []

    var body: some View {
        Group {
            KKSection(
                String(localized: "Files"),
                footer: String(localized: "Type “f ” to search only files. Spotlight finds files in your home folder; no permission is needed.")
            ) {
                Toggle(String(localized: "Show files in every search"), isOn: $filesInRoot)
            }
            KKSection(
                String(localized: "Web"),
                footer: String(localized: "Type “w ” to search the web, or an engine's keyword first: “yt lofi”, “gh kkit”, “wiki macOS”. Safari bookmarks need Full Disk Access.")
            ) {
                Picker(String(localized: "Search engine"), selection: $defaultEngine) {
                    ForEach(SearchEngine.all) { engine in
                        Text("\(engine.name) (\(engine.keyword))").tag(engine.id)
                    }
                }
                Picker(String(localized: "Open web results in"), selection: $browser) {
                    Text("Default browser").tag("")
                    ForEach(browsers, id: \.path) { app in
                        Text(app.deletingPathExtension().lastPathComponent).tag(app.path)
                    }
                }
                Toggle(String(localized: "Offer a web search when nothing else matches"), isOn: $webFallback)
                Toggle(String(localized: "Search browser bookmarks"), isOn: $bookmarks)
            }
        }
        .onAppear {
            browsers = WebProvider.browsers()
        }
    }
}
