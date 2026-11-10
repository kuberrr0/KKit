import AppKit
import CoreMedia
import KKitServicesAPI
import ScreenCaptureKit

/// Screenshots (`SCScreenshotManager`, macOS 14) and recordings (`SCRecordingOutput`,
/// macOS 15) with ScreenCaptureKit. KKit's own windows (the Island, pickers, pinned
/// screenshots) are left out of display and area captures.
///
/// ScreenCaptureKit's objects aren't `Sendable`, so all the work happens in
/// nonisolated code and only the finished image or file crosses back.
@MainActor
public final class ScreenCaptureKitService: ScreenCaptureService {
    public init() {}

    public func capture(_ target: CaptureTarget, showsCursor: Bool) async throws -> CapturedImage {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permissionDenied }
        return try await Self.captureImage(target, showsCursor: showsCursor, displays: Self.displayGeometry())
    }

    public func windowThumbnails(_ windowIDs: [UInt32], maxSize: CGSize) -> AsyncStream<WindowThumbnail> {
        guard !windowIDs.isEmpty, CGPreflightScreenCaptureAccess() else {
            return AsyncStream { $0.finish() }
        }
        return AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await Self.captureThumbnails(windowIDs, maxSize: maxSize) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public var supportsRecording: Bool {
        if #available(macOS 15.0, *) {
            return true
        }
        return false
    }

    public func startRecording(_ target: CaptureTarget, options: RecordingOptions, to url: URL) async throws -> any ScreenRecording {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permissionDenied }
        guard #available(macOS 15.0, *) else {
            throw CaptureError.unsupported(String(localized: "Screen recording needs macOS 15 or later."))
        }
        let session = RecordingSession(outputURL: url)
        let recording = Recording(session: session, outputURL: url)
        session.onInterrupted = { error in
            Task { @MainActor in recording.interrupted(error) }
        }
        try await session.start(target, options: options, displays: Self.displayGeometry())
        return recording
    }

    // MARK: Displays

    /// What the nonisolated code needs to know about each screen.
    struct DisplayGeometry: Sendable {
        var frame: CGRect
        var scale: CGFloat
        /// The height of the main screen, for flipping to top-left coordinates.
        var mainHeight: CGFloat
    }

    static func displayGeometry() -> [UInt32: DisplayGeometry] {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        var result: [UInt32: DisplayGeometry] = [:]
        for screen in NSScreen.screens {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            result[id] = DisplayGeometry(frame: screen.frame, scale: screen.backingScaleFactor, mainHeight: mainHeight)
        }
        return result
    }

    /// `rect` (global, bottom-left origin) relative to the display, top-left origin, as
    /// `SCStreamConfiguration.sourceRect` wants it.
    nonisolated static func sourceRect(for rect: CGRect, on display: DisplayGeometry) -> CGRect {
        let clipped = rect.intersection(display.frame)
        return CGRect(
            x: clipped.minX - display.frame.minX,
            y: display.frame.maxY - clipped.maxY,
            width: clipped.width,
            height: clipped.height
        ).integral
    }

    // MARK: Screenshots

    nonisolated static func captureImage(
        _ target: CaptureTarget,
        showsCursor: Bool,
        displays: [UInt32: DisplayGeometry]
    ) async throws -> CapturedImage {
        let content = try await shareableContent()
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = showsCursor
        configuration.capturesAudio = false
        let filter: SCContentFilter
        let scale: CGFloat
        switch target {
        case .display(let id), .area(let id, _):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw CaptureError.targetNotFound
            }
            filter = SCContentFilter(display: display, excludingApplications: ownApplications(in: content), exceptingWindows: [])
            let geometry = displays[id]
            scale = geometry?.scale ?? CGFloat(filter.pointPixelScale)
            if case .area(_, let rect) = target, let geometry {
                let source = sourceRect(for: rect, on: geometry)
                guard source.width >= 1, source.height >= 1 else { throw CaptureError.targetNotFound }
                configuration.sourceRect = source
                configuration.width = Int(source.width * scale)
                configuration.height = Int(source.height * scale)
            } else {
                configuration.width = Int(CGFloat(display.width) * scale)
                configuration.height = Int(CGFloat(display.height) * scale)
            }
        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureError.targetNotFound
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            scale = CGFloat(filter.pointPixelScale)
            configuration.ignoreShadowsSingleWindow = true
            configuration.width = Int(window.frame.width * scale)
            configuration.height = Int(window.frame.height * scale)
        }
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return CapturedImage(image: image, scale: scale)
        } catch {
            throw CaptureError.failed(error.localizedDescription)
        }
    }

    // MARK: Thumbnails

    nonisolated static func captureThumbnails(
        _ windowIDs: [UInt32],
        maxSize: CGSize,
        yield: @escaping @Sendable (WindowThumbnail) -> Void
    ) async {
        // Not only on-screen windows: minimised windows and hidden apps' windows can
        // sometimes still be captured.
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            return
        }
        var byID: [UInt32: UncheckedWindow] = [:]
        for window in content.windows {
            byID[window.windowID] = UncheckedWindow(window: window)
        }
        let targets = windowIDs.compactMap { byID[$0] }
        await withTaskGroup(of: WindowThumbnail?.self) { group in
            for target in targets {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    return await thumbnail(of: target.window, maxSize: maxSize)
                }
            }
            for await result in group {
                if let result {
                    yield(result)
                }
            }
        }
    }

    private nonisolated static func thumbnail(of window: SCWindow, maxSize: CGSize) async -> WindowThumbnail? {
        let frame = window.frame
        guard frame.width >= 1, frame.height >= 1 else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let pixelScale = CGFloat(filter.pointPixelScale)
        let fit = min(maxSize.width / frame.width, maxSize.height / frame.height, 1)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.scalesToFit = true
        configuration.width = max(Int(frame.width * fit * pixelScale), 2)
        configuration.height = max(Int(frame.height * fit * pixelScale), 2)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else {
            return nil
        }
        return WindowThumbnail(windowID: window.windowID, image: CapturedImage(image: image, scale: pixelScale))
    }

    nonisolated static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // -3801: the user declined Screen Recording.
            if (error as NSError).code == -3801 {
                throw CaptureError.permissionDenied
            }
            throw CaptureError.failed(error.localizedDescription)
        }
    }

    nonisolated static func ownApplications(in content: SCShareableContent) -> [SCRunningApplication] {
        let pid = ProcessInfo.processInfo.processIdentifier
        return content.applications.filter { $0.processID == pid }
    }
}

