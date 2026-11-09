import CoreGraphics
import Foundation
import KKitServicesAPI
import Testing
@testable import KKitServices

struct MenuBarLayoutTests {
    // AppKit coordinates on a 1512 × 982 screen; the menu bar is y 958…982.
    /// Both sections hidden: the chevron and the Always Hidden divider are 10 000 pt
    /// long, the chevron's arrow at its right end (maxX 1120).
    static let collapsed = MenuBarLayout(
        chevron: CGRect(x: 1120 - 10_000, y: 958, width: 10_000, height: 24),
        alwaysHiddenDivider: CGRect(x: 1120 - 10_000 - 60 - 10_000, y: 958, width: 10_000, height: 24)
    )

    /// Everything showing: a 20 pt chevron and a 12 pt divider.
    static let chevron = CGRect(x: 1100, y: 958, width: 20, height: 24)
    static let expanded = MenuBarLayout(
        chevron: chevron,
        alwaysHiddenDivider: CGRect(x: 1000, y: 958, width: 12, height: 24)
    )

    static func icon(at x: CGFloat) -> CGRect {
        CGRect(x: x, y: 958, width: 24, height: 24)
    }

    @Test func sectionsWhileCollapsed() {
        let layout = Self.collapsed
        #expect(layout.section(of: Self.icon(at: 1200)) == .shown)
        #expect(layout.section(of: Self.icon(at: 1121)) == .shown)
        // Hidden icons sit just left of the long chevron.
        #expect(layout.section(of: Self.icon(at: 1120 - 10_000 - 30)) == .hidden)
        // Always-hidden ones are left of the Always Hidden divider too.
        #expect(layout.section(of: Self.icon(at: 1120 - 30_000)) == .alwaysHidden)
        #expect(!layout.isOutOfOrder)
    }

    @Test func sectionsWhileExpanded() {
        let layout = Self.expanded
        #expect(layout.section(of: Self.icon(at: 1130)) == .shown)
        // Anything left of the chevron is hidden, right up against it too.
        #expect(layout.section(of: Self.icon(at: 1076)) == .hidden)
        #expect(layout.section(of: Self.icon(at: 1040)) == .hidden)
        #expect(layout.section(of: Self.icon(at: 950)) == .alwaysHidden)
    }

    @Test func withoutAnAlwaysHiddenDividerEverythingLeftIsHidden() {
        var layout = Self.expanded
        layout.alwaysHiddenDivider = nil
        #expect(layout.section(of: Self.icon(at: 100)) == .hidden)
        #expect(MenuBarLayout().section(of: Self.icon(at: 100)) == .shown)
    }

    @Test func outOfOrder() {
        var layout = Self.expanded
        layout.alwaysHiddenDivider = CGRect(x: 1150, y: 958, width: 12, height: 24)
        #expect(layout.isOutOfOrder)
        layout.alwaysHiddenDivider = nil
        #expect(!layout.isOutOfOrder)
    }

    @Test func dropPoints() throws {
        let layout = Self.expanded
        let shown = try #require(layout.dropPoint(for: .shown, y: 970))
        #expect(shown.y == 970)
        #expect(shown.x > Self.chevron.maxX)
        let hidden = try #require(layout.dropPoint(for: .hidden, y: 970))
        #expect(hidden.x < Self.chevron.minX)
        #expect(hidden.x > Self.chevron.minX - 6)
        let alwaysHidden = try #require(layout.dropPoint(for: .alwaysHidden, y: 970))
        #expect(alwaysHidden.x < 1000)
        var noAlwaysHidden = layout
        noAlwaysHidden.alwaysHiddenDivider = nil
        #expect(noAlwaysHidden.dropPoint(for: .alwaysHidden, y: 970) == nil)
    }

    @Test func onScreenAndTheNotch() {
        let notch = MenuBarScreen.notch(
            topLeft: CGRect(x: 0, y: 950, width: 662, height: 32),
            topRight: CGRect(x: 850, y: 950, width: 662, height: 32)
        )
        #expect(notch == CGRect(x: 662, y: 950, width: 188, height: 32))
        let screens = [MenuBarScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notch: notch)]
        #expect(MenuBarGeometry.isOnScreen(Self.icon(at: 1000), screens: screens))
        #expect(!MenuBarGeometry.isOnScreen(Self.icon(at: 700), screens: screens), "Under the notch")
        #expect(!MenuBarGeometry.isOnScreen(Self.icon(at: -9000), screens: screens), "Pushed off the screen")
        #expect(!MenuBarGeometry.isOnScreen(.zero, screens: screens))
        #expect(MenuBarScreen.notch(topLeft: nil, topRight: nil) == nil)
    }

    @Test func matchesWindowsByFrame() {
        let windows = [
            MenuBarGeometry.StatusWindow(id: 10, pid: 5, bounds: CGRect(x: 1200, y: 0, width: 24, height: 24)),
            MenuBarGeometry.StatusWindow(id: 11, pid: 6, bounds: CGRect(x: 1230, y: 0, width: 30, height: 24)),
        ]
        #expect(MenuBarGeometry.windowID(for: CGRect(x: 1200.5, y: 0, width: 24, height: 24), pid: 5, in: windows) == 10)
        // macOS 26 may report another owner: the frame alone is enough.
        #expect(MenuBarGeometry.windowID(for: CGRect(x: 1230, y: 0, width: 30, height: 24), pid: 99, in: windows) == 11)
        #expect(MenuBarGeometry.windowID(for: CGRect(x: 500, y: 0, width: 24, height: 24), pid: 5, in: windows) == nil)
    }

    @Test func iconKeysAreUniqueAndStable() {
        let keys = MenuBarGeometry.keys(prefix: "com.example", entries: [
            (identifier: "com.example.item", title: "Sync"),
            (identifier: nil, title: "Status"),
            (identifier: nil, title: ""),
            (identifier: nil, title: "Status"),
        ])
        #expect(keys == ["com.example/com.example.item", "com.example/Status", "com.example/#2", "com.example/Status#3"])
        #expect(Set(keys).count == keys.count)
    }

    @Test func theClockStaysPut() {
        #expect(!MenuBarGeometry.canMove(bundleID: "com.apple.controlcenter", identifier: "com.apple.menuextra.clock"))
        #expect(MenuBarGeometry.canMove(bundleID: "com.apple.controlcenter", identifier: "com.apple.menuextra.wifi"))
        #expect(MenuBarGeometry.canMove(bundleID: "com.getdropbox.dropbox", identifier: nil))
    }

    @Test func spacingChoices() {
        #expect(MenuBarIconSpacing.system.values == nil)
        #expect(MenuBarIconSpacing.allCases.compactMap { $0.values?.spacing } == [12, 8, 4])
    }
}
