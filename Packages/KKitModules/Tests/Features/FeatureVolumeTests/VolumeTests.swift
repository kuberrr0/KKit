import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureVolume

struct VolumeMathTests {
    @Test func stepsSnapToTheGrid() {
        #expect(VolumeMath.stepped(0.5, step: 0.0625, up: true) == 0.5625)
        #expect(VolumeMath.stepped(0.5, step: 0.0625, up: false) == 0.4375)
        #expect(VolumeMath.stepped(0.53, step: 0.0625, up: true) == 0.5625)
        #expect(VolumeMath.stepped(0.53, step: 0.0625, up: false) == 0.5)
    }

    @Test func fineStepsAreAQuarter() {
        #expect(abs(VolumeMath.stepped(0.5, step: 0.1, up: true, fine: true) - 0.525) < 1e-9)
    }

    @Test func clampsToTheLimit() {
        #expect(VolumeMath.stepped(0.98, step: 0.0625, up: true) == 1)
        #expect(VolumeMath.stepped(0.02, step: 0.0625, up: false) == 0)
        #expect(VolumeMath.stepped(0.7, step: 0.1, up: true, limit: 0.75) == 0.75)
        #expect(VolumeMath.clamp(1.4) == 1)
    }

    @Test func speakerSymbols() {
        #expect(VolumeMath.speakerSymbol(volume: 0.5, muted: true) == "speaker.slash.fill")
        #expect(VolumeMath.speakerSymbol(volume: 0, muted: false) == "speaker.slash.fill")
        #expect(VolumeMath.speakerSymbol(volume: 0.2, muted: false) == "speaker.wave.1.fill")
        #expect(VolumeMath.speakerSymbol(volume: 0.9, muted: false) == "speaker.wave.3.fill")
    }
}

struct ScrollAccumulatorTests {
    @Test func mouseWheelNotchIsOneStep() {
        var scroll = ScrollAccumulator()
        let result1 = scroll.steps(for: IslandScrollEvent(deltaY: 3, deltaX: 0, isPrecise: false, isFine: false))
        #expect(result1 == 1)
        let result2 = scroll.steps(for: IslandScrollEvent(deltaY: -1, deltaX: 0, isPrecise: false, isFine: false))
        #expect(result2 == -1)
    }

    @Test func trackpadAccumulates() {
        var scroll = ScrollAccumulator(threshold: 10)
        let small = IslandScrollEvent(deltaY: 4, deltaX: 0, isPrecise: true, isFine: false)
        let result3 = scroll.steps(for: small)
        #expect(result3 == 0)
        let result4 = scroll.steps(for: small)
        #expect(result4 == 0)
        let result5 = scroll.steps(for: small)
        #expect(result5 == 1)
        // Reversing direction drops what was left over.
        let result6 = scroll.steps(for: IslandScrollEvent(deltaY: -25, deltaX: 0, isPrecise: true, isFine: false))
        #expect(result6 == -2)
    }
}

@MainActor
struct AudioDevicePickerTests {
    private let devices = [FakeAudioService.speakers, FakeAudioService.airPods]

    @Test func matchesByName() {
        #expect(AudioDevicePicker.match("airpods", in: devices)?.uid == "airpods")
        #expect(AudioDevicePicker.match("macbook", in: devices)?.uid == "speakers")
        #expect(AudioDevicePicker.match("speakers", in: devices)?.uid == "speakers")
        #expect(AudioDevicePicker.match("hdmi", in: devices) == nil)
        #expect(AudioDevicePicker.match("  ", in: devices) == nil)
    }

    @Test func prefersTheFirstConnected() {
        let priority = [
            PriorityDevice(uid: "studio", name: "Studio Display"),
            PriorityDevice(uid: "airpods", name: "AirPods Pro"),
            PriorityDevice(uid: "speakers", name: "MacBook Pro Speakers"),
        ]
        #expect(AudioDevicePicker.preferred(in: devices, priority: priority)?.uid == "airpods")
        #expect(AudioDevicePicker.preferred(in: devices, priority: []) == nil)
    }

