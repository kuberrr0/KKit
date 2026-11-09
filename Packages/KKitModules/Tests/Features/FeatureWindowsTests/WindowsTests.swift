import CoreGraphics
import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureWindows

struct SnapGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    private let window = CGRect(x: 100, y: 100, width: 400, height: 300)

    @Test func halvesAndQuarters() {
        #expect(SnapGeometry.frame(for: .leftHalf, in: screen, current: window) == CGRect(x: 0, y: 0, width: 600, height: 800))
        #expect(SnapGeometry.frame(for: .rightHalf, in: screen, current: window) == CGRect(x: 600, y: 0, width: 600, height: 800))
        // AppKit coordinates: the top half has the higher y.
        #expect(SnapGeometry.frame(for: .topHalf, in: screen, current: window) == CGRect(x: 0, y: 400, width: 1200, height: 400))
        #expect(SnapGeometry.frame(for: .topLeft, in: screen, current: window) == CGRect(x: 0, y: 400, width: 600, height: 400))
        #expect(SnapGeometry.frame(for: .bottomRight, in: screen, current: window) == CGRect(x: 600, y: 0, width: 600, height: 400))
        #expect(SnapGeometry.frame(for: .maximize, in: screen, current: window) == screen)
    }

    @Test func halvesCycleThroughThirds() {
        #expect(SnapGeometry.frame(for: .leftHalf, in: screen, current: window, cycle: 1) == CGRect(x: 0, y: 0, width: 400, height: 800))
        #expect(SnapGeometry.frame(for: .leftHalf, in: screen, current: window, cycle: 2) == CGRect(x: 0, y: 0, width: 800, height: 800))
        #expect(SnapGeometry.frame(for: .leftHalf, in: screen, current: window, cycle: 3) == CGRect(x: 0, y: 0, width: 600, height: 800))
    }

    @Test func thirdsSplitTheLongSide() {
        #expect(SnapGeometry.frame(for: .centerThird, in: screen, current: window) == CGRect(x: 400, y: 0, width: 400, height: 800))
        let portrait = CGRect(x: 0, y: 0, width: 600, height: 900)
        #expect(SnapGeometry.frame(for: .firstThird, in: portrait, current: window) == CGRect(x: 0, y: 600, width: 600, height: 300))
    }

    @Test func centerKeepsTheSize() {
        #expect(SnapGeometry.frame(for: .center, in: screen, current: window) == CGRect(x: 400, y: 250, width: 400, height: 300))
    }

    @Test func gapsAreFullAtEdgesAndHalfBetweenWindows() {
        let left = SnapGeometry.frame(for: .leftHalf, in: screen, current: window, gap: 10)
        #expect(left == CGRect(x: 10, y: 10, width: 585, height: 780))
        let right = SnapGeometry.frame(for: .rightHalf, in: screen, current: window, gap: 10)
        #expect(right.minX - left.maxX == 10)
    }

    @Test func movingToAnotherScreenKeepsTheRelativePlace() {
        let target = CGRect(x: 1200, y: 0, width: 2400, height: 1600)
        #expect(SnapGeometry.move(window, from: screen, to: target) == CGRect(x: 1400, y: 200, width: 800, height: 600))
    }

    @Test func dragZones() {
        #expect(SnapGeometry.dragZone(for: CGPoint(x: 1, y: 400), screen: screen) == .leftHalf)
        #expect(SnapGeometry.dragZone(for: CGPoint(x: 1199, y: 400), screen: screen) == .rightHalf)
        #expect(SnapGeometry.dragZone(for: CGPoint(x: 600, y: 799), screen: screen) == .maximize)
        #expect(SnapGeometry.dragZone(for: CGPoint(x: 1, y: 790), screen: screen) == .topLeft)
        #expect(SnapGeometry.dragZone(for: CGPoint(x: 1190, y: 1), screen: screen) == .bottomRight)
        #expect(SnapGeometry.dragZone(for: CGPoint(x: 600, y: 1), screen: screen) == nil)
        #expect(SnapGeometry.dragZone(for: CGPoint(x: 600, y: 400), screen: screen) == nil)
    }

    @Test func resizeEdgesFollowTheNearestCorner() {
        let edges = SnapGeometry.resizeEdges(for: CGPoint(x: 110, y: 390), in: window, nearestCorner: true)
        #expect(edges == ResizeEdges(left: true, top: true))
        let side = SnapGeometry.resizeEdges(for: CGPoint(x: 490, y: 250), in: window, nearestCorner: true)
        #expect(side == ResizeEdges(right: true))
        #expect(SnapGeometry.resizeEdges(for: CGPoint(x: 110, y: 390), in: window, nearestCorner: false) == .bottomRight)
    }

    @Test func resizingKeepsAMinimumSize() {
        let smaller = SnapGeometry.resized(window, edges: .bottomRight, dx: -1000, dy: 1000)
        #expect(smaller.width == 160)
        #expect(smaller.height == 100)
        #expect(smaller.minX == window.minX)
        #expect(smaller.maxY == window.maxY)
    }

    @Test func screenIndexPicksTheLargestOverlap() {
        let screens = [screen, CGRect(x: 1200, y: 0, width: 1200, height: 800)]
        #expect(SnapGeometry.screenIndex(for: CGRect(x: 1000, y: 0, width: 600, height: 300), screens: screens) == 1)
        #expect(SnapGeometry.screenIndex(for: window, screens: screens) == 0)
    }

    @Test func snapActionNames() {
        #expect(SnapAction.named("left") == .leftHalf)
        #expect(SnapAction.named("Top Left") == .topLeft)
        #expect(SnapAction.named("max") == .maximize)
        #expect(SnapAction.named("lefthalf") == .leftHalf)
        #expect(SnapAction.named("nothing") == nil)
    }
}

