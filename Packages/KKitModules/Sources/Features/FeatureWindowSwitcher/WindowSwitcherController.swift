import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// The window switcher on the shared input tap: modifier + Tab opens it, Tab and the
/// arrows move, releasing the modifier switches. DESIGN.md §3.19.
///
/// The tap handler only looks at key codes and flags; the window list, previews and
/// switching run in tasks afterwards. The window list is fetched fresh on every opening
/// (no background polling). A quick ⌘Tab switches without the panel ever appearing:
/// the panel shows only once the modifier has been held for `showDelay`.
@MainActor
final class WindowSwitcherController {
    enum Phase: Equatable {
        case closed
        /// Open while the modifier is held, or until ↩, ⎋ or a click when `sticky`
        /// (opened by command).
        case open(sticky: Bool)
        /// The modifier came up before the window list arrived; switch when it does.
        case committing
    }

    let model = SwitcherModel()
    private(set) var phase: Phase = .closed

    private let input: FeatureInput
    private let windowService: any WindowService
    private let capture: any ScreenCaptureService
    private let overlays: any OverlayService
    private let settings: FeatureSettings
    private let apps: any SwitcherAppControlling

    private var keyToken: InputHandlerToken?
    private var mouseToken: InputHandlerToken?
    private var panel: (any OverlayHandle)?
    private var panelFrame: CGRect?
    /// Bumped on every opening and closing, so late results of an old one are dropped.
    private var session = 0
    /// Tab presses that arrived before the window list.
    private var pendingSteps = 0
    private var backwards = false
    private var frontmostPID: Int32?
    private var wantsPanel = false
    private var releasedAt = Date()
    private var mouseAtOpen = CGPoint.zero
    /// Key-ups to swallow because their key-down was the switcher's.
    private var swallowedKeyUps: Set<Int> = []
    /// Apps in the order they were last in front, most recent first.
    private(set) var recentPIDs: [Int32] = []
    private var thumbnailCache: [UInt32: CGImage] = [:]
    private var thumbnailOrder: [UInt32] = []
    private var settingTasks: [Task<Void, Never>] = []
    private var loadTask: Task<Void, Never>?
    private var showTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    // Settings, cached because the tap reads them on every key.
    private var takeOver = true
    private var trigger: Shortcut.Modifiers = .command

    /// How long modifier + Tab is held before the panel appears.
    var showDelay: Duration = .milliseconds(80)
    /// A switch that waits longer than this for the window list after the modifier came
    /// up is dropped; the user has moved on.
    static let maxCommitWait: TimeInterval = 1.5
    static let thumbnailCacheLimit = 40
    static let recentLimit = 64

    init(
        input: FeatureInput,
        windowService: any WindowService,
        capture: any ScreenCaptureService,
        overlays: any OverlayService,
        settings: FeatureSettings,
        apps: any SwitcherAppControlling
    ) {
        self.input = input
        self.windowService = windowService
        self.capture = capture
        self.overlays = overlays
        self.settings = settings
        self.apps = apps
    }

    var isOpen: Bool {
        if case .open = phase { true } else { false }
    }

    // MARK: Lifecycle

    func start() {
        keyToken = input.add(priority: .high, interests: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handle(event) ?? .pass
        }
        watch(WindowSwitcherSettings.takeOverShortcut) { controller, value in controller.takeOver = value }
        watch(WindowSwitcherSettings.modifier) { controller, value in controller.trigger = value.modifiers }
        if let frontmost = apps.frontmostPID {
            noteActivation(frontmost)
        }
        apps.observeActivations { [weak self] pid in
            self?.noteActivation(pid)
        }
    }

    func stop() {
        finish()
        settingTasks.forEach { $0.cancel() }
        settingTasks = []
        if let keyToken {
            input.remove(keyToken)
        }
        keyToken = nil
        apps.stopObserving()
        panel?.close()
        panel = nil
        thumbnailCache = [:]
        thumbnailOrder = []
        swallowedKeyUps = []
    }

    private func watch<Value: Codable & Sendable>(
        _ key: SettingKey<Value>,
        _ apply: @escaping @MainActor (WindowSwitcherController, Value) -> Void
    ) {
        let stream = settings.changes(of: key)
        apply(self, settings[key])
        settingTasks.append(Task { [weak self] in
            for await value in stream {
                guard let self else { return }
                apply(self, value)
            }
        })
    }

    func noteActivation(_ pid: Int32) {
        recentPIDs.removeAll { $0 == pid }
        recentPIDs.insert(pid, at: 0)
        if recentPIDs.count > Self.recentLimit {
            recentPIDs.removeLast(recentPIDs.count - Self.recentLimit)
        }
    }

    // MARK: The tap handler (must be quick)

