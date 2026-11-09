import AppKit
import CoreGraphics
import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureWindowSwitcher

/// Running apps you set by hand.
@MainActor
final class FakeSwitcherApps: SwitcherAppControlling {
    var frontmostPID: Int32? = 100
    var apps: [SwitcherApp] = []
    private(set) var hiddenPIDs: [Int32] = []
    private(set) var quitPIDs: [Int32] = []
    private(set) var isObserving = false
    private var handler: (@MainActor @Sendable (Int32) -> Void)?

    func runningApps() -> [SwitcherApp] { apps }
    func icon(for pid: Int32) -> NSImage? { nil }
    func hide(_ pid: Int32) { hiddenPIDs.append(pid) }
    func quit(_ pid: Int32) { quitPIDs.append(pid) }

    func observeActivations(_ handler: @escaping @MainActor @Sendable (Int32) -> Void) {
        self.handler = handler
        isObserving = true
    }

    func stopObserving() {
        handler = nil
        isObserving = false
    }

    func activate(_ pid: Int32) {
        frontmostPID = pid
        handler?(pid)
    }
}

private func window(
    _ key: UInt64,
    pid: Int32,
    app: String = "App",
    title: String = "",
    minimized: Bool = false,
    hidden: Bool = false,
    windowID: UInt32? = nil
) -> WindowInfo {
    WindowInfo(
        ref: WindowHandle(pid: pid, key: key),
        title: title,
        appName: app,
        bundleID: "com.example.\(app.lowercased())",
        frame: CGRect(x: 0, y: 0, width: 800, height: 600),
        isMinimized: minimized,
        windowID: windowID,
        isAppHidden: hidden
    )
}

struct SwitcherListTests {
    @Test func visibleWindowsFirstThenTuckedAwayThenAppsByRecency() {
        let windows = [
            window(1, pid: 10, app: "Editor"),
            window(2, pid: 20, app: "Browser"),
            window(3, pid: 30, app: "Mail", minimized: true),
            window(4, pid: 40, app: "Notes", hidden: true),
            window(5, pid: 10, app: "Editor"),
        ]
        let apps = [
            SwitcherApp(pid: 10, name: "Editor", bundleID: nil, isHidden: false),
            SwitcherApp(pid: 50, name: "Finder", bundleID: nil, isHidden: false),
            SwitcherApp(pid: 60, name: "Music", bundleID: nil, isHidden: false),
        ]
        let items = SwitcherList.build(windows: windows, apps: apps, recentPIDs: [10, 60, 40, 20], includeAppsWithoutWindows: true)
        #expect(items.map(\.id) == ["w10-1", "w20-2", "w10-5", "w40-4", "w30-3", "a60", "a50"])
        #expect(items[3].isAppHidden)
        #expect(items[4].isMinimized)
        #expect(items[5].kind == .app)

        let windowsOnly = SwitcherList.build(windows: windows, apps: apps, recentPIDs: [], includeAppsWithoutWindows: false)
        #expect(windowsOnly.allSatisfy { $0.window != nil })
    }

    @Test func zeroWindowIDsAreDropped() {
        let item = SwitcherItem(window: window(1, pid: 1, windowID: 0))
        #expect(item.windowID == nil)
        #expect(SwitcherItem(window: window(1, pid: 1, windowID: 77)).windowID == 77)
    }

    @Test func untitledWindowsShowTheAppName() {
        #expect(SwitcherItem(window: window(1, pid: 1, app: "Terminal")).displayTitle == "Terminal")
        #expect(SwitcherItem(window: window(1, pid: 1, app: "Terminal", title: "zsh")).displayTitle == "zsh")
    }

    @Test func listIsCapped() {
        let windows = (0..<100).map { window(UInt64($0), pid: Int32($0)) }
        #expect(SwitcherList.build(windows: windows, apps: [], recentPIDs: [], includeAppsWithoutWindows: true).count == SwitcherList.limit)
    }

