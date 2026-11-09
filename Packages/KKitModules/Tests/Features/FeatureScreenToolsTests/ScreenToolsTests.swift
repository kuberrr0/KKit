import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureScreenTools

private let utc = TimeZone(identifier: "UTC")!

/// 9 November 2026, 14:05:09 UTC.
private let date: Date = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 14, minute: 5, second: 9))!
}()

struct CaptureFileNamerTests {
    @Test func fillsDateFormats() {
        #expect(CaptureFileNamer.name(pattern: "Screenshot {yyyy-MM-dd} at {HH.mm.ss}", date: date, timeZone: utc) == "Screenshot 2026-11-09 at 14.05.09")
        #expect(CaptureFileNamer.name(pattern: "shot", date: date, timeZone: utc) == "shot")
        #expect(CaptureFileNamer.name(pattern: "a {} b {unclosed", date: date, timeZone: utc) == "a  b {unclosed")
    }

    @Test func makesSafeNames() {
        #expect(CaptureFileNamer.name(pattern: "../{HH:mm}", date: date, timeZone: utc) == "-14.05")
        #expect(CaptureFileNamer.name(pattern: "   ", date: date, timeZone: utc) == "Screenshot")
    }

    @Test func numbersTakenNames() {
        let folder = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        let taken: Set<String> = ["/tmp/shots/a.png", "/tmp/shots/a (2).png"]
        let url = CaptureFileNamer.uniqueURL(in: folder, name: "a", fileExtension: "png") { taken.contains($0.path) }
        #expect(url.lastPathComponent == "a (3).png")
    }
}

struct ColorFormatterTests {
    private let orange = RGBAColor(red: 1, green: 0.5, blue: 0)

    @Test func formats() {
        #expect(ColorFormatter.string(orange, as: .rgb) == "rgb(255, 128, 0)")
        #expect(ColorFormatter.string(orange, as: .hsl) == "hsl(30, 100%, 50%)")
        #expect(ColorFormatter.string(orange, as: .css) == "rgb(255 128 0)")
        #expect(ColorFormatter.string(orange, as: .swiftUI) == "Color(red: 1, green: 0.5, blue: 0)")
        #expect(ColorFormatter.string(orange, as: .nsColor) == "NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)")
        #expect(ColorFormatter.string(orange, as: .hex) == orange.hex)
    }

    @Test func includesAlphaWhenTranslucent() {
        let clear = RGBAColor(red: 0, green: 0, blue: 1, alpha: 0.5)
        #expect(ColorFormatter.string(clear, as: .rgb) == "rgba(0, 0, 255, 0.5)")
        #expect(ColorFormatter.string(clear, as: .css) == "rgb(0 0 255 / 50%)")
        #expect(ColorFormatter.string(clear, as: .hsl) == "hsla(240, 100%, 50%, 0.5)")
    }

    @Test func greysHaveNoHue() {
        let (hue, saturation, lightness) = ColorFormatter.hsl(RGBAColor(red: 0.5, green: 0.5, blue: 0.5))
        #expect(hue == 0)
        #expect(saturation == 0)
        #expect(abs(lightness - 0.5) < 0.0001)
    }

    @Test func trimsDecimals() {
        #expect(ColorFormatter.decimal(0.5, places: 3) == "0.5")
        #expect(ColorFormatter.decimal(1, places: 3) == "1")
        #expect(ColorFormatter.decimal(0.50196, places: 3) == "0.502")
    }
}

struct ScannedLinkTests {
    @Test func findsLinks() {
        #expect(ScreenToolsController.link(in: "https://kkit.app/x")?.host() == "kkit.app")
        #expect(ScreenToolsController.link(in: "mailto:me@example.com") != nil)
        #expect(ScreenToolsController.link(in: "hello world") == nil)
        #expect(ScreenToolsController.link(in: "WIFI:S:home;T:WPA;P:secret;;") == nil)
        #expect(ScreenToolsController.link(in: "https://") == nil)
    }
}

struct ImageEncoderTests {
    @Test func encodesPNGAndJPEG() throws {
        let capture = CapturedImage(image: FakeScreenCaptureService.sampleImage(width: 8, height: 4), scale: 2)
        // HEIC needs a hardware encoder that CI's virtual Macs may not have.
        for format in [ImageFormat.png, .jpeg] {
            let data = try ImageEncoder.encode(capture, as: format, quality: 0.8)
            #expect(!data.isEmpty)
        }
        #expect(capture.size == CGSize(width: 4, height: 2))
    }
}

@MainActor
struct ScreenshotFlowTests {
    private func makeController(granted: Set<Permission> = [.screenRecording]) throws -> (TestEnvironment, ScreenToolsController, URL) {
        let environment = TestEnvironment(granted: granted)
        let context = environment.makeContext(for: ScreenToolsFeature.manifest.id)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenToolsTests-\(UUID().uuidString)", isDirectory: true)
        context.settings[ScreenToolsSettings.saveFolder] = folder.path
        let controller = ScreenToolsController(context: context)
        controller.temporaryFolder = folder.appendingPathComponent("tmp", isDirectory: true)
        controller.now = { date }
        return (environment, controller, folder)
    }

    @Test func capturesAnAreaSavesCopiesAndShowsIt() async throws {
        let (environment, controller, folder) = try makeController()
        let rect = CGRect(x: 100, y: 100, width: 40, height: 20)
        environment.overlays.nextRegion = RegionSelection(displayID: 1, rect: rect)
        try await controller.screenshot(.area)

        #expect(environment.screenCapture.captures == [.area(displayID: 1, rect: rect)])
        let shot = try #require(controller.latest)
        #expect(shot.isSaved)
        #expect(shot.isCopied)
        #expect(shot.sourceRect == rect)
        #expect(shot.fileURL.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: shot.fileURL.path))
        #expect(environment.pasteboard.writes.last?.imageType == "public.png")
        #expect(environment.island.activityIDs.contains(ScreenToolsController.screenshotActivity))
    }

