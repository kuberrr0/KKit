import AppKit
import Foundation
import KKitCore
import KKitServicesAPI
import SwiftUI
import UniformTypeIdentifiers

/// A screenshot after capture. There's always a file: the save folder when saving is
/// on, otherwise a temporary one, so it can be dragged out, shelved or edited.
struct Screenshot: Identifiable {
    let id = UUID()
    let capture: CapturedImage
    let date: Date
    var fileURL: URL
    /// Saved in the save folder (not just the temporary file).
    var isSaved: Bool
    var isCopied: Bool
    /// Where it was on screen (global, bottom-left origin), so a pin opens in place.
    let sourceRect: CGRect?
}

/// What a capture command asks the user to pick.
enum CaptureMode: Sendable, Equatable {
    case area
    case window
    case screen
    /// Pick an area or window, then wait `timerSeconds`.
    case timed
}

/// Soft failures, shown in the Island rather than as errors.
enum ScreenToolsNotice {
    case noText
    case noCode
    case nothingToTranslate

    var message: String {
        switch self {
        case .noText: String(localized: "No text found")
        case .noCode: String(localized: "No QR code or barcode found")
        case .nothingToTranslate: String(localized: "Nothing to translate")
        }
    }
}

enum ScreenToolsError: LocalizedError {
    case recordingUnsupported
    case alreadyRecording
    case microphoneDenied

    var errorDescription: String? {
        switch self {
        case .recordingUnsupported: String(localized: "Screen recording needs macOS 15 or later.")
        case .alreadyRecording: String(localized: "A recording is already running.")
        case .microphoneDenied: String(localized: "KKit needs Microphone permission to record your voice.")
        }
    }
}

/// Screenshots, text and code scanning, translation and recording.
/// The commands call into this; the Island pages and the settings pane read it.
@MainActor
@Observable
final class ScreenToolsController {
    let context: FeatureContext
    var settings: FeatureSettings { context.settings }

    /// The newest screenshot, shown on the Island's screenshot page.
    var latest: Screenshot?
    /// Recognised text and scanned codes from the last scan.
    var recognizedText: String?
    var scannedCodes: [String] = []
    /// The recording in progress.
    var recording: (any ScreenRecording)?
    /// The last finished recording.
    var lastRecordingURL: URL?

    /// A picker or capture is on screen; a second command waits its turn.
    @ObservationIgnored private var isPicking = false
    @ObservationIgnored private var resultHandles: [String: any IslandHandle] = [:]
    @ObservationIgnored private var resultTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var pins: [UUID: any OverlayHandle] = [:]
    @ObservationIgnored var translationPanel: (any OverlayHandle)?
    @ObservationIgnored var recordingHandle: (any IslandHandle)?

    /// Overridable for tests.
    @ObservationIgnored var now: @MainActor () -> Date = { Date() }
    @ObservationIgnored var temporaryFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("KKit Screenshots", isDirectory: true)

    init(context: FeatureContext) {
        self.context = context
    }

    /// Closes pins, cards and Island results (the feature stopped).
    func tearDown() async {
        for task in resultTasks.values { task.cancel() }
        resultTasks = [:]
        for handle in resultHandles.values { handle.dismiss() }
        resultHandles = [:]
        for pin in pins.values { pin.close() }
        pins = [:]
        translationPanel?.close()
        translationPanel = nil
        if let recording {
            _ = try? await recording.stop()
            self.recording = nil
        }
        recordingHandle?.dismiss()
        recordingHandle = nil
    }

    // MARK: Picking

    func ensureScreenRecording() async throws {
        let permissions = context.permissions
        guard permissions.status(of: .screenRecording) != .granted else { return }
        if await permissions.request(.screenRecording) != .granted {
            throw CaptureError.permissionDenied
        }
    }

    /// Asks the user for an area, window or screen. `nil` when they cancel.
    func pickTarget(_ style: RegionPickerStyle, prompt: String?) async -> (target: CaptureTarget, rect: CGRect?)? {
        guard !isPicking else { return nil }
        isPicking = true
        defer { isPicking = false }
        guard let selection = await context.overlays.pickRegion(RegionPickerOptions(style: style, prompt: prompt)) else {
            return nil
        }
        let target = Self.target(for: selection, style: style)
        if case .display = target { return (target, nil) }
        return (target, selection.rect)
    }

    static func target(for selection: RegionSelection, style: RegionPickerStyle) -> CaptureTarget {
        if let window = selection.windowID { return .window(window) }
        if style == .screen { return .display(selection.displayID) }
        return .area(displayID: selection.displayID, rect: selection.rect)
    }

    // MARK: Screenshots

