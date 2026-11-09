import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// The Island: a black panel drawn over the notch that grows "ears" for live
/// activities, shows HUDs, and expands into pages on hover or click. On screens
/// without a notch it's a pill that only appears when there's something to show.
///
/// It implements `IslandService`, which features reach through `context.island`.
@MainActor
public final class IslandHost: IslandService {
    public let model = IslandModel()

    private let dependencies: HostDependencies
    private let events: EventBus
    private let settings: FeatureSettings
    private var panels: [UInt32: IslandPanel] = [:]
    private var scrollHandlers: [(owner: FeatureID, handler: @MainActor (IslandScrollEvent) -> Void)] = []
    private var transientTasks: [UUID: Task<Void, Never>] = [:]
    private var hudTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    private var tasks: [Task<Void, Never>] = []
    private var horizontalScroll: CGFloat = 0

    public init(dependencies: HostDependencies, events: EventBus) {
        self.dependencies = dependencies
        self.events = events
        self.settings = FeatureSettings(featureID: IslandSettings.owner, store: dependencies.settings)
        observe()
        rebuildPanels()
    }

    /// The Island's own settings, for the Settings page.
    public var islandSettings: FeatureSettings { settings }

    // MARK: IslandService

    @discardableResult
    public func present(_ activity: IslandActivity, owner: FeatureID) -> any IslandHandle {
        let token = model.upsert(activity, owner: owner)
        scheduleLifetime(activity.lifetime, token: token)
        return Handle(host: self, owner: owner, token: token)
    }