    func handle(_ event: InputEvent) -> InputDecision {
        let keyCode = event.keyCode
        switch event.type {
        case .flagsChanged:
            if phase == .open(sticky: false), !event.modifiers.isSuperset(of: trigger) {
                commit()
            }
            return .pass
        case .keyDown:
            if isOpen {
                swallowedKeyUps.insert(keyCode)
                openKeyDown(event)
                return .consume
            }
            guard takeOver, keyCode == Shortcut.Key.tab, isTrigger(event.modifiers) else { return .pass }
            open(sticky: false, backwards: event.modifiers.contains(.shift))
            swallowedKeyUps.insert(keyCode)
            return .consume
        case .keyUp:
            if swallowedKeyUps.remove(keyCode) != nil || isOpen {
                return .consume
            }
            return .pass
        default:
            return .pass
        }
    }

    private func isTrigger(_ modifiers: Shortcut.Modifiers) -> Bool {
        !trigger.isEmpty && (modifiers == trigger || modifiers == trigger.union(.shift))
    }

    private func openKeyDown(_ event: InputEvent) {
        let isRepeat = event.isAutoRepeat
        switch event.keyCode {
        case Shortcut.Key.tab:
            step(event.modifiers.contains(.shift) ? -1 : 1)
        case Shortcut.Key.rightArrow:
            step(1)
        case Shortcut.Key.leftArrow:
            step(-1)
        case Shortcut.Key.downArrow:
            if model.isLoaded { model.moveRow(by: 1) }
        case Shortcut.Key.upArrow:
            if model.isLoaded { model.moveRow(by: -1) }
        case Shortcut.Key.returnKey, Shortcut.Key.space:
            if !isRepeat { commit() }
        case Shortcut.Key.escape:
            cancel()
        case Shortcut.Key.w:
            if !isRepeat { closeSelectedWindow() }
        case Shortcut.Key.q:
            if !isRepeat { quitSelectedApp() }
        case Shortcut.Key.h:
            if !isRepeat { hideSelectedApp() }
        default:
            break
        }
    }

    private func step(_ steps: Int) {
        if model.isLoaded {
            model.move(by: steps)
        } else {
            pendingSteps += steps
        }
    }

    // MARK: Opening and closing