    func screenshot(_ mode: CaptureMode) async throws {
        try await ensureScreenRecording()
        let style: RegionPickerStyle = switch mode {
        case .area, .timed: .area
        case .window: .window
        case .screen: .screen
        }
        let seconds = settings[ScreenToolsSettings.timerSeconds]
        let prompt: String? = mode == .timed
            ? String(localized: "Choose what to capture in \(seconds) seconds. Space switches between area and window.")
            : nil
        guard let picked = await pickTarget(style, prompt: prompt) else { return }
        if mode == .timed {
            await countDown(seconds)
        }
        let capture = try await context.screenCapture.capture(picked.target, showsCursor: settings[ScreenToolsSettings.showCursor])
        try await finish(capture, sourceRect: picked.rect)
    }

    private func countDown(_ seconds: Int) async {
        for remaining in stride(from: max(seconds, 0), to: 0, by: -1) {
            context.island.showHUD(IslandHUD(
                id: "screenTools.timer",
                symbol: "timer",
                title: String(localized: "Screenshot in \(remaining)"),
                duration: 1.1
            ))
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Copies, saves and shows a capture as the settings say.
    func finish(_ capture: CapturedImage, sourceRect: CGRect?) async throws {
        let date = now()
        let shouldSave = settings[ScreenToolsSettings.saveAfterCapture]
        let folder = shouldSave ? saveFolder() : temporaryFolder
        let url = try await write(capture, to: folder, date: date)
        var shot = Screenshot(capture: capture, date: date, fileURL: url, isSaved: shouldSave, isCopied: false, sourceRect: sourceRect)
        if settings[ScreenToolsSettings.copyAfterCapture] {
            try await copyImage(capture)
            shot.isCopied = true
        }
        latest = shot
        if shouldSave {
            context.events.publish(.screenshotCaptured(url))
        }
        if settings[ScreenToolsSettings.showInIsland] {
            presentScreenshot(shot)
        } else if shot.isCopied || shouldSave {
            context.island.showHUD(IslandHUD(
                id: "screenTools.captured",
                symbol: "camera.viewfinder",
                title: shouldSave ? String(localized: "Screenshot saved") : String(localized: "Screenshot copied")
            ))
        }
    }

    func saveFolder() -> URL {
        let path = settings[ScreenToolsSettings.saveFolder]
        if !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Encodes and writes the capture off the main actor.
    private func write(_ capture: CapturedImage, to folder: URL, date: Date) async throws -> URL {
        let format = settings[ScreenToolsSettings.format]
        let quality = settings[ScreenToolsSettings.jpegQuality]
        let name = CaptureFileNamer.name(pattern: settings[ScreenToolsSettings.fileNamePattern], date: date)
        return try await Task.detached(priority: .userInitiated) {
            let data = try ImageEncoder.encode(capture, as: format, quality: quality)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = CaptureFileNamer.uniqueURL(in: folder, name: name, fileExtension: format.fileExtension) {
                FileManager.default.fileExists(atPath: $0.path)
            }
            try data.write(to: url, options: .withoutOverwriting)
            return url
        }.value
    }

    func copyImage(_ capture: CapturedImage) async throws {
        let png = try await Task.detached(priority: .userInitiated) { try ImageEncoder.png(capture) }.value
        context.pasteboard.write(PasteboardContents(image: png, imageType: UTType.png.identifier, types: [UTType.png.identifier]))
    }

    // MARK: Screenshot actions (the Island page)

    func copy(_ shot: Screenshot) async {
        do {
            try await copyImage(shot.capture)
            update(shot.id) { $0.isCopied = true }
            context.island.showHUD(IslandHUD(id: "screenTools.copied", symbol: "doc.on.doc", detail: String(localized: "Copied"), duration: 1))
        } catch {
            problem(error)
        }
    }

    /// Moves the temporary file into the save folder.
    func save(_ shot: Screenshot) async {
        guard !shot.isSaved else { return }
        let folder = saveFolder()
        let source = shot.fileURL
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = source.deletingPathExtension().lastPathComponent
                let destination = CaptureFileNamer.uniqueURL(in: folder, name: name, fileExtension: source.pathExtension) {
                    FileManager.default.fileExists(atPath: $0.path)
                }
                try FileManager.default.moveItem(at: source, to: destination)
                return destination
            }.value
            update(shot.id) {
                $0.fileURL = url
                $0.isSaved = true
            }
            context.events.publish(.screenshotCaptured(url))
        } catch {
            problem(error)
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens the file in Preview to mark it up.
    func edit(_ shot: Screenshot) {
        let url = shot.fileURL
        if let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
            NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
        dismissResult(Self.screenshotActivity)
    }

    var canShelve: Bool {
        context.services.resolve((any ShelfServicing).self) != nil
    }

    var canSendToNote: Bool {
        context.services.resolve((any QuickNoteServicing).self) != nil
    }

    func shelve(_ items: [DroppedItem]) async {
        guard let shelf = context.services.resolve((any ShelfServicing).self) else { return }
        do {
            try await shelf.add(items)
            context.island.showHUD(IslandHUD(id: "screenTools.shelved", symbol: "tray.and.arrow.down.fill", detail: String(localized: "On the Shelf"), duration: 1))
        } catch {
            problem(error)
        }
    }

    func sendToNote(_ text: String) {
        context.services.resolve((any QuickNoteServicing).self)?.openEditor(with: text)
    }

    /// Recognises the text in a screenshot that's already taken.
    func recognizeText(in shot: Screenshot) async {
        await recognize(shot.capture)
    }

    func dismissScreenshot() {
        dismissResult(Self.screenshotActivity)
    }

    private func update(_ id: Screenshot.ID, _ change: (inout Screenshot) -> Void) {
        guard var shot = latest, shot.id == id else { return }
        change(&shot)
        latest = shot
    }

    // MARK: Island results

    static let screenshotActivity = "screenshot"
    static let textActivity = "text"
    static let codeActivity = "code"
    static let recordingActivity = "recording"
    static let recordingDoneActivity = "recordingSaved"

    private func presentScreenshot(_ shot: Screenshot) {
        let controller = self
        let image = shot.capture
        let activity = IslandActivity(
            id: Self.screenshotActivity,
            title: String(localized: "Screenshot"),
            symbol: "camera.viewfinder",
            priority: .high,
            compactLeading: AnyView(
                Image(decorative: image.image, scale: image.scale)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            ),
            compactTrailing: AnyView(
                Text(shot.isSaved ? String(localized: "Saved") : shot.isCopied ? String(localized: "Copied") : String(localized: "Ready"))
                    .foregroundStyle(.white)
            ),
            expanded: AnyView(ScreenshotPage(controller: controller))
        )
        presentResult(activity, seconds: settings[ScreenToolsSettings.thumbnailSeconds], expand: true)
    }

    /// Shows an activity, expands the Island on it, and dismisses it after `seconds`
    /// (later if the user is looking at it).
    func presentResult(_ activity: IslandActivity, seconds: Double, expand: Bool) {
        let id = activity.id
        resultTasks[id]?.cancel()
        if let handle = resultHandles[id], handle.isActive {
            handle.update(activity)
        } else {
            resultHandles[id] = context.island.present(activity)
        }
        if expand {
            context.island.showActivity(id)
        }
        resultTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(seconds, 1)))
            while !Task.isCancelled, self?.isExpanded(id) == true {
                try? await Task.sleep(for: .seconds(1))
            }
            if !Task.isCancelled {
                self?.dismissResult(id)
            }
        }
    }

