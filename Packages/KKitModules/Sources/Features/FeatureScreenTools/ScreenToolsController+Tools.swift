import AppKit
import Foundation
import KKitCore
import KKitServicesAPI
import SwiftUI

// MARK: Text and codes

extension ScreenToolsController {
    /// Select an area → its text is copied and shown in the Island.
    func captureText() async throws {
        try await ensureScreenRecording()
        guard let picked = await pickTarget(.area, prompt: String(localized: "Select the text to copy")) else { return }
        let capture = try await context.screenCapture.capture(picked.target, showsCursor: false)
        await recognize(capture)
    }

    func recognize(_ capture: CapturedImage) async {
        do {
            let lines = try await ImageAnalyzer.recognizeText(in: capture, language: settings[ScreenToolsSettings.ocrLanguage])
            let text = ImageAnalyzer.text(from: lines)
            guard !text.isEmpty else {
                notice(.noText)
                return
            }
            context.pasteboard.copy(text)
            recognizedText = text
            presentText(text)
        } catch {
            problem(error)
        }
    }

    private func presentText(_ text: String) {
        let words = ImageAnalyzer.wordCount(text)
        let activity = IslandActivity(
            id: Self.textActivity,
            title: String(localized: "Text"),
            symbol: "text.viewfinder",
            priority: .high,
            compactLeading: AnyView(Image(systemName: "text.viewfinder").foregroundStyle(.white)),
            compactTrailing: AnyView(Text(String(localized: "\(words) words")).foregroundStyle(.white)),
            expanded: AnyView(RecognizedTextPage(controller: self))
        )
        presentResult(activity, seconds: 6, expand: false)
    }

    /// Select an area → the QR code or barcode in it is copied (and opened if it's a link
    /// and the setting says so).
    func scanCode() async throws {
        try await ensureScreenRecording()
        guard let picked = await pickTarget(.area, prompt: String(localized: "Select a QR code or barcode")) else { return }
        let capture = try await context.screenCapture.capture(picked.target, showsCursor: false)
        await scan([capture])
    }

    /// Looks for codes on every screen.
    func scanScreens() async throws {
        try await ensureScreenRecording()
        var captures: [CapturedImage] = []
        for screen in context.overlays.screens {
            captures.append(try await context.screenCapture.capture(.display(screen.id), showsCursor: false))
        }
        await scan(captures)
    }

    func scan(_ captures: [CapturedImage]) async {
        do {
            var codes: [String] = []
            for capture in captures {
                for code in try await ImageAnalyzer.detectCodes(in: capture) where !codes.contains(code) {
                    codes.append(code)
                }
            }
            guard let first = codes.first else {
                notice(.noCode)
                return
            }
            scannedCodes = codes
            context.pasteboard.copy(codes.joined(separator: "\n"))
            if let url = Self.link(in: first), settings[ScreenToolsSettings.openScannedLinks] {
                NSWorkspace.shared.open(url)
            }
            presentCodes(codes)
        } catch {
            problem(error)
        }
    }

    private func presentCodes(_ codes: [String]) {
        let isLink = codes.first.flatMap(Self.link(in:)) != nil
        let activity = IslandActivity(
            id: Self.codeActivity,
            title: String(localized: "Scanned Code"),
            symbol: "qrcode.viewfinder",
            priority: .high,
            compactLeading: AnyView(Image(systemName: "qrcode").foregroundStyle(.white)),
            compactTrailing: AnyView(
                Text(isLink ? String(localized: "Link copied") : String(localized: "Copied"))
                    .foregroundStyle(.white)
            ),
            expanded: AnyView(ScannedCodesPage(controller: self))
        )
        presentResult(activity, seconds: 8, expand: true)
    }

    /// A web, mail or other link a scanned payload holds.
    nonisolated static func link(in payload: String) -> URL? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        let schemes: Set<String> = ["http", "https", "mailto", "tel", "sms", "facetime", "maps", "geo"]
        guard schemes.contains(scheme) else { return nil }
        if scheme.hasPrefix("http"), url.host == nil { return nil }
        return url
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        dismissResult(Self.codeActivity)
    }
}

// MARK: Translation

extension ScreenToolsController {
    /// Select an area → its text is translated in a floating card.
    func translateArea() async throws {
        try await ensureScreenRecording()
        guard let picked = await pickTarget(.area, prompt: String(localized: "Select the text to translate")) else { return }
        let capture = try await context.screenCapture.capture(picked.target, showsCursor: false)
        let lines = try await ImageAnalyzer.recognizeText(in: capture, language: settings[ScreenToolsSettings.ocrLanguage])
        // Lines in a paragraph translate better joined.
        showTranslation(of: lines.joined(separator: " "), near: picked.rect)
    }

    func translateClipboard() {
        showTranslation(of: context.pasteboard.read().string ?? "", near: nil)
    }

