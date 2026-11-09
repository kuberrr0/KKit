import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureToggles

@MainActor
struct TogglesTests {
    private func make(_ env: TestEnvironment) -> (ToggleController, DesktopCover) {
        let desktop = DesktopCover(overlays: env.overlays, actions: env.systemActions)
        return (ToggleController(actions: env.systemActions, desktop: desktop), desktop)
    }

    @Test func switchesFlip() async throws {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        #expect(controller.isOn(.darkMode) == false)
        try await controller.perform(.darkMode)
        #expect(controller.isOn(.darkMode) == true)
        try await controller.perform(.wifi)
        #expect(env.systemActions.actions == ["darkMode=true", "wifi=false"])
        #expect(controller.isOn(.lockScreen) == nil)
    }

    @Test func wifiUnavailableWithoutHardware() {
        let env = TestEnvironment()
        env.systemActions.isWiFiOn = nil
        let (controller, _) = make(env)
        #expect(!controller.isAvailable(.wifi))
        #expect(controller.isAvailable(.darkMode))
    }

    @Test func hideDesktopIconsCoversEveryScreen() async throws {
        let env = TestEnvironment()
        let (controller, desktop) = make(env)
        try await controller.perform(.hideDesktopIcons)
        #expect(desktop.isHidingIcons)
        let open = env.overlays.panels.filter { !$0.isClosed }
        #expect(open.count == env.overlays.screens.count)
        #expect(open.allSatisfy { $0.isVisible && $0.configuration.level == .aboveDesktopIcons && $0.configuration.ignoresMouseEvents })

        try await controller.perform(.hideDesktopIcons)
        #expect(env.overlays.panels.allSatisfy(\.isClosed))
    }

    @Test func failuresShowAHUDAndThrow() async {
        let env = TestEnvironment()
        env.systemActions.failure = SystemActionError("Not allowed")
        let (controller, _) = make(env)
        var huds: [IslandHUD] = []
        controller.onHUD = { huds.append($0) }
        await #expect(throws: SystemActionError.self) {
            try await controller.perform(.emptyTrash)
        }
        #expect(huds.last?.title == "Not allowed")
        #expect(controller.busy.isEmpty)
    }

    @Test func tilesFollowTheSetting() async throws {
        let env = TestEnvironment()
        let context = env.makeContext(for: "quickToggles")
        let feature = TogglesFeature(context: context)
        try await feature.start()
        #expect(feature.quickToggles.map(\.id) == ToggleSettings.tiles.defaultValue.map(\.commandID))

        context.settings[ToggleSettings.tiles] = [.lockScreen, .darkMode]
        #expect(feature.quickToggles.map(\.title) == ["Lock Screen", "Dark Mode"])
        #expect(feature.commands.count == SystemToggle.allCases.count)
        #expect(feature.commands.allSatisfy { $0.id.featureID == "quickToggles" })
        await feature.stop()
    }
}
