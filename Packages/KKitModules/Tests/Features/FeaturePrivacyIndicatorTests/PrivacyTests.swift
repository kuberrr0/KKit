import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeaturePrivacyIndicator

struct UsageLogTests {
    private let zoom = DeviceUser(pid: 42, name: "zoom.us", bundleID: "us.zoom.xos")
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func opensAndClosesEntries() {
        var log = UsageLog()
        #expect(!log.record(DeviceUsage(micInUse: true, micUsers: [zoom]), at: start))
        #expect(log.entries.count == 1)
        #expect(log.entries[0].apps == ["zoom.us"])

        let later = start.addingTimeInterval(600)
        #expect(log.record(.idle, at: later))
        #expect(log.entries[0].end == later)
        #expect(log.entries[0].duration == 600)
    }

    @Test func addsAppsSeenLater() {
        var log = UsageLog()
        log.record(DeviceUsage(micInUse: true), at: start)
        log.record(DeviceUsage(micInUse: true, micUsers: [zoom]), at: start.addingTimeInterval(5))
        log.record(DeviceUsage(micInUse: true, micUsers: [zoom]), at: start.addingTimeInterval(10))
        #expect(log.entries.count == 1)
        #expect(log.entries[0].apps == ["zoom.us"])
    }

    @Test func tracksTheCameraSeparately() {
        var log = UsageLog()
        log.record(DeviceUsage(micInUse: true, cameraInUse: true), at: start)
        log.record(DeviceUsage(micInUse: true, cameraInUse: false), at: start.addingTimeInterval(30))
        #expect(log.entries.map(\.device) == [.microphone, .camera])
        #expect(log.entries[0].end == nil)
        #expect(log.entries[1].end != nil)
    }

    @Test func prunesAfterAWeek() {
        var log = UsageLog()
        log.record(DeviceUsage(micInUse: true), at: start)
        log.record(.idle, at: start.addingTimeInterval(60))
        log.prune(now: start.addingTimeInterval(8 * 24 * 3600))
        #expect(log.entries.isEmpty)
    }
}

@MainActor
struct PrivacyIndicatorTests {
    @Test func indicatorContent() {
        let model = PrivacyModel()
        #expect(model.indicator(showMic: true, showCamera: true, showAppNames: true) == nil)

        model.update(usage: DeviceUsage(micInUse: true, micUsers: [DeviceUser(pid: 1, name: "FaceTime", bundleID: nil)]), keepLog: false, at: Date())
        let mic = model.indicator(showMic: true, showCamera: true, showAppNames: true)
        #expect(mic?.symbols == ["mic.fill"])
        #expect(mic?.label == "FaceTime")
        #expect(model.indicator(showMic: false, showCamera: true, showAppNames: true) == nil)

        model.update(audio: AudioState(inputMuted: true))
        let muted = model.indicator(showMic: true, showCamera: true, showAppNames: true)
        #expect(muted?.micMuted == true)
        #expect(muted?.symbols == ["mic.slash.fill"])
    }

    @Test func cameraWithoutAName() {
        let model = PrivacyModel()
        model.update(usage: DeviceUsage(cameraInUse: true), keepLog: false, at: Date())
        let camera = model.indicator(showMic: true, showCamera: true, showAppNames: true)
        #expect(camera?.symbols == ["video.fill"])
        #expect(camera?.label == "Camera")
    }

    @Test func featureShowsAndHidesTheActivity() async throws {
        let env = TestEnvironment()
        let feature = PrivacyIndicatorFeature(context: env.makeContext(for: "privacyIndicator"))
        try await feature.start()
        await env.settle()
        #expect(env.island.activityIDs.isEmpty)

        env.deviceUsage.usage = DeviceUsage(micInUse: true)
        await env.settle()
        let activity = try #require(env.island.activity("inUse"))
        #expect(activity.priority == .high)

        // Clicking the ear mutes the mic.
        activity.onTap?()
        #expect(env.audio.state.inputMuted)

        env.deviceUsage.usage = .idle
        await env.settle()
        #expect(env.island.activityIDs.isEmpty)
        await feature.stop()
    }

    @Test func savesTheLogWhenOn() async throws {
        let env = TestEnvironment()
        let context = env.makeContext(for: "privacyIndicator")
        context.settings[PrivacySettings.keepLog] = true
        let feature = PrivacyIndicatorFeature(context: context)
        try await feature.start()
        env.deviceUsage.usage = DeviceUsage(micInUse: true)
        await env.settle()
        env.deviceUsage.usage = .idle
        await env.settle()
        let saved = try env.storage.readJSON(UsageLog.self, named: PrivacyIndicatorFeature.logFile, for: "privacyIndicator")
        #expect(saved?.entries.count == 1)
        await feature.stop()
    }
}