    /// Opens the translation card. It translates on-device (macOS 15).
    func showTranslation(of text: String, near rect: CGRect?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            notice(.nothingToTranslate)
            return
        }
        translationPanel?.close()
        let model = TranslationModel(source: trimmed, target: settings[ScreenToolsSettings.translateTarget])
        let settings = settings
        model.onTargetChange = { settings[ScreenToolsSettings.translateTarget] = $0 }
        let card = TranslationCard(
            model: model,
            copy: { [weak self] text in
                self?.context.pasteboard.copy(text)
                self?.context.island.showHUD(IslandHUD(id: "screenTools.copied", symbol: "doc.on.doc", detail: String(localized: "Copied"), duration: 1))
            },
            close: { [weak self] in
                self?.translationPanel?.close()
                self?.translationPanel = nil
            }
        )
        let size = TranslationCard.size
        let placement: OverlayPlacement = if let rect {
            // Under the selection, or above it when there's no room.
            .frame(CGRect(
                x: rect.midX - size.width / 2,
                y: rect.minY - size.height - 12 > 0 ? rect.minY - size.height - 12 : rect.maxY + 12,
                width: size.width,
                height: size.height
            ))
        } else {
            .topCenter(size: size, offset: 60)
        }
        let panel = context.overlays.makePanel(
            OverlayConfiguration(level: .floating, screen: .withCursor, placement: placement, acceptsKeyFocus: true, isMovable: true),
            content: AnyView(card)
        )
        translationPanel = panel
        panel.show()
    }
}

// MARK: Recording

enum RecordingMode: Sendable {
    case area, window, screen

    var style: RegionPickerStyle {
        switch self {
        case .area: .area
        case .window: .window
        case .screen: .screen
        }
    }
}

extension ScreenToolsController {
    var isRecording: Bool { recording != nil }

    func startRecording(_ mode: RecordingMode) async throws {
        guard recording == nil else { throw ScreenToolsError.alreadyRecording }
        guard context.screenCapture.supportsRecording else { throw ScreenToolsError.recordingUnsupported }
        try await ensureScreenRecording()
        let microphone = settings[ScreenToolsSettings.recordMicrophone]
        if microphone, context.permissions.status(of: .microphone) != .granted,
           await context.permissions.request(.microphone) != .granted {
            throw ScreenToolsError.microphoneDenied
        }
        let prompt = String(localized: "Choose what to record. Press Stop in the Island to finish.")
        guard let picked = await pickTarget(mode.style, prompt: prompt) else { return }
        let options = RecordingOptions(
            capturesSystemAudio: settings[ScreenToolsSettings.recordSystemAudio],
            capturesMicrophone: microphone,
            showsCursor: true,
            showsClicks: settings[ScreenToolsSettings.showClicks],
            framesPerSecond: settings[ScreenToolsSettings.recordFPS]
        )
        let folder = saveFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = CaptureFileNamer.name(pattern: settings[ScreenToolsSettings.recordingNamePattern], date: now())
        let url = CaptureFileNamer.uniqueURL(in: folder, name: name, fileExtension: "mp4") {
            FileManager.default.fileExists(atPath: $0.path)
        }
        let recording = try await context.screenCapture.startRecording(picked.target, options: options, to: url)
        recording.onInterrupted = { [weak self] error in
            guard let self else { return }
            self.problem(error)
            Task { await self.stopRecording() }
        }
        self.recording = recording
        presentRecording(recording)
    }

    func stopRecording() async {
        guard let recording else { return }
        self.recording = nil
        recordingHandle?.dismiss()
        recordingHandle = nil
        do {
            let url = try await recording.stop()
            lastRecordingURL = url
            presentRecordingSaved()
        } catch {
            problem(error)
        }
    }

    private func presentRecording(_ recording: any ScreenRecording) {
        let startedAt = recording.startedAt
        let activity = IslandActivity(
            id: Self.recordingActivity,
            title: String(localized: "Recording"),
            symbol: "record.circle",
            priority: .critical,
            compactLeading: AnyView(RecordingDot()),
            compactTrailing: AnyView(ElapsedTime(since: startedAt)),
            expanded: AnyView(RecordingPage(controller: self, startedAt: startedAt))
        )
        recordingHandle = context.island.present(activity)
    }

    private func presentRecordingSaved() {
        let activity = IslandActivity(
            id: Self.recordingDoneActivity,
            title: String(localized: "Recording"),
            symbol: "film",
            priority: .high,
            compactLeading: AnyView(Image(systemName: "film").foregroundStyle(.white)),
            compactTrailing: AnyView(Text(String(localized: "Saved")).foregroundStyle(.white)),
            expanded: AnyView(RecordingSavedPage(controller: self))
        )
        presentResult(activity, seconds: settings[ScreenToolsSettings.thumbnailSeconds], expand: true)
    }
}