    func isShowing(_ id: String) -> Bool {
        resultHandles[id]?.isActive == true
    }

    private func isExpanded(_ id: String) -> Bool {
        resultHandles[id]?.isExpanded == true
    }

    func dismissResult(_ id: String) {
        resultTasks[id]?.cancel()
        resultTasks[id] = nil
        resultHandles[id]?.dismiss()
        resultHandles[id] = nil
    }

    func notice(_ notice: ScreenToolsNotice) {
        context.island.showHUD(IslandHUD(id: "screenTools.notice", symbol: "exclamationmark.magnifyingglass", title: notice.message, duration: 2))
    }

    func problem(_ error: any Error) {
        context.log.error("Screen Tools: \(error.localizedDescription, privacy: .public)")
        context.island.showHUD(IslandHUD(
            id: "screenTools.problem",
            symbol: "exclamationmark.triangle.fill",
            title: error.localizedDescription,
            tint: .warning,
            duration: 3
        ))
    }

    // MARK: Pinning

    func pin(_ shot: Screenshot) {
        let id = UUID()
        let size = Self.pinSize(for: shot.capture.size)
        let placement: OverlayPlacement = if let rect = shot.sourceRect, rect.width >= 8, rect.height >= 8 {
            .frame(rect)
        } else {
            .centered(size: size)
        }
        let capture = shot.capture
        let content = PinnedScreenshotView(
            image: capture,
            copy: { [weak self] in
                guard let self else { return }
                Task { try? await self.copyImage(capture) }
            },
            close: { [weak self] in self?.unpin(id) }
        )
        let panel = context.overlays.makePanel(
            OverlayConfiguration(level: .floating, screen: .withCursor, placement: placement, hasShadow: true, isMovable: true),
            content: AnyView(content)
        )
        pins[id] = panel
        panel.show()
        dismissResult(Self.screenshotActivity)
    }

    func unpin(_ id: UUID) {
        pins.removeValue(forKey: id)?.close()
    }

    func unpinAll() {
        for pin in pins.values { pin.close() }
        pins = [:]
    }

    var pinCount: Int { pins.count }

    /// At most 640 × 480 points, keeping the aspect ratio.
    static func pinSize(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 320, height: 200) }
        let scale = min(1, 640 / size.width, 480 / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}
