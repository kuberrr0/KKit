import AppKit
import KKitCore
import KKitServicesAPI
import Observation

enum WindowsError: LocalizedError {
    case noLayout(String)
    case nothingToSave

    var errorDescription: String? {
        switch self {
        case .noLayout(let name): String(localized: "There's no layout called “\(name)”.")
        case .nothingToSave: String(localized: "There are no windows to save.")
        }
    }
}

/// Snapping, restoring, moving between displays and saved layouts. DESIGN.md §3.12.
@MainActor
@Observable
final class WindowsController {
    private(set) var layouts: [WindowLayout] = []

    private let windows: any WindowService
    private let overlays: any OverlayService
    private let settings: FeatureSettings
    private let storage: FeatureStorage
    private let island: FeatureIsland
    /// Frames before KKit first moved each window, for Restore.
    @ObservationIgnored private var restoreFrames: [WindowHandle: CGRect] = [:]
    /// The last snap, so pressing the same shortcut again cycles sizes.
    @ObservationIgnored private var lastSnap: (action: SnapAction, window: WindowHandle, frame: CGRect, cycle: Int)?

    static let layoutsFile = "layouts"

    init(windows: any WindowService, overlays: any OverlayService, settings: FeatureSettings, storage: FeatureStorage, island: FeatureIsland) {
        self.windows = windows
        self.overlays = overlays
        self.settings = settings
        self.storage = storage
        self.island = island
    }

    func load() {
        layouts = (try? storage.read([WindowLayout].self, named: Self.layoutsFile)) ?? []
    }

    var screenFrames: [(frame: CGRect, visible: CGRect)] {
        overlays.screens.map { (frame: $0.frame, visible: $0.visibleFrame) }
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return settings[WindowsSettings.excludedApps].contains(bundleID)
    }

    // MARK: Snapping the focused window

    func snapFocused(_ action: SnapAction) async throws {
        let window = try await focusedWindow()
        await snap(window, to: action, cycling: settings[WindowsSettings.cycleSizes])
    }

    /// Moves `window` to `action` on the screen it's mostly on.
    func snap(_ window: WindowInfo, to action: SnapAction, cycling: Bool = false) async {
        let screens = screenFrames
        guard let index = SnapGeometry.screenIndex(for: window.frame, screens: screens.map(\.frame)) else { return }
        var cycle = 0
        if cycling, action.cycles, let last = lastSnap, last.action == action, last.window == window.ref,
           Self.isClose(last.frame, window.frame) {
            cycle = last.cycle + 1
        }
        let target = SnapGeometry.frame(
            for: action,
            in: screens[index].visible,
            current: window.frame,
            gap: CGFloat(max(settings[WindowsSettings.gap], 0)),
            cycle: cycle
        )
        rememberRestoreFrame(window)
        await windows.setFrame(target, of: window.ref)
        let landed = await windows.info(for: window.ref)?.frame ?? target
        lastSnap = (action: action, window: window.ref, frame: landed, cycle: cycle)
    }

    func restoreFocused() async throws {
        let window = try await focusedWindow()
        guard let frame = restoreFrames.removeValue(forKey: window.ref) else { return }
        lastSnap = nil
        await windows.setFrame(frame, of: window.ref)
    }

    /// Maximises, or restores a window that's already maximised (modifier + double-click).
    func toggleMaximize(_ window: WindowInfo) async {
        let screens = screenFrames
        guard let index = SnapGeometry.screenIndex(for: window.frame, screens: screens.map(\.frame)) else { return }
        let maximized = SnapGeometry.frame(for: .maximize, in: screens[index].visible, current: window.frame,
                                           gap: CGFloat(max(settings[WindowsSettings.gap], 0)))
        if Self.isClose(maximized, window.frame), let previous = restoreFrames.removeValue(forKey: window.ref) {
            await windows.setFrame(previous, of: window.ref)
        } else {
            rememberRestoreFrame(window)
            await windows.setFrame(maximized, of: window.ref)
        }
    }

    func moveFocusedToDisplay(next: Bool) async throws {
        let window = try await focusedWindow()
        let screens = screenFrames.sorted { $0.frame.minX < $1.frame.minX }
        guard screens.count > 1,
              let index = SnapGeometry.screenIndex(for: window.frame, screens: screens.map(\.frame)) else { return }
        let target = screens[(index + (next ? 1 : -1) + screens.count) % screens.count]
        rememberRestoreFrame(window)
        let frame = SnapGeometry.move(window.frame, from: screens[index].visible, to: target.visible)
        await windows.setFrame(frame, of: window.ref)
    }

    func resizeFocused(grow: Bool) async throws {
        let window = try await focusedWindow()
        let screens = screenFrames
        guard let index = SnapGeometry.screenIndex(for: window.frame, screens: screens.map(\.frame)) else { return }
        rememberRestoreFrame(window)
        await windows.setFrame(SnapGeometry.resize(window.frame, in: screens[index].visible, grow: grow), of: window.ref)
    }

    // MARK: Layouts

    func saveLayout(named name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let layoutName = trimmed.isEmpty ? String(localized: "Layout \(layouts.count + 1)") : trimmed
        let current = await windows.visibleWindows().filter { !isExcluded($0.bundleID) }
        var layout = LayoutMatcher.layout(named: layoutName, windows: current)
        guard !layout.entries.isEmpty else { throw WindowsError.nothingToSave }
        if let index = layouts.firstIndex(where: { $0.name.lowercased() == layoutName.lowercased() }) {
            layout.id = layouts[index].id
            layouts[index] = layout
        } else {
            layouts.append(layout)
        }
        persist()
        island.showHUD(IslandHUD(
            id: "windows.layout",
            symbol: "rectangle.3.group",
            title: String(localized: "Saved “\(layoutName)”"),
            detail: String(localized: "\(layout.entries.count) windows")
        ))
    }

    func restoreLayout(named name: String) async throws {
        guard let layout = LayoutMatcher.find(name, in: layouts) else { throw WindowsError.noLayout(name) }
        try await restoreLayout(id: layout.id)
    }

    func restoreLayout(id: UUID) async throws {
        guard let layout = layouts.first(where: { $0.id == id }) else { throw WindowsError.noLayout("") }
        let current = await windows.visibleWindows()
        for (window, frame) in LayoutMatcher.assignments(for: layout, windows: current) {
            await windows.setFrame(frame, of: window)
        }
    }

    func deleteLayout(_ id: UUID) {
        layouts.removeAll { $0.id == id }
        persist()
    }

    func renameLayout(_ id: UUID, to name: String) {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        layouts[index].name = name
        persist()
    }

    // MARK: Private

    private func focusedWindow() async throws -> WindowInfo {
        guard windows.isTrusted else { throw WindowError.needsAccessibility }
        guard let window = await windows.focusedWindow() else { throw WindowError.noWindow }
        return window
    }

    private func rememberRestoreFrame(_ window: WindowInfo) {
        if restoreFrames[window.ref] == nil {
            restoreFrames[window.ref] = window.frame
        }
        if restoreFrames.count > 200 {
            restoreFrames.removeAll()
        }
    }

    private func persist() {
        do {
            try storage.write(layouts, named: Self.layoutsFile)
        } catch {
            island.showHUD(IslandHUD(id: "windows.layout", symbol: "exclamationmark.triangle.fill",
                                     title: String(localized: "Couldn't save layouts"), tint: .warning))
        }
    }

    static func isClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
