import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI
import UniformTypeIdentifiers

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
    private var hovering: Set<UInt32> = []
    private var autoCollapseTask: Task<Void, Never>?
    /// Where each panel's notch is, for spotting drags heading toward it.
    private var notchAnchors: [UInt32: (screen: CGRect, centerX: CGFloat)] = [:]
    private var dragMonitors: [Any] = []
    private var dragStartCount = 0
    private var dropHideTask: Task<Void, Never>?
    private var isOverDropArea = false

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

    public func expand(page: String?, activityID: String?, owner: FeatureID) {
        let pageID: String?
        if let activityID {
            pageID = IslandPageItem.activityPageID(owner: owner, activityID: activityID)
        } else if let page {
            pageID = IslandPageItem.pageID(owner: owner, pageID: page)
        } else {
            pageID = nil
        }
        guard let display = displayForExpansion() else { return }
        expand(on: display, page: pageID)
        // Opened without the pointer: close again unless the user moves onto it.
        autoCollapseTask?.cancel()
        autoCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, !self.hovering.contains(display) else { return }
            if self.model.expandedDisplay == display {
                self.model.collapse()
            }
        }
    }

    /// The panel on the screen with the pointer, or the first one.
    private func displayForExpansion() -> UInt32? {
        let mouse = NSEvent.mouseLocation
        if let match = notchAnchors.first(where: { $0.value.screen.contains(mouse) }) {
            return match.key
        }
        return panels.keys.sorted().first
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

        var isExpanded: Bool {
            host?.model.isExpanded(token: token) ?? false
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
                    self.updateDragMonitor()
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
        let enabled = settings.changes(of: IslandSettings.enabled)
        tasks.append(Task { [weak self] in
            for await _ in enabled {
                self?.updateDragMonitor()
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
        notchAnchors = [:]
        for screen in screens {
            let geometry = Self.geometry(for: screen)
            let frame = Self.panelFrame(for: screen, geometry: geometry)
            notchAnchors[geometry.displayID] = (screen.frame, frame.midX)
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
            dropZones: { [weak self] in self?.dropZones() ?? [] },
            actions: IslandViewActions(
                hoverChanged: { [weak self] hovering in self?.hoverChanged(hovering, display: geometry.displayID) },
                tapped: { [weak self] entry in self?.tapped(entry, display: geometry.displayID) },
                selectPage: { [weak self] page in self?.model.selectedPageID = page },
                dropEntered: { [weak self] in self?.dropEntered(display: geometry.displayID) },
                dropExited: { [weak self] in self?.dropExited(display: geometry.displayID) },
                dropHovered: { [weak self] zone in self?.model.hoveredDropZone = zone },
                drop: { [weak self] zone, providers in self?.drop(providers, on: zone) }
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
        if hovering {
            self.hovering.insert(display)
        } else {
            self.hovering.remove(display)
        }
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

    // MARK: Drop area

    func dropZones() -> [IslandDropZoneItem] {
        IslandDropZoneItem.collect(from: dependencies.features.runningFeatures)
    }

    /// Watches mouse drags (no permission needed) only while some feature has a drop
    /// zone, and opens the drop area when a drag with content nears a notch.
    private func updateDragMonitor() {
        let wanted = !dropZones().isEmpty && settings[IslandSettings.enabled]
        if wanted, dragMonitors.isEmpty {
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
                let type = event.type
                MainActor.assumeIsolated { self?.handleDrag(type) }
            }) {
                dragMonitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                let type = event.type
                MainActor.assumeIsolated { self?.handleDrag(type) }
                return event
            }) {
                dragMonitors.append(local)
            }
        } else if !wanted, !dragMonitors.isEmpty {
            dragMonitors.forEach(NSEvent.removeMonitor)
            dragMonitors = []
            model.hideDropArea()
        }
    }

    private func handleDrag(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            dragStartCount = NSPasteboard(name: .drag).changeCount
        case .leftMouseDragged:
            // A real drag-and-drop puts something on the drag pasteboard.
            guard NSPasteboard(name: .drag).changeCount != dragStartCount else { return }
            let mouse = NSEvent.mouseLocation
            let near = notchAnchors.first { _, anchor in
                anchor.screen.contains(mouse)
                    && mouse.y > anchor.screen.maxY - 150
                    && abs(mouse.x - anchor.centerX) < 320
            }
            if let near {
                dropHideTask?.cancel()
                if model.dropDisplay != near.key {
                    model.showDropArea(on: near.key)
                }
            } else if model.dropDisplay != nil, !isOverDropArea {
                scheduleDropAreaHide(after: .milliseconds(250))
            }
        case .leftMouseUp:
            if model.dropDisplay != nil {
                scheduleDropAreaHide(after: .milliseconds(400))
            }
        default:
            break
        }
    }

    private func dropEntered(display: UInt32) {
        isOverDropArea = true
        dropHideTask?.cancel()
        if model.dropDisplay != display {
            model.showDropArea(on: display)
        }
    }

    private func dropExited(display: UInt32) {
        isOverDropArea = false
        model.hoveredDropZone = nil
        scheduleDropAreaHide(after: .milliseconds(300))
    }

    private func scheduleDropAreaHide(after delay: Duration) {
        dropHideTask?.cancel()
        dropHideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.isOverDropArea else { return }
            self.model.hideDropArea()
        }
    }

    private func drop(_ providers: [NSItemProvider], on zoneID: String?) {
        isOverDropArea = false
        let zones = dropZones()
        let target = zones.first { $0.id == zoneID } ?? zones.first
        model.hideDropArea()
        guard let target else { return }
        Task { [weak self] in
            let items = await Self.load(providers)
            let accepted = target.zone.accepted(items)
            guard !accepted.isEmpty else {
                self?.showHUD(
                    IslandHUD(id: "island.drop", symbol: "nosign", title: String(localized: "\(target.zone.title) can't take that"), tint: .warning),
                    owner: IslandSettings.owner
                )
                return
            }
            await target.zone.perform(accepted)
        }
    }

    /// The types the drop area takes, most specific first.
    static let dropTypes: [UTType] = [.fileURL, .url, .image, .plainText]

    static func load(_ providers: [NSItemProvider]) async -> [DroppedItem] {
        var items: [DroppedItem] = []
        for provider in providers {
            if let item = await load(provider) {
                items.append(item)
            }
        }
        return items
    }

    private static func load(_ provider: NSItemProvider) async -> DroppedItem? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let data = await data(from: provider, type: UTType.fileURL.identifier),
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            // Finder sends file reference URLs (file:///.file/id=…).
            return .file((url as NSURL).filePathURL ?? url)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let data = await data(from: provider, type: UTType.url.identifier),
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url.isFileURL ? .file(url) : .url(url)
        }
        for type in [UTType.png, .tiff, .jpeg, .heic, .image] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let data = await data(from: provider, type: type.identifier) {
                return .image(data, type: type == .image ? UTType.tiff.identifier : type.identifier)
            }
        }
        for type in [UTType.utf8PlainText, .plainText] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let data = await data(from: provider, type: type.identifier),
               let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return .text(text)
            }
        }
        return nil
    }

    private static func data(from provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
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
