import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI
import UniformTypeIdentifiers

struct ScreenToolsSettingsView: View {
    let controller: ScreenToolsController
    let permissions: any PermissionsService
    let supportsRecording: Bool

    @Setting(ScreenToolsSettings.saveFolder) private var saveFolder
    @Setting(ScreenToolsSettings.fileNamePattern) private var fileNamePattern
    @Setting(ScreenToolsSettings.format) private var format
    @Setting(ScreenToolsSettings.jpegQuality) private var jpegQuality
    @Setting(ScreenToolsSettings.copyAfterCapture) private var copyAfterCapture
    @Setting(ScreenToolsSettings.saveAfterCapture) private var saveAfterCapture
    @Setting(ScreenToolsSettings.showInIsland) private var showInIsland
    @Setting(ScreenToolsSettings.thumbnailSeconds) private var thumbnailSeconds
    @Setting(ScreenToolsSettings.showCursor) private var showCursor
    @Setting(ScreenToolsSettings.timerSeconds) private var timerSeconds
    @Setting(ScreenToolsSettings.ocrLanguage) private var ocrLanguage
    @Setting(ScreenToolsSettings.openScannedLinks) private var openScannedLinks
    @Setting(ScreenToolsSettings.translateTarget) private var translateTarget
    @Setting(ScreenToolsSettings.recordSystemAudio) private var recordSystemAudio
    @Setting(ScreenToolsSettings.recordMicrophone) private var recordMicrophone
    @Setting(ScreenToolsSettings.showClicks) private var showClicks
    @Setting(ScreenToolsSettings.recordFPS) private var recordFPS

    @State private var choosingFolder = false
    @State private var languages: [String] = []

    var body: some View {
        Group {
            if !permissions.status(of: .screenRecording).isGranted {
                KKSection(footer: String(localized: "Screenshots, text and code scanning, translating an area and recording all need it. You may need to quit and reopen KKit after turning it on.")) {
                    KKRow(String(localized: "Screen Recording is off"), symbol: "rectangle.dashed.badge.record") {
                        Button(String(localized: "Open System Settings")) { permissions.openSystemSettings(for: .screenRecording) }
                    }
                }
            }
            screenshots
            KKSection(
                String(localized: "Text and Codes"),
                footer: String(localized: "Recognition and scanning run on this Mac.")
            ) {
                Picker(String(localized: "Text language"), selection: $ocrLanguage) {
                    Text("Detect automatically").tag("")
                    ForEach(languages, id: \.self) { code in
                        Text(Locale.current.localizedString(forIdentifier: code) ?? code).tag(code)
                    }
                }
                Toggle(String(localized: "Open scanned links straight away"), isOn: $openScannedLinks)
                Picker(String(localized: "Translate into"), selection: $translateTarget) {
                    ForEach(TranslationLanguage.common) { language in
                        Text(language.name).tag(language.id)
                    }
                }
            }
            recording
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                saveFolder = url.path
            }
        }
        .task {
            languages = ImageAnalyzer.supportedLanguages()
        }
    }

    private var screenshots: some View {
        KKSection(
            String(localized: "Screenshots"),
            footer: String(localized: "Put date formats in braces: {yyyy-MM-dd}, {HH.mm.ss}. Next: \(CaptureFileNamer.name(pattern: fileNamePattern, date: Date())).\(format.fileExtension)")
        ) {
            KKRow(String(localized: "Save to"), subtitle: controller.saveFolder().path, symbol: "folder") {
                HStack {
                    Button(String(localized: "Choose…")) { choosingFolder = true }
                    if !saveFolder.isEmpty {
                        Button(String(localized: "Desktop")) { saveFolder = "" }
                    }
                }
            }
            TextField(String(localized: "File name"), text: $fileNamePattern)
            Picker(String(localized: "Format"), selection: $format) {
                ForEach(ImageFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            if format != .png {
                LabeledContent(String(localized: "Quality")) {
                    Slider(value: $jpegQuality, in: 0.3...1)
                        .frame(width: 180)
                }
            }
            Toggle(String(localized: "Copy to the clipboard"), isOn: $copyAfterCapture)
            Toggle(String(localized: "Save to the folder"), isOn: $saveAfterCapture)
            Toggle(String(localized: "Show in the Island"), isOn: $showInIsland)
            if showInIsland {
                Stepper(value: $thumbnailSeconds, in: 3...30, step: 1) {
                    LabeledContent(String(localized: "Keep it there for"), value: String(localized: "\(Int(thumbnailSeconds)) s"))
                }
            }
            Toggle(String(localized: "Include the pointer"), isOn: $showCursor)
            Stepper(value: $timerSeconds, in: 1...30) {
                LabeledContent(String(localized: "Timed screenshot after"), value: String(localized: "\(timerSeconds) s"))
            }
        }
    }

    private var recording: some View {
        KKSection(
            String(localized: "Recording"),
            footer: supportsRecording
                ? String(localized: "Recordings are saved as MP4 in the same folder. Stop them from the Island.")
                : String(localized: "Screen recording needs macOS 15 or later.")
        ) {
            Toggle(String(localized: "Record system audio"), isOn: $recordSystemAudio)
            Toggle(String(localized: "Record the microphone"), isOn: $recordMicrophone)
            Toggle(String(localized: "Highlight clicks"), isOn: $showClicks)
            Picker(String(localized: "Frame rate"), selection: $recordFPS) {
                Text("30 fps").tag(30)
                Text("60 fps").tag(60)
            }
        }
        .disabled(!supportsRecording)
    }
}
