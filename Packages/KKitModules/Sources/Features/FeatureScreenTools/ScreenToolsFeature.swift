import Foundation
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Screen Tools: screenshots, text and code scanning, translation and screen recording.
/// DESIGN.md §3.6. The colour picker is its own feature (FeatureColorPicker).
@MainActor
public final class ScreenToolsFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "screenTools",
        name: String(localized: "Screen Tools"),
        symbol: "camera.viewfinder",
        summary: String(localized: "Screenshots, text and QR scanning, translation and screen recording."),
        category: .capture,
        optionalPermissions: [.screenRecording, .microphone],
        enabledByDefault: true
    )

    private let context: FeatureContext
    let controller: ScreenToolsController
    private lazy var translateProvider = TranslateProvider(controller: controller)

    public init(context: FeatureContext) {
        self.context = context
        controller = ScreenToolsController(context: context)
    }

    public func start() async throws {}

    public func stop() async {
        await controller.tearDown()
    }

    // MARK: Contributions

    public var commands: [Command] {
        let controller = controller
        return [
            Command(
                id: "screenTools.captureArea",
                title: String(localized: "Capture Area"),
                subtitle: String(localized: "Drag out part of the screen. Space picks a window instead"),
                symbol: "rectangle.dashed",
                keywords: ["screenshot", "capture", "snip", "area", "selection"]
            ) { _ in
                try await controller.screenshot(.area)
            },
            Command(
                id: "screenTools.captureWindow",
                title: String(localized: "Capture Window"),
                symbol: "macwindow",
                keywords: ["screenshot", "capture", "window"]
            ) { _ in
                try await controller.screenshot(.window)
            },
            Command(
                id: "screenTools.captureScreen",
                title: String(localized: "Capture Screen"),
                symbol: "display",
                keywords: ["screenshot", "capture", "full screen", "display"]
            ) { _ in
                try await controller.screenshot(.screen)
            },
            Command(
                id: "screenTools.captureTimed",
                title: String(localized: "Capture with Timer"),
                subtitle: String(localized: "Pick an area or window, then wait a few seconds"),
                symbol: "timer",
                keywords: ["screenshot", "capture", "timer", "delay"]
            ) { _ in
                try await controller.screenshot(.timed)
            },
            Command(
                id: "screenTools.captureText",
                title: String(localized: "Copy Text from Screen"),
                subtitle: String(localized: "Select an area and its text is copied"),
                symbol: "text.viewfinder",
                keywords: ["ocr", "text", "recognize", "scan", "copy"]
            ) { _ in
                try await controller.captureText()
            },
            Command(
                id: "screenTools.scanCode",
                title: String(localized: "Scan QR Code"),
                subtitle: String(localized: "Select a QR code or barcode"),
                symbol: "qrcode.viewfinder",
                keywords: ["qr", "barcode", "scan", "link"]
            ) { _ in
                try await controller.scanCode()
            },
            Command(
                id: "screenTools.scanScreenCodes",
                title: String(localized: "Scan Screen for QR Codes"),
                symbol: "qrcode",
                keywords: ["qr", "barcode", "scan", "screen"]
            ) { _ in
                try await controller.scanScreens()
            },
            Command(
                id: "screenTools.translateArea",
                title: String(localized: "Translate Area"),
                subtitle: String(localized: "Select text on screen to translate it"),
                symbol: "translate",
                keywords: ["translate", "language", "ocr"]
            ) { _ in
                try await controller.translateArea()
            },
            Command(
                id: "screenTools.translateClipboard",
                title: String(localized: "Translate Clipboard"),
                symbol: "doc.on.clipboard",
                keywords: ["translate", "language", "clipboard"]
            ) { _ in
                controller.translateClipboard()
            },
            Command(
                id: "screenTools.recordArea",
                title: String(localized: "Record Area"),
                symbol: "record.circle",
                keywords: ["record", "video", "screen recording", "capture"],
                isEnabled: { !controller.isRecording }
            ) { _ in
                try await controller.startRecording(.area)
            },
            Command(
                id: "screenTools.recordWindow",
                title: String(localized: "Record Window"),
                symbol: "macwindow.badge.plus",
                keywords: ["record", "video", "window"],
                isEnabled: { !controller.isRecording }
            ) { _ in
                try await controller.startRecording(.window)
            },
            Command(
                id: "screenTools.recordScreen",
                title: String(localized: "Record Screen"),
                symbol: "record.circle.fill",
                keywords: ["record", "video", "screen recording", "full screen"],
                isEnabled: { !controller.isRecording }
            ) { _ in
                try await controller.startRecording(.screen)
            },
            Command(
                id: "screenTools.stopRecording",
                title: String(localized: "Stop Recording"),
                symbol: "stop.circle",
                keywords: ["record", "stop", "video"],
                isEnabled: { controller.isRecording }
            ) { _ in
                await controller.stopRecording()
            },
            Command(
                id: "screenTools.closePins",
                title: String(localized: "Close Pinned Screenshots"),
                symbol: "pin.slash",
                keywords: ["pin", "screenshot", "close"],
                isEnabled: { controller.pinCount > 0 }
            ) { _ in
                controller.unpinAll()
            },
        ]
    }

    public var quickToggles: [QuickToggle] {
        let controller = controller
        return [
            QuickToggle(Command(
                id: "screenTools.recordTile",
                title: String(localized: "Record"),
                symbol: "record.circle",
                state: {
                    guard let recording = controller.recording else { return .off }
                    return .value(KKFormat.clock(Date().timeIntervalSince(recording.startedAt)))
                }
            ) { _ in
                if controller.isRecording {
                    await controller.stopRecording()
                } else {
                    try await controller.startRecording(.screen)
                }
            }),
        ]
    }

    public var searchProviders: [any SearchProvider] {
        [translateProvider]
    }

    public var settingsPane: SettingsPane? {
        let controller = controller
        let permissions = context.permissions
        let supportsRecording = context.screenCapture.supportsRecording
        return SettingsPane {
            ScreenToolsSettingsView(controller: controller, permissions: permissions, supportsRecording: supportsRecording)
        }
    }
}
