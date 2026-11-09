import KKitCore
import KKitUI
import SwiftUI
import UniformTypeIdentifiers

enum QuickNoteSettings {
    static let defaults = NoteConfiguration()

    /// The vault folder's path, and a bookmark that finds it if it moves.
    static let vaultPath = SettingKey("vaultPath", default: "")
    static let vaultBookmark = SettingKey("vaultBookmark", default: Data())
    static let defaultTarget = SettingKey("defaultTarget", default: NoteTargetKind.inbox)
    static let inboxPath = SettingKey("inboxPath", default: defaults.inboxPath)
    static let inboxHeading = SettingKey("inboxHeading", default: defaults.inboxHeading)
    static let dailyPattern = SettingKey("dailyPattern", default: defaults.dailyPattern)
    static let dailyTemplate = SettingKey("dailyTemplate", default: defaults.dailyTemplate)
    static let dailyHeading = SettingKey("dailyHeading", default: defaults.dailyHeading)
    static let newNoteFolder = SettingKey("newNoteFolder", default: defaults.newNoteFolder)
    static let newNoteTemplate = SettingKey("newNoteTemplate", default: defaults.newNoteTemplate)
    static let entryTemplate = SettingKey("entryTemplate", default: defaults.entryTemplate)
    static let timeFormat = SettingKey("timeFormat", default: defaults.timeFormat)
    /// Add "(from Safari)": the app that was in front.
    static let includeContext = SettingKey("includeContext", default: defaults.includeContext)
    /// Open the note in Obsidian after every save (⌘⇧↵ does it once).
    static let openAfterSave = SettingKey("openAfterSave", default: false)
}

struct QuickNoteSettingsView: View {
    let controller: QuickNoteController

    @Setting(QuickNoteSettings.vaultPath) private var vaultPath
    @Setting(QuickNoteSettings.defaultTarget) private var defaultTarget
    @Setting(QuickNoteSettings.inboxPath) private var inboxPath
    @Setting(QuickNoteSettings.inboxHeading) private var inboxHeading
    @Setting(QuickNoteSettings.dailyPattern) private var dailyPattern
    @Setting(QuickNoteSettings.dailyTemplate) private var dailyTemplate
    @Setting(QuickNoteSettings.dailyHeading) private var dailyHeading
    @Setting(QuickNoteSettings.newNoteFolder) private var newNoteFolder
    @Setting(QuickNoteSettings.newNoteTemplate) private var newNoteTemplate
    @Setting(QuickNoteSettings.entryTemplate) private var entryTemplate
    @Setting(QuickNoteSettings.timeFormat) private var timeFormat
    @Setting(QuickNoteSettings.includeContext) private var includeContext
    @Setting(QuickNoteSettings.openAfterSave) private var openAfterSave

    @State private var choosingVault = false

    var body: some View {
        Group {
            KKSection(
                String(localized: "Vault"),
                footer: String(localized: "Your Obsidian vault, or any folder of markdown files. Notes are written straight to disk; Obsidian picks them up.")
            ) {
                KKRow(vaultPath.isEmpty ? String(localized: "No vault chosen") : vaultPath, symbol: "folder") {
                    Button(vaultPath.isEmpty ? String(localized: "Choose…") : String(localized: "Change…")) {
                        choosingVault = true
                    }
                }
                Picker(String(localized: "Save to"), selection: $defaultTarget) {
                    ForEach(NoteTargetKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }
            KKSection(
                String(localized: "Inbox"),
                footer: String(localized: "A file in the vault. With a heading, notes go at the end of that section (it's added if missing).")
            ) {
                TextField(String(localized: "File"), text: $inboxPath, prompt: Text(verbatim: "Inbox.md"))
                TextField(String(localized: "Under heading"), text: $inboxHeading, prompt: Text("Optional"))
            }
            KKSection(
                String(localized: "Daily Note"),
                footer: String(localized: "Date formats go in braces: {yyyy}/{MM}/{yyyy-MM-dd}. A missing note is created from the template.")
            ) {
                TextField(String(localized: "Path"), text: $dailyPattern, prompt: Text(verbatim: QuickNoteSettings.defaults.dailyPattern))
                TextField(String(localized: "Under heading"), text: $dailyHeading, prompt: Text("Optional"))
                LabeledContent(String(localized: "Template")) {
                    TextEditor(text: $dailyTemplate)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 60)
                }
            }
            KKSection(String(localized: "New Note"), footer: String(localized: "The first line becomes the title and the file name.")) {
                TextField(String(localized: "Folder"), text: $newNoteFolder, prompt: Text(verbatim: "Notes"))
                LabeledContent(String(localized: "Template")) {
                    TextEditor(text: $newNoteTemplate)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 60)
                }
            }
            KKSection(
                String(localized: "Entries"),
                footer: String(localized: "For the inbox and daily note. Placeholders: {{time}}, {{date}}, {{text}}, {{app}}.")
            ) {
                TextField(String(localized: "Entry"), text: $entryTemplate, prompt: Text(verbatim: QuickNoteSettings.defaults.entryTemplate))
                TextField(String(localized: "Time format"), text: $timeFormat, prompt: Text(verbatim: "HH:mm"))
                Toggle(String(localized: "Note which app was in front"), isOn: $includeContext)
                Toggle(String(localized: "Open in Obsidian after saving"), isOn: $openAfterSave)
            }
        }
        .fileImporter(isPresented: $choosingVault, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                controller.setVault(url)
            }
        }
    }
}
