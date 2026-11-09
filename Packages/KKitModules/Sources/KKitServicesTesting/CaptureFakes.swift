import CoreGraphics
import Foundation
import KKitCore
import KKitServicesAPI

/// A clipboard in memory. `simulateCopy` stands in for another app copying.
@MainActor
public final class FakePasteboardService: PasteboardService {
    public private(set) var contents = PasteboardContents()
    public private(set) var changeCount = 0
    public private(set) var writes: [PasteboardContents] = []
    public private(set) var pasteCount = 0
    public var canPaste = true
    private let broadcast = Broadcast<PasteboardChange>()

    public init() {}

    public var subscriberCount: Int { broadcast.subscriberCount }

    public func changes() -> AsyncStream<PasteboardChange> {
        broadcast.stream(initial: PasteboardChange(changeCount: changeCount, contents: contents))
    }

    public func read() -> PasteboardContents {
        contents
    }

    public func write(_ contents: PasteboardContents) {
        self.contents = contents
        changeCount += 1
        writes.append(contents)
        broadcast.send(PasteboardChange(changeCount: changeCount, contents: contents, isFromKKit: true))
    }

    public func paste() async throws {
        guard canPaste else { throw PasteError.needsAccessibility }
        pasteCount += 1
    }

    /// Another app copied something.
    public func simulateCopy(_ contents: PasteboardContents, from bundleID: String? = "com.apple.TextEdit", appName: String? = "TextEdit") {
        self.contents = contents
        changeCount += 1
        broadcast.send(PasteboardChange(
            changeCount: changeCount,
            contents: contents,
            sourceBundleID: bundleID,
            sourceAppName: appName
        ))
    }
}

/// Returns a small grey image for every capture and records what was asked.
@MainActor
public final class FakeScreenCaptureService: ScreenCaptureService {
    public private(set) var captures: [CaptureTarget] = []
    public private(set) var recordings: [FakeRecording] = []
    public var failure: CaptureError?
    public var supportsRecording = true

    public init() {}

    public func capture(_ target: CaptureTarget, showsCursor: Bool) async throws -> CapturedImage {
        if let failure { throw failure }
        captures.append(target)
        return CapturedImage(image: Self.sampleImage(width: 40, height: 20), scale: 2)
    }

    public func startRecording(_ target: CaptureTarget, options: RecordingOptions, to url: URL) async throws -> any ScreenRecording {
        if let failure { throw failure }
        let recording = FakeRecording(target: target, options: options, outputURL: url)
        recordings.append(recording)
        return recording
    }

    /// A solid grey image.
    public static func sampleImage(width: Int, height: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

@MainActor
public final class FakeRecording: ScreenRecording {
    public let target: CaptureTarget
    public let options: RecordingOptions
    public let startedAt = Date()
    public let outputURL: URL
    public var onInterrupted: (@MainActor (any Error) -> Void)?
    public private(set) var isStopped = false

    init(target: CaptureTarget, options: RecordingOptions, outputURL: URL) {
        self.target = target
        self.options = options
        self.outputURL = outputURL
    }

    public func stop() async throws -> URL {
        isStopped = true
        try? Data("fake movie".utf8).write(to: outputURL)
        return outputURL
    }
}