@MainActor
struct LayoutMatcherTests {
    private func window(_ key: UInt64, _ bundleID: String, _ title: String, frame: CGRect = .zero) -> WindowInfo {
        WindowInfo(ref: WindowRef(pid: 1, key: key), title: title, appName: bundleID, bundleID: bundleID, frame: frame)
    }

    @Test func matchesByTitleThenOrder() {
        let layout = WindowLayout(name: "Coding", entries: [
            .init(bundleID: "editor", appName: "Editor", title: "b.swift", frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
            .init(bundleID: "editor", appName: "Editor", title: "gone.swift", frame: CGRect(x: 20, y: 0, width: 10, height: 10)),
            .init(bundleID: "browser", appName: "Browser", title: "", frame: CGRect(x: 40, y: 0, width: 10, height: 10)),
        ])
        let windows = [
            window(1, "editor", "a.swift"),
            window(2, "editor", "b.swift"),
            window(3, "browser", "Docs"),
            window(4, "chat", "Chat"),
        ]
        let assignments = Dictionary(uniqueKeysWithValues: LayoutMatcher.assignments(for: layout, windows: windows).map { ($0.0.key, $0.1) })
        #expect(assignments[2] == CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(assignments[1] == CGRect(x: 20, y: 0, width: 10, height: 10))
        #expect(assignments[3] == CGRect(x: 40, y: 0, width: 10, height: 10))
        #expect(assignments[4] == nil)
    }

    @Test func findsByPartOfTheName() {
        let layouts = [WindowLayout(name: "Coding", entries: []), WindowLayout(name: "Writing", entries: [])]
        #expect(LayoutMatcher.find("coding", in: layouts)?.name == "Coding")
        #expect(LayoutMatcher.find("wri", in: layouts)?.name == "Writing")
        #expect(LayoutMatcher.find("", in: layouts) == nil)
    }
}

@MainActor
struct WindowsControllerTests {
    private func make(_ env: TestEnvironment) -> (WindowsController, FeatureSettings) {
        let settings = FeatureSettings(featureID: "windows", store: env.settings)
        let controller = WindowsController(
            windows: env.windows,
            overlays: env.overlays,
            settings: settings,
            storage: FeatureStorage(featureID: "windows", service: env.storage),
            island: FeatureIsland(owner: "windows", service: env.island)
        )
        return (controller, settings)
    }

    /// The fake's main screen: visible frame 1512 × 944.
    private let original = CGRect(x: 100, y: 100, width: 600, height: 400)

    @Test func snapsCyclesAndRestores() async throws {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        env.windows.addWindow(key: 1, frame: original)

        try await controller.snapFocused(.leftHalf)
        #expect(env.windows.frame(of: 1) == CGRect(x: 0, y: 0, width: 756, height: 944))
        try await controller.snapFocused(.leftHalf)
        #expect(env.windows.frame(of: 1) == CGRect(x: 0, y: 0, width: 504, height: 944))
        try await controller.restoreFocused()
        #expect(env.windows.frame(of: 1) == original)
    }