    @Test func initialSelectionIsThePreviousWindow() {
        let items = [window(1, pid: 10), window(2, pid: 20), window(3, pid: 30)].map(SwitcherItem.init(window:))
        #expect(SwitcherList.initialIndex(for: items, frontmostPID: 10, backwards: false) == 1)
        // The frontmost app (say, KKit's Settings) isn't in the list: start at the top.
        #expect(SwitcherList.initialIndex(for: items, frontmostPID: 99, backwards: false) == 0)
        #expect(SwitcherList.initialIndex(for: items, frontmostPID: 10, backwards: true) == 2)
        #expect(SwitcherList.initialIndex(for: Array(items.prefix(1)), frontmostPID: 10, backwards: false) == 0)
        #expect(SwitcherList.initialIndex(for: [], frontmostPID: 10, backwards: false) == 0)
    }
}

struct SwitcherLayoutTests {
    private let screen = CGSize(width: 1512, height: 944)

    @Test func fewWindowsUseThePreferredSizeInOneRow() {
        let layout = SwitcherLayout.make(count: 3, preferredTileWidth: 230, showsPreviews: true, in: screen)
        #expect(layout.columns == 3)
        #expect(layout.rows == 1)
        #expect(layout.tileSize.width == 230)
        #expect(layout.panelSize.width == 2 * SwitcherLayout.padding + 3 * 230 + 2 * SwitcherLayout.spacing)
        #expect(layout.thumbnailSize.width == 230 - 2 * SwitcherLayout.tileInset)
    }

    @Test func manyWindowsShrinkToFit() {
        let layout = SwitcherLayout.make(count: 30, preferredTileWidth: 310, showsPreviews: true, in: screen)
        #expect(layout.tileSize.width < 310)
        #expect(layout.panelSize.width <= screen.width * 0.9)
        #expect(layout.panelSize.height <= screen.height * 0.8)
        #expect(layout.columns * layout.rows >= 30)
        #expect(layout.visibleRows == layout.rows)
    }

    @Test func tooManyWindowsScroll() {
        let layout = SwitcherLayout.make(count: 60, preferredTileWidth: 230, showsPreviews: true, in: CGSize(width: 800, height: 600))
        #expect(layout.visibleRows < layout.rows)
        #expect(layout.panelSize.height <= 600 * 0.8)
    }

    @Test func iconsOnlyAreCompact() {
        let layout = SwitcherLayout.make(count: 4, preferredTileWidth: 310, showsPreviews: false, in: screen)
        #expect(layout.tileSize.width == SwitcherLayout.iconOnlyWidth)
        #expect(layout.thumbnailSize.height == SwitcherLayout.iconSize)
    }

    @Test func framesAreCentred() {
        let layout = SwitcherLayout.make(count: 2, preferredTileWidth: 230, showsPreviews: true, in: screen)
        let frame = layout.frame(centeredIn: CGRect(x: 1512, y: 0, width: 1512, height: 944))
        #expect(abs(frame.midX - (1512 + 756)) <= 1)
        #expect(abs(frame.midY - 472) <= 1)
    }
}

@MainActor
struct SwitcherModelTests {
    private func makeModel(count: Int, columns: Int) -> SwitcherModel {
        let model = SwitcherModel()
        let items = (0..<count).map { SwitcherItem(window: window(UInt64($0), pid: Int32($0))) }
        model.load(items, selectedIndex: 0, icons: [:])
        let layout = SwitcherLayout(
            columns: columns,
            rows: (count + columns - 1) / columns,
            visibleRows: 1,
            tileSize: .zero,
            thumbnailSize: .zero,
            panelSize: .zero
        )
        model.setLayout(layout, showsPreviews: true)
        return model
    }

    @Test func movingWraps() {
        let model = makeModel(count: 3, columns: 3)
        model.move(by: -1)
        #expect(model.selectedIndex == 2)
        model.move(by: 2)
        #expect(model.selectedIndex == 1)
        model.move(by: 7)
        #expect(model.selectedIndex == 2)
    }

    @Test func rowsMoveByTheColumnCount() {
        let model = makeModel(count: 7, columns: 3)
        model.moveRow(by: 1)
        #expect(model.selectedIndex == 3)
        model.moveRow(by: 1)
        #expect(model.selectedIndex == 6)
        model.moveRow(by: 1)
        #expect(model.selectedIndex == 6)
        model.moveRow(by: -1)
        #expect(model.selectedIndex == 3)
        // From the middle row's end down to the short last row: the last tile.
        model.move(by: 2)
        model.moveRow(by: 1)
        #expect(model.selectedIndex == 6)
        model.select(id: "w0-0")
        model.moveRow(by: -1)
        #expect(model.selectedIndex == 0)
    }

