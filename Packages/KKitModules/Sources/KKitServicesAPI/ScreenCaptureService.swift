import CoreGraphics
import Foundation

/// What to capture.
public enum CaptureTarget: Sendable, Hashable {
    /// A whole display (`CGDirectDisplayID`).
    case display(UInt32)
    /// Part of a display. `rect` is in global screen coordinates (points, origin at the
    /// bottom left of the main screen, like `NSScreen.frame`).
    case area(displayID: UInt32, rect: CGRect)
    /// One window (`CGWindowID`), without its shadow or what's behind it.
    case window(UInt32)
}

/// A captured image and the scale it was taken at (2 on Retina screens).
public struct CapturedImage: @unchecked Sendable {
    public let image: CGImage
    public let scale: CGFloat

    public init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
    }

    /// The size in points.
    public var size: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }
}

public struct RecordingOptions: Sendable, Hashable {
    public var capturesSystemAudio: Bool
    public var capturesMicrophone: Bool
    public var showsCursor: Bool
    public var showsClicks: Bool
    public var framesPerSecond: Int

    public init(
        capturesSystemAudio: Bool = false,
        capturesMicrophone: Bool = false,
        showsCursor: Bool = true,
        showsClicks: Bool = false,
        framesPerSecond: Int = 30
    ) {
        self.capturesSystemAudio = capturesSystemAudio
        self.capturesMicrophone = capturesMicrophone
        self.showsCursor = showsCursor
        self.showsClicks = showsClicks
        self.framesPerSecond = framesPerSecond
    }
}

public enum CaptureError: LocalizedError, Sendable, Equatable {
    case permissionDenied
    case targetNotFound
    case unsupported(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            String(localized: "KKit needs Screen Recording permission. Turn it on in System Settings › Privacy & Security.")
        case .targetNotFound:
            String(localized: "That screen or window isn't there any more.")
        case .unsupported(let message), .failed(let message):
            message
        }
    }
}

/// A recording in progress.
@MainActor
public protocol ScreenRecording: AnyObject {
    var startedAt: Date { get }
    var outputURL: URL { get }
    /// Stops and finishes the file. Returns its URL.
    func stop() async throws -> URL
    /// Called if the recording stops on its own (the window closed, permission revoked).
    var onInterrupted: (@MainActor (any Error) -> Void)? { get set }
}

/// Screenshots and screen recordings with ScreenCaptureKit, leaving KKit's own panels
/// (the Island, pickers) out. Needs Screen Recording permission.
@MainActor
public protocol ScreenCaptureService: AnyObject {
    func capture(_ target: CaptureTarget, showsCursor: Bool) async throws -> CapturedImage
    /// Recording needs macOS 15 (`SCRecordingOutput`).
    var supportsRecording: Bool { get }
    func startRecording(_ target: CaptureTarget, options: RecordingOptions, to url: URL) async throws -> any ScreenRecording
}
