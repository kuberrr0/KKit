import CoreGraphics
import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureMenuBarManager

@MainActor
struct MenuBarManagerTests {
    /// On the fake built-in screen's menu bar (982 pt tall, 38 pt menu bar).
    static let onMenuBar = CGPoint(x: 500, y: 970)
    static let onDesktop = CGPoint(x: 500, y: 400)

    @MainActor
    final class Pointer {
        var location = MenuBarManagerTests.onDesktop
    }

    private func make(_ env: TestEnvironment, pointer: Pointer = Pointer()) -> (MenuBarManagerController, FeatureSettings) {
        let settings = FeatureSettings(featureID: "menuBarManager", store: env.settings)
        let controller = MenuBarManagerController(
            service: env.menuBarItems,
            input: FeatureInput(owner: "menuBarManager", service: env.input),
            overlays: env.overlays,
            screenCapture: env.screenCapture,
            permissions: env.permissions,
            settings: settings,
            revealDelay: .zero,
            pointerLocation: { pointer.location }
        )
        return (controller, settings)
    }

    @Test func accessibilityComesFromThePermissionsService() {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        env.permissions.statuses[.accessibility] = .denied
        #expect(!controller.hasAccessibility)
        env.permissions.statuses[.accessibility] = .granted
        #expect(controller.hasAccessibility)
    }

    @Test func startPutsTheDividersInAndStopTakesThemOut() async {
        let env = TestEnvironment()
        let (controller, settings) = make(env)
        controller.start()
        await env.settle()
        #expect(env.menuBarItems.isInstalled)
        #expect(env.menuBarItems.hasAlwaysHiddenSection)

        settings[MenuBarManagerSettings.alwaysHiddenSection] = false
        await env.settle()
        #expect(env.menuBarItems.isInstalled)
        #expect(!env.menuBarItems.hasAlwaysHiddenSection)

        controller.stop()
        #expect(!env.menuBarItems.isInstalled)
        #expect(env.input.handlers(owner: "menuBarManager").isEmpty)
    }

    @Test func chevronShowsAndHidesInPlace() async {
        let env = TestEnvironment()
        let (controller, settings) = make(env)
        settings[MenuBarManagerSettings.openStyle] = .inPlace
        controller.start()
        await env.settle()

        env.menuBarItems.sendChevron(.click(alternate: false))
        #expect(env.menuBarItems.revealed == [.hidden])
        #expect(controller.isShowingHidden)

        env.menuBarItems.sendChevron(.click(alternate: false))
        #expect(env.menuBarItems.revealed.isEmpty)

        // ⌥-click shows the Always Hidden section too.
        env.menuBarItems.sendChevron(.click(alternate: true))
        #expect(env.menuBarItems.revealed == [.hidden, .alwaysHidden])
        controller.stop()
    }

    @Test func hoverOnlyShowsWhenAskedTo() async {
        let env = TestEnvironment()
        let (controller, settings) = make(env)
        settings[MenuBarManagerSettings.openStyle] = .inPlace
        controller.start()
        await env.settle()

        env.menuBarItems.sendChevron(.hover)
        #expect(env.menuBarItems.revealed.isEmpty)

        settings[MenuBarManagerSettings.revealOn] = .hover
        env.menuBarItems.sendChevron(.hover)
        #expect(env.menuBarItems.revealed == [.hidden])
        controller.stop()
    }

    @Test func notchedScreensGetTheDropDownBar() async throws {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        env.menuBarItems.addIcon("wifi", appName: "Control Center", title: "Wi-Fi", section: .shown, x: 1300)
        env.menuBarItems.addIcon("dropbox", appName: "Dropbox", section: .hidden, x: -9000)
        env.menuBarItems.addIcon("docker", appName: "Docker", section: .hidden, x: -9030)
        env.menuBarItems.addIcon("vpn", appName: "VPN", section: .alwaysHidden, x: -19000)
        controller.start()
        await env.settle()
        // The fake built-in screen has a notch, so "automatic" means the drop-down bar.
        #expect(controller.usesDropDownBar)

        await controller.showDropDown()
        #expect(controller.isDropDownVisible)
        #expect(env.menuBarItems.revealed.isEmpty)
        #expect(controller.dropDownGroups.map { $0.map(\.id) } == [["dropbox", "docker"], ["vpn"]])

        let panel = try #require(env.overlays.openPanels.first)
        #expect(panel.configuration.level == .statusBar)
        guard case .frame(let frame) = panel.configuration.placement else {
            Issue.record("The drop-down bar should be placed by frame")
            return
        }
        // Under the 38 pt menu bar, its right edge near the chevron (maxX 1220).
        #expect(frame.maxY <= 982 - 38)
        #expect(abs(frame.maxX - 1228) < 1)
        #expect(frame.width == DropDownBarView.size(for: [2, 1], hasMessage: false).width)

        controller.toggle()
        #expect(!controller.isDropDownVisible)
        controller.stop()
    }