    /// Opens the switcher. `sticky`: stays open without a modifier held (the command).
    func open(sticky: Bool, backwards: Bool = false) {
        if phase != .closed {
            finish()
        }
        session += 1
        let id = session
        phase = .open(sticky: sticky)
        pendingSteps = 0
        self.backwards = backwards
        frontmostPID = apps.frontmostPID
        wantsPanel = false
        mouseAtOpen = NSEvent.mouseLocation
        swallowedKeyUps = []
        model.reset()
        addMouseHandler()

        let service = windowService
        let includeMinimized = settings[WindowSwitcherSettings.includeMinimized]
        let includeHidden = settings[WindowSwitcherSettings.includeHiddenApps]
        loadTask = Task { [weak self] in
            let windows = await service.switchableWindows(includeMinimized: includeMinimized, includeHiddenApps: includeHidden)
            self?.loaded(windows, session: id)
        }
        let delay = sticky ? Duration.zero : showDelay
        showTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard let self, !Task.isCancelled, self.session == id else { return }
            self.wantsPanel = true
            self.showPanel(loadingPreviews: true)
        }
    }

    private func loaded(_ windows: [WindowInfo], session id: Int) {
        guard session == id, phase != .closed else { return }
        let items = SwitcherList.build(
            windows: windows,
            apps: apps.runningApps(),
            recentPIDs: recentPIDs,
            includeAppsWithoutWindows: settings[WindowSwitcherSettings.includeAppsWithoutWindows]
        )
        var icons: [Int32: NSImage] = [:]
        for pid in Set(items.map(\.pid)) {
            icons[pid] = apps.icon(for: pid)
        }
        let start = SwitcherList.initialIndex(for: items, frontmostPID: frontmostPID, backwards: backwards)
        model.load(items, selectedIndex: start, icons: icons)
        model.move(by: pendingSteps)
        pendingSteps = 0
        var cached: [UInt32: CGImage] = [:]
        for windowID in items.compactMap(\.windowID) {
            cached[windowID] = thumbnailCache[windowID]
        }
        model.thumbnails = cached

        if phase == .committing {
            if Date().timeIntervalSince(releasedAt) > Self.maxCommitWait {
                finish()
            } else {
                switchToSelection()
            }
            return
        }
        showPanel(loadingPreviews: true)
    }

    /// Switches to the selected tile (↩, releasing the modifier). Before the window
    /// list has arrived, the switch waits for it.
    func commit() {
        guard isOpen else { return }
        guard model.isLoaded else {
            phase = .committing
            releasedAt = Date()
            showTask?.cancel()
            wantsPanel = false
            panel?.hide()
            removeMouseHandler()
            return
        }
        switchToSelection()
    }

    /// Closes without switching (⎋, a click elsewhere).
    func cancel() {
        guard phase != .closed else { return }
        finish()
    }

    private func switchToSelection() {
        let item = model.selected
        finish()
        guard let item else { return }
        let service = windowService
        Task {
            if let window = item.window {
                await service.raise(window)
            } else {
                await service.activateApp(pid: item.pid)
            }
        }
    }

    private func finish() {
        phase = .closed
        session += 1
        loadTask?.cancel()
        showTask?.cancel()
        thumbnailTask?.cancel()
        loadTask = nil
        showTask = nil
        thumbnailTask = nil
        wantsPanel = false
        pendingSteps = 0
        panel?.hide()
        removeMouseHandler()
    }

    // MARK: The panel

    private func showPanel(loadingPreviews: Bool) {
        guard wantsPanel, model.isLoaded, isOpen else { return }
        if model.items.isEmpty, phase == .open(sticky: false) {
            // Nothing to switch to; ⌘Tab with no windows does nothing.
            return
        }
        let screen = panelScreen()
        let previews = settings[WindowSwitcherSettings.showPreviews]
        let layout = SwitcherLayout.make(
            count: model.items.count,
            preferredTileWidth: settings[WindowSwitcherSettings.previewSize].tileWidth,
            showsPreviews: previews,
            in: screen.visibleFrame.size
        )
        model.setLayout(layout, showsPreviews: previews)
        let frame = layout.frame(centeredIn: screen.visibleFrame)
        panelFrame = frame
        let configuration = OverlayConfiguration(
            level: .screenSaver,
            screen: .display(screen.id),
            placement: .frame(frame),
            acceptsKeyFocus: false,
            ignoresMouseEvents: false,
            hasShadow: true
        )
        if let panel {
            panel.setConfiguration(configuration)
        } else {
            let view = SwitcherView(
                model: model,
                onHover: { [weak self] id in self?.hovered(id) },
                onClick: { [weak self] id in self?.clicked(id) }
            )
            panel = overlays.makePanel(configuration, content: AnyView(view))
        }
        panel?.show()
        if previews, loadingPreviews {
            loadThumbnails(maxSize: layout.thumbnailSize)
        }
    }

    /// The screen with the cursor, like the Floating Bar.
    private func panelScreen() -> ScreenInfo {
        let screens = overlays.screens
        let mouse = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouse) }
            ?? screens.first(where: \.isMain)
            ?? screens.first
            ?? ScreenInfo(
                id: 0,
                name: "",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                notchHeight: 0,
                isMain: true
            )
    }

    private func loadThumbnails(maxSize: CGSize) {
        thumbnailTask?.cancel()
        let ids = model.items.compactMap(\.windowID)
        guard !ids.isEmpty else { return }
        let stream = capture.windowThumbnails(ids, maxSize: maxSize)
        let id = session
        thumbnailTask = Task { [weak self] in
            for await thumbnail in stream {
                guard let self, self.session == id, !Task.isCancelled else { return }
                self.model.thumbnails[thumbnail.windowID] = thumbnail.image.image
                self.remember(thumbnail.image.image, for: thumbnail.windowID)
            }
        }
    }

    /// Recent previews, so the next opening shows something straight away.
    private func remember(_ image: CGImage, for windowID: UInt32) {
        if thumbnailCache[windowID] == nil {
            thumbnailOrder.append(windowID)
        }
        thumbnailCache[windowID] = image
        while thumbnailOrder.count > Self.thumbnailCacheLimit {
            let dropped = thumbnailOrder.removeFirst()
            thumbnailCache[dropped] = nil
        }
    }

    private func hovered(_ id: SwitcherItem.ID) {
        guard isOpen else { return }
        // The tile that happens to be under a cursor that hasn't moved isn't a choice.
        guard NSEvent.mouseLocation != mouseAtOpen else { return }
        model.select(id: id)
    }

    private func clicked(_ id: SwitcherItem.ID) {
        guard isOpen else { return }
        model.select(id: id)
        switchToSelection()
    }

    // MARK: Clicks elsewhere

    private func addMouseHandler() {
        guard mouseToken == nil else { return }
        mouseToken = input.add(priority: .high, interests: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.mouseDown(at: event.location)
            return .pass
        }
    }

    private func removeMouseHandler() {
        if let mouseToken {
            input.remove(mouseToken)
        }
        mouseToken = nil
    }

    /// `location` in Core Graphics coordinates (top-left origin).
    private func mouseDown(at location: CGPoint) {
        guard isOpen else { return }
        let mainHeight = overlays.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? overlays.screens.first?.frame.height ?? 0
        let point = CGPoint(x: location.x, y: mainHeight - location.y)
        if let panelFrame, panel?.isVisible == true, panelFrame.contains(point) {
            return
        }
        cancel()
    }

    // MARK: Actions on the selected tile

    private func closeSelectedWindow() {
        guard model.isLoaded, let item = model.selected, let window = item.window else { return }
        model.remove { $0.id == item.id }
        let service = windowService
        Task { await service.close(window) }
        afterRemoving()
    }

    private func quitSelectedApp() {
        guard model.isLoaded, let item = model.selected else { return }
        apps.quit(item.pid)
        model.remove { $0.pid == item.pid }
        afterRemoving()
    }

    private func hideSelectedApp() {
        guard model.isLoaded, let item = model.selected else { return }
        apps.hide(item.pid)
        model.markHidden(pid: item.pid)
    }

    private func afterRemoving() {
        if model.items.isEmpty {
            cancel()
        } else if panel?.isVisible == true {
            showPanel(loadingPreviews: false)
        }
    }
}