    @Test func removingKeepsTheSelection() {
        let model = makeModel(count: 4, columns: 4)
        model.select(id: "w2-2")
        model.remove { $0.id == "w0-0" }
        #expect(model.selected?.id == "w2-2")
        model.remove { $0.id == "w2-2" }
        #expect(model.selectedIndex == 1)
        #expect(model.items.count == 2)
    }
}

@MainActor
struct WindowSwitcherControllerTests {
    @MainActor
    private struct Setup {
        let env: TestEnvironment
        let apps: FakeSwitcherApps
        let feature: WindowSwitcherFeature
        var controller: WindowSwitcherController { feature.controller }
    }

    private func setUp() async throws -> Setup {
        let env = TestEnvironment(granted: [.accessibility])
        let apps = FakeSwitcherApps()
        env.windows.addWindow(key: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), title: "a.swift", appName: "Editor", pid: 100, windowID: 11)
        env.windows.addWindow(key: 2, frame: CGRect(x: 50, y: 50, width: 800, height: 600), title: "Docs", appName: "Browser", pid: 200, windowID: 22)
        env.windows.addWindow(key: 3, frame: CGRect(x: 90, y: 90, width: 800, height: 600), title: "Inbox", appName: "Mail", pid: 300, windowID: 33)
        let feature = WindowSwitcherFeature(context: env.makeContext(for: "windowSwitcher"), apps: apps)
        feature.controller.showDelay = .zero
        try await feature.start()
        await env.settle()
        return Setup(env: env, apps: apps, feature: feature)
    }

    private func pressCommandTab(_ env: TestEnvironment, shift: Bool = false) -> Bool {
        let modifiers: Shortcut.Modifiers = shift ? [.command, .shift] : [.command]
        env.input.sendFlags(modifiers, keyCode: Shortcut.Key.leftCommand)
        let consumed = env.input.sendKey(Shortcut.Key.tab, down: true, modifiers: modifiers)
        env.input.sendKey(Shortcut.Key.tab, down: false, modifiers: modifiers)
        return consumed
    }

    @Test func commandTabAndReleaseSwitchesToThePreviousWindow() async throws {
        let setup = try await setUp()
        let env = setup.env
        #expect(pressCommandTab(env))
        await env.settle(10)
        #expect(setup.controller.isOpen)
        #expect(setup.controller.model.selected?.window == WindowHandle(pid: 200, key: 2))
        // The panel is up with previews of every window.
        #expect(env.overlays.panels.first?.isVisible == true)
        #expect(env.screenCapture.thumbnailRequests.last == [11, 22, 33])
        #expect(setup.controller.model.thumbnails.count == 3)

        env.input.sendFlags([], keyCode: Shortcut.Key.leftCommand)
        await env.settle(10)
        #expect(!setup.controller.isOpen)
        #expect(env.windows.raised == [WindowHandle(pid: 200, key: 2)])
        #expect(env.overlays.panels.first?.isVisible == false)
    }

    @Test func tabMovesAndShiftTabGoesBack() async throws {
        let setup = try await setUp()
        let env = setup.env
        #expect(pressCommandTab(env))
        await env.settle(10)
        #expect(env.input.sendKey(Shortcut.Key.tab, down: true, modifiers: [.command]))
        env.input.sendKey(Shortcut.Key.tab, down: false, modifiers: [.command])
        #expect(setup.controller.model.selected?.window?.key == 3)
        // Wraps around.
        env.input.sendKey(Shortcut.Key.tab, down: true, modifiers: [.command])
        #expect(setup.controller.model.selected?.window?.key == 1)
        env.input.sendKey(Shortcut.Key.tab, down: true, modifiers: [.command, .shift])
        #expect(setup.controller.model.selected?.window?.key == 3)
        // Arrow keys too, and they never reach the app with ⌘ held.
        #expect(env.input.sendKey(Shortcut.Key.leftArrow, down: true, modifiers: [.command]))
        #expect(setup.controller.model.selected?.window?.key == 2)
        env.input.sendFlags([], keyCode: Shortcut.Key.leftCommand)
        await env.settle(10)
        #expect(env.windows.raised == [WindowHandle(pid: 200, key: 2)])
    }

    @Test func aQuickCommandTabSwitchesBeforeTheListArrives() async throws {
        let setup = try await setUp()
        let env = setup.env
        // Release ⌘ before the window list has been fetched.
        #expect(pressCommandTab(env))
        env.input.sendFlags([], keyCode: Shortcut.Key.leftCommand)
        #expect(setup.controller.phase == .committing)
        // Keys typed meanwhile go to the app again.
        #expect(!env.input.sendKey(Shortcut.Key.a, down: true))
        await env.settle(10)
        #expect(setup.controller.phase == .closed)
        #expect(env.windows.raised == [WindowHandle(pid: 200, key: 2)])
    }

    @Test func tabsBeforeTheListArriveStillCount() async throws {
        let setup = try await setUp()
        let env = setup.env
        #expect(pressCommandTab(env))
        env.input.sendKey(Shortcut.Key.tab, down: true, modifiers: [.command])
        env.input.sendKey(Shortcut.Key.tab, down: false, modifiers: [.command])
        await env.settle(10)
        #expect(setup.controller.model.selected?.window?.key == 3)
    }

    @Test func commandShiftTabStartsFromTheEnd() async throws {
        let setup = try await setUp()
        let env = setup.env
        #expect(pressCommandTab(env, shift: true))
        await env.settle(10)
        #expect(setup.controller.model.selected?.window?.key == 3)
    }

    @Test func escapeCancels() async throws {
        let setup = try await setUp()
        let env = setup.env
        #expect(pressCommandTab(env))
        await env.settle(10)
        #expect(env.input.sendKey(Shortcut.Key.escape, down: true, modifiers: [.command]))
        #expect(!setup.controller.isOpen)
        // The Escape key-up is swallowed too.
        #expect(env.input.sendKey(Shortcut.Key.escape, down: false, modifiers: [.command]))
        env.input.sendFlags([], keyCode: Shortcut.Key.leftCommand)
        await env.settle(10)
        #expect(env.windows.raised.isEmpty)
        // Clicks aren't watched once it's closed.
        #expect(!env.input.tappedTypes.contains(.leftMouseDown))
    }

    @Test func otherShortcutsPassThrough() async throws {
        let setup = try await setUp()
        let env = setup.env
        #expect(!env.input.sendKey(Shortcut.Key.tab, down: true))
        #expect(!env.input.sendKey(Shortcut.Key.tab, down: true, modifiers: [.option]))
        #expect(!env.input.sendKey(Shortcut.Key.tab, down: true, modifiers: [.command, .option]))
        #expect(!env.input.sendKey(Shortcut.Key.c, down: true, modifiers: [.command]))
        #expect(!setup.controller.isOpen)
    }

    @Test func theModifierAndTakeoverAreSettings() async throws {
        let setup = try await setUp()
        let env = setup.env
        let settings = FeatureSettings(featureID: "windowSwitcher", store: env.settings)
        settings[WindowSwitcherSettings.modifier] = .option
        await env.settle()
        #expect(!env.input.sendKey(Shortcut.Key.tab, down: true, modifiers: [.command]))
        #expect(env.input.sendKey(Shortcut.Key.tab, down: true, modifiers: [.option]))
        setup.controller.cancel()

        settings[WindowSwitcherSettings.takeOverShortcut] = false
        await env.settle()
        #expect(!env.input.sendKey(Shortcut.Key.tab, down: true, modifiers: [.option]))
    }

    @Test func appsWithoutWindowsAreActivated() async throws {
        let setup = try await setUp()
        let env = setup.env
        setup.apps.apps = [SwitcherApp(pid: 400, name: "Finder", bundleID: "com.apple.finder", isHidden: false)]
        #expect(pressCommandTab(env, shift: true))
        await env.settle(10)
        #expect(setup.controller.model.selected?.kind == .app)
        env.input.sendFlags([], keyCode: Shortcut.Key.leftCommand)
        await env.settle(10)
        #expect(env.windows.activatedApps == [400])
        #expect(env.windows.raised.isEmpty)
    }

    @Test func listOptionsComeFromSettings() async throws {
        let setup = try await setUp()
        let env = setup.env
        let settings = FeatureSettings(featureID: "windowSwitcher", store: env.settings)
        settings[WindowSwitcherSettings.includeMinimized] = false
        env.windows.addWindow(key: 4, frame: .zero, pid: 500, isMinimized: true)
        #expect(pressCommandTab(env))
        await env.settle(10)
        #expect(env.windows.switchableRequests.last?.includeMinimized == false)
        #expect(env.windows.switchableRequests.last?.includeHiddenApps == true)
        #expect(!setup.controller.model.items.contains { $0.pid == 500 })
        setup.controller.cancel()
    }

    @Test func closeQuitAndHideWhileOpen() async throws {
        let setup = try await setUp()
        let env = setup.env
        #expect(pressCommandTab(env))
        await env.settle(10)
        #expect(env.input.sendKey(Shortcut.Key.w, down: true, modifiers: [.command]))
        await env.settle()
        #expect(env.windows.closed == [WindowHandle(pid: 200, key: 2)])
        #expect(setup.controller.model.items.count == 2)
        #expect(setup.controller.isOpen)

        #expect(env.input.sendKey(Shortcut.Key.h, down: true, modifiers: [.command]))
        #expect(setup.apps.hiddenPIDs == [300])
        #expect(setup.controller.model.selected?.isAppHidden == true)

        #expect(env.input.sendKey(Shortcut.Key.q, down: true, modifiers: [.command]))
        #expect(setup.apps.quitPIDs == [300])
        #expect(setup.controller.model.items.count == 1)
        setup.controller.cancel()
    }

    @Test func theCommandOpensAStickySwitcher() async throws {
        let setup = try await setUp()
        let env = setup.env
        let command = setup.feature.commands.first { $0.id == "windowSwitcher.show" }
        try await command?.perform(CommandInvocation())
        await env.settle(10)
        #expect(setup.controller.phase == .open(sticky: true))
        #expect(env.overlays.panels.first?.isVisible == true)
        // No modifier is held, so modifier changes don't close it.
        env.input.sendFlags([], keyCode: Shortcut.Key.leftCommand)
        #expect(setup.controller.isOpen)
        #expect(env.input.sendKey(Shortcut.Key.rightArrow, down: true))
        #expect(env.input.sendKey(Shortcut.Key.returnKey, down: true))
        await env.settle(10)
        #expect(!setup.controller.isOpen)
        #expect(env.windows.raised == [WindowHandle(pid: 300, key: 3)])
    }

    @Test func previewsCanBeTurnedOff() async throws {
        let setup = try await setUp()
        let env = setup.env
        let settings = FeatureSettings(featureID: "windowSwitcher", store: env.settings)
        settings[WindowSwitcherSettings.showPreviews] = false
        #expect(pressCommandTab(env))
        await env.settle(10)
        #expect(env.screenCapture.thumbnailRequests.isEmpty)
        #expect(!setup.controller.model.showsPreviews)
        setup.controller.cancel()
    }

    @Test func activationsAreRemembered() async throws {
        let setup = try await setUp()
        #expect(setup.apps.isObserving)
        #expect(setup.controller.recentPIDs == [100])
        setup.apps.activate(300)
        setup.apps.activate(200)
        setup.apps.activate(300)
        #expect(setup.controller.recentPIDs == [300, 200, 100])
    }

    @Test func stoppingRemovesEverything() async throws {
        let setup = try await setUp()
        let env = setup.env
        #expect(pressCommandTab(env))
        await env.settle(10)
        await setup.feature.stop()
        #expect(env.input.handlers(owner: "windowSwitcher").isEmpty)
        #expect(env.overlays.openPanels.isEmpty)
        #expect(!setup.apps.isObserving)
        #expect(!setup.controller.isOpen)
    }

    @Test func manifest() {
        let manifest = WindowSwitcherFeature.manifest
        #expect(manifest.id == "windowSwitcher")
        #expect(manifest.requiredPermissions == [.accessibility])
        #expect(manifest.optionalPermissions == [.screenRecording])
    }
}