    public func showHUD(_ hud: IslandHUD, owner: FeatureID) {
        let token = model.showHUD(hud, owner: owner)
        hudTask?.cancel()
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(hud.duration))
            guard !Task.isCancelled else { return }
            self?.model.clearHUD(token: token)
        }
    }

    public func dismissAll(owner: FeatureID) {
        model.removeAll(owner: owner)
    }

    public func setScrollHandler(_ handler: (@MainActor (IslandScrollEvent) -> Void)?, owner: FeatureID) {
        scrollHandlers.removeAll { $0.owner == owner }
        if let handler {
            scrollHandlers.append((owner, handler))
        }
    }

    // MARK: Handles

    @MainActor
    final class Handle: IslandHandle {
        private weak var host: IslandHost?
        private let owner: FeatureID
        private let token: UUID

        init(host: IslandHost, owner: FeatureID, token: UUID) {
            self.host = host
            self.owner = owner
            self.token = token
        }

        var isActive: Bool {
            host?.model.contains(token: token) ?? false
        }

        func update(_ activity: IslandActivity) {
            host?.model.update(activity, owner: owner, token: token)
        }

        func dismiss() {
            host?.model.remove(token: token)
        }
    }

    // MARK: Observation

    private func observe() {
        let featureEvents = events.stream { event in
            if case .featureStateChanged = event { return true }
            return event == .displaysChanged
        }
        tasks.append(Task { [weak self] in
            for await event in featureEvents {
                guard let self else { return }
                switch event {
                case .featureStateChanged(let id):
                    if !self.dependencies.features.state(of: id).isRunning {
                        self.model.removeAll(owner: id)
                        self.scrollHandlers.removeAll { $0.owner == id }
                    }
                case .displaysChanged:
                    self.rebuildPanels()
                default:
                    break
                }
            }
        })
        let displays = settings.changes(of: IslandSettings.displays)
        tasks.append(Task { [weak self] in
            for await _ in displays {
                self?.rebuildPanels()
            }
        })
        let fullScreen = settings.changes(of: IslandSettings.showInFullScreen)
        tasks.append(Task { [weak self] in
            for await show in fullScreen {
                self?.panels.values.forEach { $0.setShowsInFullScreen(show) }
            }
        })
    }

    private func scheduleLifetime(_ lifetime: IslandLifetime, token: UUID) {
        guard case .transient(let seconds) = lifetime else { return }
        transientTasks[token]?.cancel()
        transientTasks[token] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.model.remove(token: token)
            self.transientTasks[token] = nil
        }
    }

    // MARK: Panels

    private func rebuildPanels() {
        let screens = targetScreens()
        let wanted = Set(screens.map(\.islandDisplayID))
        for (id, panel) in panels where !wanted.contains(id) {
            panel.close()
            panels[id] = nil
        }
        if let expanded = model.expandedDisplay, !wanted.contains(expanded) {
            model.collapse()
        }
        for screen in screens {
            let geometry = Self.geometry(for: screen)
            let frame = Self.panelFrame(for: screen, geometry: geometry)
            if let panel = panels[geometry.displayID] {
                panel.update(geometry: geometry, frame: frame, rootView: rootView(for: geometry))
            } else {
                let panel = IslandPanel(
                    frame: frame,
                    rootView: rootView(for: geometry),
                    showsInFullScreen: settings[IslandSettings.showInFullScreen]
                )
                panel.onScroll = { [weak self] event in self?.handleScroll(event, display: geometry.displayID) }
                panels[geometry.displayID] = panel
                panel.show()
            }
        }
    }

    private func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        switch settings[IslandSettings.displays] {
        case .all:
            return screens
        case .main:
            return [NSScreen.screens.first].compactMap { $0 }
        case .builtIn:
            let builtIn = screens.first { CGDisplayIsBuiltin($0.islandDisplayID) != 0 }
            return [builtIn ?? screens.first].compactMap { $0 }
        }
    }

    static func geometry(for screen: NSScreen) -> IslandGeometry {
        let notchHeight = screen.safeAreaInsets.top
        if notchHeight > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchWidth = screen.frame.width - left.width - right.width
            return IslandGeometry(displayID: screen.islandDisplayID, hasNotch: true, centerWidth: max(notchWidth, 0), barHeight: notchHeight)
        }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return IslandGeometry(
            displayID: screen.islandDisplayID,
            hasNotch: false,
            centerWidth: 16,
            barHeight: menuBarHeight > 0 ? menuBarHeight : 24
        )
    }

    /// A fixed panel big enough for the expanded Island plus its shadow, centred on the
    /// notch. Its transparent parts let clicks through.
    static func panelFrame(for screen: NSScreen, geometry: IslandGeometry) -> CGRect {
        let width = max(geometry.centerWidth + 2 * 150, IslandRootView.expandedMinWidth) + 2 * geometry.shoulder + 80
        let height = geometry.barHeight + IslandRootView.expandedContentHeight + 40
        var centerX = screen.frame.midX
        if geometry.hasNotch, let left = screen.auxiliaryTopLeftArea {
            centerX = screen.frame.minX + left.width + geometry.centerWidth / 2
        }
        return CGRect(
            x: (centerX - width / 2).rounded(),
            y: screen.frame.maxY - height,
            width: width.rounded(),
            height: height.rounded()
        )
    }

    private func rootView(for geometry: IslandGeometry) -> IslandRootView {
        IslandRootView(
            model: model,
            geometry: geometry,
            isEnabled: { [settings] in settings[IslandSettings.enabled] },
            pages: { [weak self] in self?.pages() ?? [] },
            actions: IslandViewActions(
                hoverChanged: { [weak self] hovering in self?.hoverChanged(hovering, display: geometry.displayID) },
                tapped: { [weak self] entry in self?.tapped(entry, display: geometry.displayID) },
                selectPage: { [weak self] page in self?.model.selectedPageID = page }
            )
        )
    }

    /// Activities' expanded views first (in priority order), then features' pages.
    private func pages() -> [IslandPageItem] {
        let activityPages = model.orderedEntries.compactMap(IslandPageItem.activity)
        let featurePages = dependencies.features.runningFeatures.flatMap { feature in
            feature.islandPages.map { IslandPageItem.page($0, owner: type(of: feature).manifest.id) }
        }
        return activityPages + featurePages
    }

    // MARK: Interaction

    private func hoverChanged(_ hovering: Bool, display: UInt32) {
        hoverTask?.cancel()
        if hovering {
            guard settings[IslandSettings.expandOnHover], model.expandedDisplay != display else { return }
            let delay = settings[IslandSettings.hoverDelay]
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.expand(on: display, page: nil)
            }
        } else {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self else { return }
                if self.model.expandedDisplay == display {
                    self.model.collapse()
                }
            }
        }
    }

    private func tapped(_ entry: IslandModel.Entry?, display: UInt32) {
        hoverTask?.cancel()
        if let entry, let onTap = entry.activity.onTap {
            onTap()
            return
        }
        expand(on: display, page: entry.map(IslandPageItem.activityPageID))
    }

    private func expand(on display: UInt32, page: String?) {
        let available = pages()
        guard !available.isEmpty else { return }
        var selected = page ?? model.selectedPageID
        if page == nil, let compact = model.compactEntry, compact.activity.expanded != nil {
            // Hovering opens the page of whatever the compact Island was showing.
            selected = IslandPageItem.activityPageID(compact)
        }
        if !available.contains(where: { $0.id == selected }) {
            selected = available.first?.id
        }
        model.expand(on: display, page: selected)
    }

    private func handleScroll(_ event: NSEvent, display: UInt32) {
        if model.expandedDisplay == display, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            // Horizontal swipes switch pages.
            horizontalScroll += event.scrollingDeltaX
            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 60 : 1
            guard abs(horizontalScroll) >= threshold else { return }
            let forward = horizontalScroll < 0
            horizontalScroll = 0
            let available = pages()
            guard let index = available.firstIndex(where: { $0.id == model.selectedPageID }) ?? (available.isEmpty ? nil : 0) else { return }
            let next = min(max(index + (forward ? 1 : -1), 0), available.count - 1)
            model.selectedPageID = available[next].id
            return
        }
        guard let handler = scrollHandlers.last?.handler else { return }
        handler(IslandScrollEvent(
            deltaY: Double(event.scrollingDeltaY) * (event.isDirectionInvertedFromDevice ? -1 : 1),
            deltaX: Double(event.scrollingDeltaX),
            isPrecise: event.hasPreciseScrollingDeltas,
            isFine: event.modifierFlags.contains(.option)
        ))
    }
}