/// `SCWindow` isn't `Sendable`; it's only read inside one capture task.
private struct UncheckedWindow: @unchecked Sendable {
    let window: SCWindow
}

// MARK: - Recording

/// The main-actor face of a recording.
@MainActor
final class Recording: ScreenRecording {
    let startedAt = Date()
    let outputURL: URL
    var onInterrupted: (@MainActor (any Error) -> Void)?
    private let session: any RecordingStopping
    private var isStopped = false

    init(session: any RecordingStopping, outputURL: URL) {
        self.session = session
        self.outputURL = outputURL
    }

    func stop() async throws -> URL {
        guard !isStopped else { return outputURL }
        isStopped = true
        try await session.stop()
        return outputURL
    }

    func interrupted(_ error: any Error) {
        guard !isStopped else { return }
        isStopped = true
        onInterrupted?(error)
    }
}

protocol RecordingStopping: Sendable {
    func stop() async throws
}

/// Owns the `SCStream` and `SCRecordingOutput`. Its state is only touched by `start`,
/// `stop` and the delegate callbacks, guarded by a lock.
@available(macOS 15.0, *)
final class RecordingSession: NSObject, RecordingStopping, SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
    let outputURL: URL
    var onInterrupted: (@Sendable (any Error) -> Void)?

    private let lock = NSLock()
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var startContinuation: CheckedContinuation<Void, any Error>?
    private var finishContinuation: CheckedContinuation<Void, any Error>?
    /// How starting went, if it finished before `start` began waiting.
    private var startResult: Result<Void, any Error>?
    private var isStopping = false

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func start(
        _ target: CaptureTarget,
        options: RecordingOptions,
        displays: [UInt32: ScreenCaptureKitService.DisplayGeometry]
    ) async throws {
        let content = try await ScreenCaptureKitService.shareableContent()
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = options.showsCursor
        configuration.showMouseClicks = options.showsClicks
        configuration.capturesAudio = options.capturesSystemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = options.capturesMicrophone
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(options.framesPerSecond, 1)))
        configuration.queueDepth = 6

        let filter: SCContentFilter
        switch target {
        case .display(let id), .area(let id, _):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw CaptureError.targetNotFound
            }
            filter = SCContentFilter(
                display: display,
                excludingApplications: ScreenCaptureKitService.ownApplications(in: content),
                exceptingWindows: []
            )
            let scale = displays[id]?.scale ?? CGFloat(filter.pointPixelScale)
            if case .area(_, let rect) = target, let geometry = displays[id] {
                let source = ScreenCaptureKitService.sourceRect(for: rect, on: geometry)
                guard source.width >= 2, source.height >= 2 else { throw CaptureError.targetNotFound }
                configuration.sourceRect = source
                // H.264 wants even dimensions.
                configuration.width = Int(source.width * scale) & ~1
                configuration.height = Int(source.height * scale) & ~1
            } else {
                configuration.width = Int(CGFloat(display.width) * scale) & ~1
                configuration.height = Int(CGFloat(display.height) * scale) & ~1
            }
        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureError.targetNotFound
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            configuration.ignoreShadowsSingleWindow = true
            configuration.width = Int(window.frame.width * scale) & ~1
            configuration.height = Int(window.frame.height * scale) & ~1
        }

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mp4
        recordingConfiguration.videoCodecType = .h264
        let output = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addRecordingOutput(output)
        } catch {
            throw CaptureError.failed(error.localizedDescription)
        }
        lock.withLock {
            self.stream = stream
            self.output = output
        }
        do {
            try await stream.startCapture()
        } catch {
            throw CaptureError.failed(error.localizedDescription)
        }
        // Don't wait forever if ScreenCaptureKit never says it started.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.started(.success(()))
        }
        // Wait until the file has actually started, so a failure shows up here.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let early: Result<Void, any Error>? = lock.withLock {
                if let result = startResult { return result }
                startContinuation = continuation
                return nil
            }
            if let early {
                continuation.resume(with: early)
            }
        }
    }

    private func started(_ result: Result<Void, any Error>) {
        let continuation: CheckedContinuation<Void, any Error>? = lock.withLock {
            guard startResult == nil else { return nil }
            startResult = result
            let continuation = startContinuation
            startContinuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }

    func stop() async throws {
        let stream: SCStream? = lock.withLock {
            isStopping = true
            return self.stream
        }
        guard let stream else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            lock.withLock { finishContinuation = continuation }
            stream.stopCapture { error in
                if let error {
                    self.finish(with: error)
                } else {
                    // The file normally finishes right away; don't hang if it doesn't say so.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                        self.finish(with: nil)
                    }
                }
            }
        }
        lock.withLock {
            self.stream = nil
            self.output = nil
        }
    }

    private func finish(with error: (any Error)?) {
        let (wasStarted, finish, stopping) = lock.withLock {
            let state = (startResult != nil, finishContinuation, isStopping)
            finishContinuation = nil
            return state
        }
        if !wasStarted {
            // Failed before the file started: `start` throws.
            started(error.map { .failure($0) } ?? .success(()))
            return
        }
        if let finish {
            if let error { finish.resume(throwing: error) } else { finish.resume() }
        } else if let error, !stopping {
            onInterrupted?(error)
        }
    }

    // MARK: SCRecordingOutputDelegate

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        started(.success(()))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        finish(with: error)
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finish(with: nil)
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        finish(with: error)
    }
}