    @Test func pickingAWindowCapturesIt() async throws {
        let (environment, controller, _) = try makeController()
        environment.overlays.nextRegion = RegionSelection(displayID: 1, rect: CGRect(x: 0, y: 0, width: 300, height: 200), windowID: 42)
        try await controller.screenshot(.area)
        #expect(environment.screenCapture.captures == [.window(42)])
    }

    @Test func cancellingCapturesNothing() async throws {
        let (environment, controller, _) = try makeController()
        environment.overlays.nextRegion = nil
        try await controller.screenshot(.screen)
        #expect(environment.screenCapture.captures.isEmpty)
        #expect(controller.latest == nil)
    }

    @Test func withoutPermissionItAsks() async throws {
        let (environment, controller, _) = try makeController(granted: [])
        environment.overlays.nextRegion = RegionSelection(displayID: 1, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        await #expect(throws: CaptureError.permissionDenied) {
            try await controller.screenshot(.area)
        }
        #expect(environment.screenCapture.captures.isEmpty)
    }

    @Test func notSavingKeepsATemporaryFileToSaveLater() async throws {
        let (environment, controller, folder) = try makeController()
        controller.settings[ScreenToolsSettings.saveAfterCapture] = false
        controller.settings[ScreenToolsSettings.copyAfterCapture] = false
        environment.overlays.nextRegion = RegionSelection(displayID: 1, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        try await controller.screenshot(.area)
        let shot = try #require(controller.latest)
        #expect(!shot.isSaved)
        #expect(environment.pasteboard.writes.isEmpty)
        await controller.save(shot)
        let saved = try #require(controller.latest)
        #expect(saved.isSaved)
        #expect(saved.fileURL.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: saved.fileURL.path))
    }

    @Test func pinsOpenAMovablePanel() async throws {
        let (environment, controller, _) = try makeController()
        environment.overlays.nextRegion = RegionSelection(displayID: 1, rect: CGRect(x: 10, y: 10, width: 40, height: 20))
        try await controller.screenshot(.area)
        controller.pin(try #require(controller.latest))
        #expect(controller.pinCount == 1)
        #expect(environment.overlays.openPanels.last?.configuration.isMovable == true)
        controller.unpinAll()
        #expect(controller.pinCount == 0)
        #expect(environment.overlays.openPanels.isEmpty)
    }

    @Test func remembersColours() throws {
        let (environment, controller, _) = try makeController()
        controller.copyColor(RGBAColor(red: 1, green: 0, blue: 0))
        controller.copyColor(RGBAColor(red: 0, green: 0, blue: 1))
        controller.copyColor(RGBAColor(red: 1, green: 0, blue: 0))
        #expect(controller.colorHistory == [RGBAColor(red: 1, green: 0, blue: 0).hex, RGBAColor(red: 0, green: 0, blue: 1).hex])
        #expect(environment.pasteboard.writes.last?.string == RGBAColor(red: 1, green: 0, blue: 0).hex)
        controller.settings[ScreenToolsSettings.colorFormat] = .rgb
        controller.copyColor(RGBAColor(red: 0, green: 1, blue: 0))
        #expect(environment.pasteboard.writes.last?.string == "rgb(0, 255, 0)")
    }

    @Test func recordsAndStops() async throws {
        let (environment, controller, folder) = try makeController()
        environment.overlays.nextRegion = RegionSelection(displayID: 1, rect: CGRect(x: 0, y: 0, width: 100, height: 100))
        try await controller.startRecording(.screen)
        #expect(controller.isRecording)
        let recording = try #require(environment.screenCapture.recordings.first)
        #expect(recording.target == .display(1))
        #expect(recording.outputURL.pathExtension == "mp4")
        #expect(recording.outputURL.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(environment.island.activity(ScreenToolsController.recordingActivity)?.priority == .critical)
        await #expect(throws: ScreenToolsError.self) {
            try await controller.startRecording(.area)
        }
        await controller.stopRecording()
        #expect(!controller.isRecording)
        #expect(recording.isStopped)
        #expect(controller.lastRecordingURL == recording.outputURL)
    }

    @Test func recordingNeedsSupport() async throws {
        let (environment, controller, _) = try makeController()
        environment.screenCapture.supportsRecording = false
        await #expect(throws: ScreenToolsError.self) {
            try await controller.startRecording(.screen)
        }
    }

    @Test func translateProviderOffersOneResult() throws {
        let (_, controller, _) = try makeController()
        #expect(TranslateProvider.results(for: SearchQuery(text: "   "), target: "fr", controller: controller).isEmpty)
        let results = TranslateProvider.results(for: SearchQuery(text: "hola", isScoped: true), target: "fr", controller: controller)
        #expect(results.count == 1)
        #expect(results.first?.kind == .custom)
    }

    @Test func featureCommandsAreNamespaced() {
        let environment = TestEnvironment()
        let feature = ScreenToolsFeature(context: environment.makeContext(for: ScreenToolsFeature.manifest.id))
        let ids = feature.commands.map(\.id.rawValue)
        #expect(ids.allSatisfy { $0.hasPrefix("screenTools.") })
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains("screenTools.captureArea"))
        #expect(ids.contains("screenTools.stopRecording"))
    }
}