/// One Island panel (one per display).
@MainActor
final class IslandPanel {
    private let panel: KKPanel
    private let hostingView: IslandHostingView
    var onScroll: (@MainActor (NSEvent) -> Void)? {
        didSet { hostingView.onScroll = onScroll }
    }

    init(frame: CGRect, rootView: IslandRootView, showsInFullScreen: Bool) {
        panel = KKPanel(contentRect: frame, acceptsKeyFocus: false)
        hostingView = IslandHostingView(rootView: rootView)
        panel.contentView = hostingView
        // Above the menu bar so the Island can cover the notch area.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.acceptsMouseMovedEvents = true
        panel.hasShadow = false
        panel.animationBehavior = .none
        setShowsInFullScreen(showsInFullScreen)
        panel.setFrame(frame, display: false)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func update(geometry: IslandGeometry, frame: CGRect, rootView: IslandRootView) {
        hostingView.rootView = rootView
        panel.setFrame(frame, display: true)
    }

    func setShowsInFullScreen(_ show: Bool) {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if show {
            behavior.insert(.fullScreenAuxiliary)
        }
        panel.collectionBehavior = behavior
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

/// Hosts the Island's SwiftUI view, takes first clicks (the panel never becomes key)
/// and forwards scroll-wheel events to the host.
final class IslandHostingView: NSHostingView<IslandRootView> {
    var onScroll: (@MainActor (NSEvent) -> Void)?

    required init(rootView: IslandRootView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        if let onScroll {
            onScroll(event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

extension NSScreen {
    var islandDisplayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