    @Test func iconsBehindTheNotchGoInTheDropDownBar() async {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        var icon = env.menuBarItems.addIcon("slack", appName: "Slack", section: .shown, x: 700)
        icon.isOnScreen = false
        env.menuBarItems.iconList = [icon]
        env.menuBarItems.addIcon("wifi", appName: "Control Center", title: "Wi-Fi", section: .shown, x: 1300)
        await controller.refreshIcons()
        #expect(controller.dropDownGroups.map { $0.map(\.id) } == [["slack"]])
    }

    @Test func openingAHiddenIconShowsItsSectionFirst() async throws {
        let env = TestEnvironment()
        let (controller, settings) = make(env)
        settings[MenuBarManagerSettings.autoHideDelay] = 0
        let hidden = env.menuBarItems.addIcon("dropbox", appName: "Dropbox", section: .hidden, x: -9000)
        let alwaysHidden = env.menuBarItems.addIcon("vpn", appName: "VPN", section: .alwaysHidden, x: -19000)
        controller.start()
        await env.settle()

        try await controller.open(hidden)
        #expect(env.menuBarItems.pressed.map(\.id) == ["dropbox"])
        #expect(env.menuBarItems.revealedWhenPressed.last == [.hidden])
        #expect(env.menuBarItems.pressed.last?.isOnScreen == true)

        controller.hideAll()
        try await controller.open(alwaysHidden)
        #expect(env.menuBarItems.revealedWhenPressed.last == [.hidden, .alwaysHidden])
        controller.stop()
    }

    @Test func openingAShownIconDoesntChangeAnything() async throws {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        let wifi = env.menuBarItems.addIcon("wifi", appName: "Control Center", title: "Wi-Fi", section: .shown, x: 1300)
        controller.start()
        await env.settle()
        try await controller.open(wifi)
        #expect(env.menuBarItems.revealHistory.isEmpty)
        #expect(env.menuBarItems.pressed.map(\.id) == ["wifi"])
        controller.stop()
    }

