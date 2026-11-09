import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    let controller: ClipboardController
    let canPaste: Bool
    let openAccessibility: @MainActor () -> Void

    @Setting(ClipboardSettings.maxItems) private var maxItems
    @Setting(ClipboardSettings.retention) private var retention
    @Setting(ClipboardSettings.keepRichText) private var keepRichText
    @Setting(ClipboardSettings.keepImages) private var keepImages
    @Setting(ClipboardSettings.keepFiles) private var keepFiles
    @Setting(ClipboardSettings.ignoredApps) private var ignoredApps
    @Setting(ClipboardSettings.paused) private var paused
    @Setting(ClipboardSettings.clearOnQuit) private var clearOnQuit
    @Setting(ClipboardSettings.flashInIsland) private var flashInIsland
    @Setting(ClipboardSettings.pasteOnSelect) private var pasteOnSelect

    @State private var choosingApp = false
    @State private var confirmingClear = false
    @State private var selectedSnippet: Snippet.ID?

    var body: some View {
        Group {
            KKSection(
                String(localized: "History"),
                footer: String(localized: "Pinned items are kept whatever the limits. History stays on this Mac.")
            ) {
                Toggle(String(localized: "Pause recording"), isOn: $paused)
                Picker(String(localized: "Keep items for"), selection: $retention) {
                    ForEach(ClipboardRetention.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Stepper(value: $maxItems, in: 50...5000, step: 50) {
                    LabeledContent(String(localized: "At most"), value: String(localized: "\(maxItems) items"))
                }
                Toggle(String(localized: "Clear history when KKit quits or this is turned off"), isOn: $clearOnQuit)
                KKRow(String(localized: "\(controller.itemCount) items saved"), symbol: "list.clipboard") {
                    Button(String(localized: "Clear History…"), role: .destructive) {
                        confirmingClear = true
                    }
                }
            }
            KKSection(String(localized: "Save"), footer: String(localized: "Plain text and links are always saved.")) {
                Toggle(String(localized: "Formatting (rich text)"), isOn: $keepRichText)
                Toggle(String(localized: "Images"), isOn: $keepImages)
                Toggle(String(localized: "Files"), isOn: $keepFiles)
            }
            KKSection(
                String(localized: "Pasting"),
                footer: canPaste
                    ? String(localized: "Open the picker with its shortcut (⇧⌘V by default) or type “c ” in the Floating Bar.")
                    : String(localized: "Without Accessibility, choosing an item only copies it.")
            ) {
                Toggle(String(localized: "Paste into the app in front"), isOn: $pasteOnSelect)
                if !canPaste {
                    KKRow(String(localized: "Accessibility is off"), symbol: "accessibility") {
                        Button(String(localized: "Open System Settings")) { openAccessibility() }
                    }
                }
                Toggle(String(localized: "Flash “Copied” in the Island"), isOn: $flashInIsland)
            }
            KKSection(
                String(localized: "Ignored Apps"),
                footer: String(localized: "Copies made in these apps are never saved. Apps that mark copies as passwords are always skipped.")
            ) {
                ForEach(ignoredApps, id: \.self) { bundleID in
                    KKRow(Self.appName(for: bundleID), subtitle: bundleID, symbol: "nosign") {
                        Button {
                            ignoredApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button(String(localized: "Add App…")) {
                    choosingApp = true
                }
            }
            snippets
        }
        .fileImporter(isPresented: $choosingApp, allowedContentTypes: [.application]) { result in
            guard case .success(let url) = result, let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            if !ignoredApps.contains(bundleID) {
                ignoredApps.append(bundleID)
            }
        }
        .confirmationDialog(
            String(localized: "Clear clipboard history?"),
            isPresented: $confirmingClear
        ) {
            Button(String(localized: "Clear, Keep Pinned"), role: .destructive) {
                Task { await controller.clear(keepPinned: true) }
            }
            Button(String(localized: "Clear Everything"), role: .destructive) {
                Task { await controller.clear(keepPinned: false) }
            }
        }
    }

    private var snippets: some View {
        KKSection(
            String(localized: "Snippets"),
            footer: String(localized: "Paste them from the picker's Snippets filter or “c ” search. Placeholders: \(SnippetExpander.help)")
        ) {
            ForEach(controller.snippets) { snippet in
                SnippetEditor(snippet: snippet, controller: controller)
            }
            Button(String(localized: "Add Snippet")) {
                controller.addSnippet()
            }
        }
    }

    static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// One snippet's name, keyword and text.
private struct SnippetEditor: View {
    let snippet: Snippet
    let controller: ClipboardController

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.xs) {
            HStack {
                TextField(String(localized: "Name"), text: binding(.name))
                TextField(String(localized: "Keyword"), text: binding(.keyword))
                    .frame(width: 110)
                Button {
                    controller.removeSnippet(snippet.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Delete snippet"))
            }
            TextEditor(text: binding(.text))
                .font(.system(.body, design: .monospaced))
                .frame(height: 54)
        }
        .padding(.vertical, KKSpacing.xxs)
    }

    private enum Field: Sendable {
        case name, keyword, text
    }

    private func binding(_ field: Field) -> Binding<String> {
        let controller = controller
        let id = snippet.id
        return Binding(
            get: {
                guard let current = controller.snippets.first(where: { $0.id == id }) else { return "" }
                switch field {
                case .name: return current.name
                case .keyword: return current.keyword
                case .text: return current.text
                }
            },
            set: { newValue in
                guard var current = controller.snippets.first(where: { $0.id == id }) else { return }
                switch field {
                case .name: current.name = newValue
                case .keyword: current.keyword = newValue
                case .text: current.text = newValue
                }
                controller.updateSnippet(current)
            }
        )
    }
}