    @Test func cyclingCanBeTurnedOff() async throws {
        let env = TestEnvironment()
        let (controller, settings) = make(env)
        settings[WindowsSettings.cycleSizes] = false
        env.windows.addWindow(key: 1, frame: original)
        try await controller.snapFocused(.rightHalf)
        try await controller.snapFocused(.rightHalf)
        #expect(env.windows.frame(of: 1) == CGRect(x: 756, y: 0, width: 756, height: 944))
    }

    @Test func toggleMaximize() async {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        let window = env.windows.addWindow(key: 1, frame: original)
        await controller.toggleMaximize(window)
        let maximized = CGRect(x: 0, y: 0, width: 1512, height: 944)
        #expect(env.windows.frame(of: 1) == maximized)
        var current = window
        current.frame = maximized
        await controller.toggleMaximize(current)
        #expect(env.windows.frame(of: 1) == original)
    }

    @Test func needsAccessibility() async {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        env.windows.addWindow(key: 1, frame: original)
        env.windows.isTrusted = false
        await #expect(throws: WindowError.self) {
            try await controller.snapFocused(.maximize)
        }
    }

    @Test func savesAndRestoresALayout() async throws {
        let env = TestEnvironment()
        let (controller, _) = make(env)
        env.windows.addWindow(key: 1, frame: original, title: "Notes", bundleID: "com.example.notes")
        env.windows.addWindow(key: 2, frame: CGRect(x: 800, y: 100, width: 500, height: 500), title: "Mail", bundleID: "com.example.mail")

        try await controller.saveLayout(named: "Desk")
        #expect(controller.layouts.map(\.name) == ["Desk"])
        #expect(env.island.huds.last?.id == "windows.layout")

        await env.windows.setFrame(CGRect(x: 0, y: 0, width: 300, height: 300), of: WindowRef(pid: 100, key: 1))
        await env.windows.setFrame(CGRect(x: 0, y: 0, width: 300, height: 300), of: WindowRef(pid: 100, key: 2))
        try await controller.restoreLayout(named: "desk")
        #expect(env.windows.frame(of: 1) == original)
        #expect(env.windows.frame(of: 2) == CGRect(x: 800, y: 100, width: 500, height: 500))

        // Saved to storage: a new controller loads it.
        let (reloaded, _) = make(env)
        reloaded.load()
        #expect(reloaded.layouts.map(\.name) == ["Desk"])

        await #expect(throws: WindowsError.self) {
            try await controller.restoreLayout(named: "nope")
        }
    }

    @Test func excludedAppsAreLeftOutOfLayouts() async throws {
        let env = TestEnvironment()
        let (controller, settings) = make(env)
        settings[WindowsSettings.excludedApps] = ["com.example.game"]
        env.windows.addWindow(key: 1, frame: original, bundleID: "com.example.game")
        await #expect(throws: WindowsError.self) {
            try await controller.saveLayout(named: "Empty")
        }
    }

    @Test func featureContributesSnapCommands() {
        let env = TestEnvironment()
        let feature = WindowsFeature(context: env.makeContext(for: "windows"))
        let ids = Set(feature.commands.map(\.id.rawValue))
        #expect(ids.contains("windows.leftHalf"))
        #expect(ids.contains("windows.snap"))
        #expect(ids.contains("windows.restoreLayout"))
        let left = feature.commands.first { $0.id == "windows.leftHalf" }
        #expect(left?.defaultShortcut == Shortcut(keyCode: Shortcut.Key.leftArrow, modifiers: [.control, .option]))
    }
}

@MainActor
struct WindowDragTests {
    @Test func modifiersArmTheMouse() async throws {
        let env = TestEnvironment()
        let feature = WindowsFeature(context: env.makeContext(for: "windows"))
        try await feature.start()
        await env.settle()
        // Drag-to-snap listens for left clicks; nothing else is tapped until ⌃⌥ is held.
        #expect(!env.input.tappedTypes.contains(.rightMouseDown))
        #expect(!env.input.tappedTypes.contains(.leftMouseDragged))
        env.input.sendFlags([.control, .option], keyCode: Shortcut.Key.leftControl)
        #expect(env.input.tappedTypes.contains(.rightMouseDown))
        #expect(env.input.tappedTypes.contains(.leftMouseDragged))
        env.input.sendFlags([], keyCode: Shortcut.Key.leftControl)
        #expect(!env.input.tappedTypes.contains(.rightMouseDown))
        await feature.stop()
        #expect(env.input.handlers(owner: "windows").isEmpty)
    }
}