    @Test func pressFailuresAreReported() async {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        let wifi = env.menuBarItems.addIcon("wifi", section: .shown)
        env.menuBarItems.pressError = MenuBarItemsError.iconGone
        await #expect(throws: MenuBarItemsError.self) {
            try await controller.open(wifi)
        }
        #expect(controller.lastError == MenuBarItemsError.iconGone.message)
    }

    @Test func holdingCommandOverTheMenuBarShowsEverything() async throws {
        let env = TestEnvironment()
        let pointer = Pointer()
        let (controller, settings) = make(env, pointer: pointer)
        settings[MenuBarManagerSettings.autoHideDelay] = 0
        controller.start()
        await env.settle()
        #expect(env.input.handlers(owner: "menuBarManager").first?.interests == [.flagsChanged])

        // Not over the menu bar: nothing.
        env.input.sendFlags([.command], keyCode: Shortcut.Key.leftCommand)
        await env.settle()
        #expect(env.menuBarItems.revealed.isEmpty)
        env.input.sendFlags([], keyCode: Shortcut.Key.leftCommand)

        pointer.location = Self.onMenuBar
        // ⌘ is handed on to other apps.
        #expect(!env.input.sendFlags([.command], keyCode: Shortcut.Key.leftCommand))
        await env.settle()
        #expect(env.menuBarItems.revealed == [.hidden, .alwaysHidden])
        #expect(controller.shouldPostponeHiding)

        env.input.sendFlags([], keyCode: Shortcut.Key.leftCommand)
        try await Task.sleep(for: .milliseconds(450))
        #expect(env.menuBarItems.revealed.isEmpty)

        settings[MenuBarManagerSettings.showAllWithCommand] = false
        await env.settle()
        #expect(env.input.handlers(owner: "menuBarManager").isEmpty)
        controller.stop()
    }

    @Test func hidesAgainAfterTheDelayUnlessAMenuIsOpen() async throws {
        let env = TestEnvironment()
        let (controller, settings) = make(env)
        settings[MenuBarManagerSettings.openStyle] = .inPlace
        settings[MenuBarManagerSettings.autoHideDelay] = 1
        controller.start()
        await env.settle()

        env.menuBarItems.isMenuOpen = true
        controller.toggle()
        #expect(env.menuBarItems.revealed == [.hidden])
        try await Task.sleep(for: .milliseconds(1300))
        #expect(env.menuBarItems.revealed == [.hidden])

        env.menuBarItems.isMenuOpen = false
        try await Task.sleep(for: .milliseconds(1300))
        #expect(env.menuBarItems.revealed.isEmpty)
        controller.stop()
    }

    @Test func movingFromSettingsChangesTheSection() async {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        env.menuBarItems.addIcon("dropbox", appName: "Dropbox", section: .shown)
        env.menuBarItems.addIcon("clock", appName: "Control Center", title: "Clock", section: .shown, canMove: false)
        await controller.refreshIcons()

        await controller.move(id: "dropbox", to: .hidden)
        #expect(controller.icons(in: .hidden).map(\.id) == ["dropbox"])
        #expect(controller.lastError == nil)

        await controller.move(id: "clock", to: .hidden)
        #expect(controller.icons(in: .shown).map(\.id) == ["clock"])
        #expect(controller.lastError == MenuBarItemsError.cannotMove.message)
    }

    @Test func picturesNeedScreenRecording() async {
        let env = TestEnvironment()
        let (controller, settings) = make(env)
        env.menuBarItems.addIcon("wifi", appName: "Control Center", title: "Wi-Fi", windowID: 77)
        env.menuBarItems.addIcon("dropbox", appName: "Dropbox", section: .hidden, windowID: 78)
        await controller.refreshIcons()
        #expect(controller.images.isEmpty)
        #expect(env.screenCapture.captures.isEmpty)

        env.permissions.set(.granted, for: .screenRecording)
        await controller.refreshIcons()
        // Only icons on screen can be pictured.
        #expect(Set(controller.images.keys) == ["wifi"])
        #expect(env.screenCapture.captures == [.window(77)])

        settings[MenuBarManagerSettings.showsIconImages] = false
        env.menuBarItems.reveal([.hidden])
        await controller.refreshIcons()
        #expect(controller.images["dropbox"] == nil)
    }

    @Test func listingNeedsAccessibility() async {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        env.menuBarItems.addIcon("wifi")
        env.menuBarItems.isTrusted = false
        await controller.refreshIcons()
        #expect(controller.icons.isEmpty)
        #expect(await controller.searchableIcons().isEmpty)

        env.menuBarItems.isTrusted = true
        #expect(await controller.searchableIcons().map(\.id) == ["wifi"])
    }

    @Test func dropDownBarSize() {
        #expect(DropDownBarView.size(for: [], hasMessage: true) == DropDownBarView.messageSize)
        let size = DropDownBarView.size(for: [3, 2], hasMessage: false)
        // Padding both sides, five 30 pt cells, one separator.
        let width: CGFloat = 12 + 150 + 9
        let height: CGFloat = 38
        #expect(size.width == width)
        #expect(size.height == height)
        #expect(DropDownBarView.size(for: [200], hasMessage: false).width == DropDownBarView.maximumWidth)
    }

    @Test func featureRegistersItsCommandsAndPublishesIcons() async throws {
        let env = TestEnvironment()
        let manager = env.makeFeatureManager(catalog: [MenuBarManagerFeature.self])
        await manager.startEnabledFeatures()
        #expect(manager.runningFeatures.isEmpty, "It's off by default")

        await manager.setEnabled(true, for: "menuBarManager")
        #expect(manager.runningFeatures.count == 1)
        for id in ["menuBarManager.toggle", "menuBarManager.showAll", "menuBarManager.dropDown", "menuBarManager.hide"] {
            #expect(env.commands.command(CommandID(id)) != nil)
        }
        #expect(env.services.resolve((any MenuBarIconsServicing).self) != nil)
        await env.settle()
        #expect(env.menuBarItems.isInstalled)

        await manager.setEnabled(false, for: "menuBarManager")
        #expect(env.services.resolve((any MenuBarIconsServicing).self) == nil)
        #expect(!env.menuBarItems.isInstalled)
    }
}