    @Test func nextWraps() {
        #expect(AudioDevicePicker.next(after: FakeAudioService.speakers, in: devices)?.uid == "airpods")
        #expect(AudioDevicePicker.next(after: FakeAudioService.airPods, in: devices)?.uid == "speakers")
        #expect(AudioDevicePicker.next(after: nil, in: devices)?.uid == "speakers")
    }
}

@MainActor
struct VolumeControllerTests {
    private func make(_ env: TestEnvironment) -> (VolumeController, FeatureSettings) {
        let settings = FeatureSettings(featureID: "volume", store: env.settings)
        return (VolumeController(audio: env.audio, settings: settings), settings)
    }

    @Test func stepsAndShowsAHUD() {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        var huds: [IslandHUD] = []
        controller.onHUD = { huds.append($0) }

        controller.stepVolume(up: true)
        #expect(env.audio.state.outputVolume == 0.5625)
        #expect(huds.last?.id == "volume")
        #expect(huds.last?.level == 0.5625)
    }

    @Test func sliderChangesDontShowAHUD() {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        var huds: [IslandHUD] = []
        controller.onHUD = { huds.append($0) }
        controller.setVolume(0.3, source: .slider)
        #expect(env.audio.state.outputVolume == 0.3)
        #expect(huds.isEmpty)
    }

    @Test func limitPullsBackExternalChanges() {
        let env = TestEnvironment()
        let (controller, settings) = make(env)
        settings[VolumeSettings.volumeLimit] = 0.6
        env.audio.setVolume(0.9, for: .output)
        controller.receive(env.audio.state)
        #expect(env.audio.state.outputVolume == 0.6)
    }

    @Test func micMute() {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        var huds: [IslandHUD] = []
        controller.onHUD = { huds.append($0) }
        controller.toggleMicMute()
        #expect(env.audio.state.inputMuted)
        #expect(huds.last?.tint == .critical)
        controller.toggleMicMute()
        #expect(!env.audio.state.inputMuted)
    }

    @Test func autoSwitchesWhenAPreferredDeviceConnects() {
        let env = TestEnvironment()
        let (controller, settings) = make(env)
        settings[VolumeSettings.autoSwitchOutput] = true
        settings[VolumeSettings.outputPriority] = [PriorityDevice(uid: "airpods", name: "AirPods Pro")]
        controller.receive(env.audio.state)
        #expect(env.audio.state.defaultOutput?.uid == "speakers")

        env.audio.state.devices.append(FakeAudioService.airPods)
        controller.receive(env.audio.state)
        #expect(env.audio.state.defaultOutput?.uid == "airpods")
    }

    @Test func featureRegistersAScrollHandler() async throws {
        let env = TestEnvironment()
        let feature = VolumeFeature(context: env.makeContext(for: "volume"))
        try await feature.start()
        await env.settle()
        env.island.scroll(IslandScrollEvent(deltaY: 1, deltaX: 0, isPrecise: false, isFine: false))
        #expect(env.audio.state.outputVolume == 0.5625)
        await feature.stop()
        #expect(env.island.scrollHandlers.isEmpty)
    }

    @Test func outputByNameCommand() async throws {
        let env = TestEnvironment()
        env.audio.state.devices.append(FakeAudioService.airPods)
        let feature = VolumeFeature(context: env.makeContext(for: "volume"))
        try await feature.start()
        let command = try #require(feature.commands.first { $0.id == "volume.setOutput" })
        try await command.perform(CommandInvocation(argument: .text("airpods")))
        #expect(env.audio.state.defaultOutput?.uid == "airpods")
        await #expect(throws: VolumeError.self) {
            try await command.perform(CommandInvocation(argument: .text("nothing")))
        }
        await feature.stop()
    }
}
