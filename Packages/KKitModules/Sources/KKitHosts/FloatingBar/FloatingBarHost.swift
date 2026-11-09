import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import Observation
import SwiftUI

/// The Floating Bar: a launcher panel that opens on a hotkey (⌥Space), searches every
/// running feature's providers, and runs results. It's pre-warmed at launch and only
/// hidden between uses. Features reach it through `context.floatingBar`.
@MainActor
public final class FloatingBarHost: FloatingBarService {
    public let model: FloatingBarModel
    /// Opens a Settings page; the app connects it to the Settings host.
    public var openSettings: (@MainActor (SettingsPage) -> Void)?

    private let dependencies: HostDependencies
    private let storage: any StorageService
    private let island: (any IslandService)?
    private let settings: FeatureSettings
    private let log = KKitLog.logger("floatingBar")
    private var panel: KKPanel?
    private var hostingView: NSHostingView<FloatingBarRootView>?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var hiddenAt: Date?
    private var anchorTop: CGFloat = 0
    private var anchorMidX: CGFloat = 0
    private var saveTask: Task<Void, Never>?

    static let rememberSeconds: TimeInterval = 30

    /// The frontmost app's menus under `m ` (M4), and menu bar icons (M5).
    private let menuItemsProvider: MenuItemsSearchProvider?

    public init(
        dependencies: HostDependencies,
        storage: any StorageService,
        island: (any IslandService)?,
        accessibility: (any AccessibilityService)? = nil,
        menuBarIcons: @escaping @MainActor () -> (any MenuBarIconsServicing)? = { nil }
    ) {
        self.dependencies = dependencies
        self.storage = storage
        self.island = island
        let permissions = dependencies.permissions
        self.menuItemsProvider = accessibility.map { service in
            MenuItemsSearchProvider(accessibility: service, menuBarIcons: menuBarIcons) {
                Task { await permissions.request(.accessibility) }
            }
        }
        self.settings = FeatureSettings(featureID: FloatingBarSettings.owner, store: dependencies.settings)
        let hotkeys = dependencies.hotkeys
        let commandProvider = CommandSearchProvider(
            commands: dependencies.commands,
            shortcutText: { id in hotkeys.shortcut(for: id).map { hotkeys.displayString(for: $0) } },
            ownerName: { [dependencies] id in dependencies.ownerName(id) }
        )
        self.model = FloatingBarModel(commands: dependencies.commands, commandProvider: commandProvider)
        wireModel()
        loadHistory()
        registerCommands()
        makePanel()
    }

    /// The Floating Bar's own settings, for its Settings page.
    public var floatingBarSettings: FeatureSettings { settings }

    // MARK: FloatingBarService

    public var isVisible: Bool { panel?.isVisible ?? false }

    public func show(query: String?) {
        prepareForShow()
        if let query {
            model.query = query
        } else {
            model.refresh()
        }
        present()
    }

    public func showMode(_ modeID: String, owner: FeatureID, text: String?) {
        prepareForShow()
        model.openMode(key: "\(owner.rawValue).\(modeID)", text: text ?? "")
        present()
    }

    public func hide() {
        guard let panel, panel.isVisible else { return }
        model.closeActions()
        panel.orderOut(nil)
        hiddenAt = Date()
    }

    public func toggle() {
        if isVisible {
            hide()
        } else {
            show(query: nil)
        }
    }

    // MARK: Settings page

    /// A provider or mode, for Settings › Floating Bar.
    public struct SourceInfo: Identifiable {
        public let id: String
        public let name: String
        public let symbol: String
        public let prefix: String?
        public let owner: String
        public let inRootSearch: Bool
        public let isMode: Bool
    }

    public func sourceInfos() -> [SourceInfo] {
        let sources = currentSources()
        let providers = sources.providers.map { entry in
            SourceInfo(
                id: entry.key,
                name: entry.provider.displayName,
                symbol: entry.provider.symbol,
                prefix: entry.provider.prefix,
                owner: dependencies.ownerName(entry.owner),
                inRootSearch: entry.provider.includeInRootSearch,
                isMode: false
            )
        }
        let modes = sources.modes.map { entry in
            SourceInfo(
                id: entry.key,
                name: entry.mode.title,
                symbol: entry.mode.symbol,
                prefix: entry.mode.prefix,
                owner: dependencies.ownerName(entry.owner),
                inRootSearch: false,
                isMode: true
            )
        }
        return providers + modes
    }

    public func setProvider(_ key: String, enabled: Bool) {
        var disabled = Set(settings[FloatingBarSettings.disabledProviders])
        if enabled {
            disabled.remove(key)
        } else {
            disabled.insert(key)
        }
        settings[FloatingBarSettings.disabledProviders] = disabled.sorted()
    }

    public func isProviderEnabled(_ key: String) -> Bool {
        !settings[FloatingBarSettings.disabledProviders].contains(key)
    }

    // MARK: Wiring

    private func wireModel() {
        model.sources = { [weak self] in self?.currentSources() ?? FloatingBarSources() }
        model.isProviderEnabled = { [weak self] key in self?.isProviderEnabled(key) ?? true }
        model.showRecents = { [settings] in settings[FloatingBarSettings.showRecents] }
        model.actionsFor = { [weak self] result in self?.actions(for: result) ?? [] }
        model.onRun = { [weak self] result, keepOpen in self?.run(result, keepOpen: keepOpen) }
        model.onAction = { [weak self] action, result in self?.runAction(action, on: result) }
        model.onHistoryChange = { [weak self] history in self?.scheduleSave(history) }
    }

    /// The commands provider first, then each running feature's providers and modes.
    private func currentSources() -> FloatingBarSources {
        var providers = [ProviderEntry(owner: FloatingBarSettings.owner, provider: model.commandProvider)]
        if let menuItemsProvider {
            providers.append(ProviderEntry(owner: FloatingBarSettings.owner, provider: menuItemsProvider))
        }
        var modes: [ModeEntry] = []
        for feature in dependencies.features.runningFeatures {
            let owner = type(of: feature).manifest.id
            for provider in feature.searchProviders {
                providers.append(ProviderEntry(owner: owner, provider: provider))
            }
            for mode in feature.floatingBarModes {
                modes.append(ModeEntry(owner: owner, mode: mode))
            }
        }
        return FloatingBarSources(providers: providers, modes: modes)
    }

    private func registerCommands() {
        dependencies.commands.register([
            Command(
                id: FloatingBarCommandID.toggle,
                title: String(localized: "Open Floating Bar"),
                subtitle: String(localized: "Search and run anything"),
                symbol: "magnifyingglass",
                keywords: ["launcher", "search", "spotlight"],
                defaultShortcut: Shortcut(keyCode: Shortcut.Key.space, modifiers: [.option])
            ) { [weak self] _ in
                self?.toggle()
            },
            Command(
                id: FloatingBarCommandID.searchCommands,
                title: String(localized: "Search KKit Commands"),
                symbol: "command",
                keywords: ["commands", "actions"]
            ) { [weak self] _ in
                self?.show(query: "> ")
            },
        ], owner: FloatingBarSettings.owner)
    }

    // MARK: History

    private func loadHistory() {
        do {
            if let saved = try storage.readJSON(FloatingBarHistory.self, named: FloatingBarHistory.fileName, for: FloatingBarSettings.owner) {
                model.history = saved
            }
        } catch {
            log.error("Couldn't read Floating Bar history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleSave(_ history: FloatingBarHistory) {
        saveTask?.cancel()
        let storage = self.storage
        let log = self.log
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                do {
                    try storage.writeJSON(history, named: FloatingBarHistory.fileName, for: FloatingBarSettings.owner)
                } catch {
                    log.error("Couldn't save Floating Bar history: \(error.localizedDescription, privacy: .public)")
                }
            }.value
        }
    }

    /// Forgets Recent and frecency (Settings).
    public func clearRecents() {
        model.history.clearRecents()
    }

    public func removeFavourite(_ id: String) {
        model.history.favourites.removeAll { $0.id == id }
    }

    // MARK: Panel

    private func makePanel() {
        let panel = KKPanel(contentRect: NSRect(x: 0, y: 0, width: FloatingBarLayout.width, height: 200), acceptsKeyFocus: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let hostingView = NSHostingView(rootView: FloatingBarRootView(model: model, actions: viewActions()))
        panel.contentView = hostingView
        self.panel = panel
        self.hostingView = hostingView

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
        trackSize()
    }

    private func viewActions() -> FloatingBarViewActions {
        FloatingBarViewActions(
            run: { [weak self] row, keepOpen in self?.model.activate(row.result, keepOpen: keepOpen) },
            runAction: { [weak self] action in
                guard let self else { return }
                self.model.selectAction(action.id)
                self.model.activateSelection(keepOpen: false)
            },
            modeContext: { [weak self] mode in
                FloatingBarModeContext(
                    initialText: mode.text,
                    dismiss: { [weak self] in self?.hide() },
                    exit: { [weak self] in self?.model.exitMode() },
                    openSettings: { [weak self] in
                        self?.hide()
                        self?.openSettings?(.feature(mode.owner))
                    }
                )
            },
            prefixes: { [weak self] in self?.prefixHints() ?? [] }
        )
    }

    private func prefixHints() -> [PrefixHint] {
        let sources = currentSources()
        var hints: [PrefixHint] = []
        for entry in sources.providers where isProviderEnabled(entry.key) {
            if let prefix = entry.provider.prefix {
                hints.append(PrefixHint(id: entry.key, prefix: prefix, name: entry.provider.displayName))
            }
        }
        for entry in sources.modes {
            if let prefix = entry.mode.prefix {
                hints.append(PrefixHint(id: entry.key, prefix: prefix, name: entry.mode.title))
            }
        }
        return hints
    }

    private func prepareForShow() {
        guard let hiddenAt else { return }
        let elapsed = Date().timeIntervalSince(hiddenAt)
        if !settings[FloatingBarSettings.rememberQuery] || elapsed > Self.rememberSeconds {
            model.reset()
        }
    }

    private func present() {
        guard let panel else { return }
        let screen = Self.screenWithCursor()
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        anchorMidX = visible.midX
        switch settings[FloatingBarSettings.placement] {
        case .center:
            anchorTop = visible.maxY - (visible.height * 0.2).rounded()
        case .top:
            anchorTop = visible.maxY - 12
        }
        applySize(FloatingBarLayout.size(for: model), panel: panel)
        panel.makeKeyAndOrderFront(nil)
        model.requestFocus()
    }

    /// Resizes the panel whenever what's shown changes, keeping its top edge in place.
    private func trackSize() {
        let size = withObservationTracking {
            FloatingBarLayout.size(for: model)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.trackSize() }
        }
        guard let panel, panel.isVisible else { return }
        applySize(size, panel: panel)
    }

    private func applySize(_ size: CGSize, panel: KKPanel) {
        let frame = NSRect(
            x: (anchorMidX - size.width / 2).rounded(),
            y: (anchorTop - size.height).rounded(),
            width: size.width,
            height: size.height
        )
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private static func screenWithCursor() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }

    // MARK: Keys

    /// Navigation keys, handled before the search field sees them. Modes handle their
    /// own keys.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let panel, panel.isKeyWindow, event.window === panel, model.activeMode == nil else { return false }
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() {
            return false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased()
        switch event.keyCode {
        case 125:
            model.moveSelection(1)
        case 126:
            model.moveSelection(-1)
        case 36, 76:
            model.activateSelection(keepOpen: flags.contains(.command))
        case 53:
            escape()
        case 48:
            guard !model.actionsShown else { return true }
            model.showsPreview.toggle()
        case 40 where flags.contains(.command):
            model.toggleActions()
        case 51 where model.query.isEmpty && model.pending != nil:
            model.cancelArgument()
        default:
            if flags == .control, characters == "n" {
                model.moveSelection(1)
            } else if flags == .control, characters == "p" {
                model.moveSelection(-1)
            } else {
                return false
            }
        }
        return true
    }

    private func escape() {
        if model.actionsShown {
            model.closeActions()
        } else if model.pending != nil {
            model.cancelArgument()
        } else {
            hide()
        }
    }

    // MARK: Running

    private func run(_ result: SearchResult, keepOpen: Bool) {
        if !keepOpen {
            hide()
        }
        Task { [weak self] in
            do {
                try await self?.perform(result)
            } catch {
                self?.report(error, keepOpen: keepOpen)
            }
        }
    }

    private func perform(_ result: SearchResult) async throws {
        if let custom = result.perform {
            try await custom()
            return
        }
        switch result.kind {
        case .command(let id, let argument):
            try await dependencies.commands.perform(id, CommandInvocation(argument: argument, source: .floatingBar))
        case .application(let url):
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        case .file(let url), .url(let url):
            guard NSWorkspace.shared.open(url) else {
                throw FloatingBarError.couldNotOpen(url)
            }
        case .text(let text):
            copy(text)
            island?.showHUD(IslandHUD(id: "floatingBar.copied", symbol: "doc.on.doc", detail: String(localized: "Copied"), duration: 1.2), owner: FloatingBarSettings.owner)
        case .custom:
            break
        }
    }

    private func runAction(_ action: ResultAction, on result: SearchResult) {
        if action.dismissesBar {
            hide()
        }
        Task { [weak self] in
            do {
                try await action.perform(result)
            } catch {
                self?.report(error, keepOpen: !action.dismissesBar)
            }
        }
    }

    private func report(_ error: any Error, keepOpen: Bool) {
        log.error("Floating Bar action failed: \(error.localizedDescription, privacy: .public)")
        if keepOpen, isVisible {
            model.message = error.localizedDescription
        } else {
            island?.showHUD(
                IslandHUD(id: "floatingBar.error", symbol: "exclamationmark.triangle.fill", title: error.localizedDescription, tint: .warning, duration: 3),
                owner: FloatingBarSettings.owner
            )
        }
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: ⌘K actions

    /// The primary action, actions for the result's kind, Favourites and Recent, then
    /// every running feature's actions that apply.
    func actions(for result: SearchResult) -> [ResultAction] {
        var actions: [ResultAction] = [
            ResultAction(
                id: "floatingBar.run",
                title: result.actionTitle ?? result.kind.defaultActionTitle,
                symbol: "return",
                dismissesBar: false
            ) { [weak self] result in
                self?.model.activate(result, keepOpen: false)
            },
        ]
        if let url = result.kind.fileURL {
            actions.append(ResultAction(id: "floatingBar.reveal", title: String(localized: "Reveal in Finder"), symbol: "folder") { _ in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            })
            actions.append(ResultAction(id: "floatingBar.copyPath", title: String(localized: "Copy Path"), symbol: "doc.on.clipboard") { [weak self] _ in
                self?.copy(url.path)
            })
            if case .file = result.kind {
                for app in NSWorkspace.shared.urlsForApplications(toOpen: url).prefix(4) {
                    let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
                    actions.append(ResultAction(id: "floatingBar.openWith.\(app.path)", title: String(localized: "Open with \(name)"), symbol: "arrow.up.forward.app") { _ in
                        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                    })
                }
            }
        }
        if case .url(let url) = result.kind {
            actions.append(ResultAction(id: "floatingBar.copyLink", title: String(localized: "Copy Link"), symbol: "link") { [weak self] _ in
                self?.copy(url.absoluteString)
            })
        }
        if case .command(let id, let argument) = result.kind {
            actions.append(ResultAction(id: "floatingBar.assignShortcut", title: String(localized: "Assign Shortcut…"), symbol: "keyboard") { [weak self] _ in
                let owner = id.featureID
                let isFeature = self?.dependencies.features.manifest(for: owner) != nil
                self?.openSettings?(isFeature ? .feature(owner) : .shortcuts)
            })
            let link = KKitLink.run(id, value: argument.map { FloatingBarPreview.rawValue($0) }).url.absoluteString
            actions.append(ResultAction(id: "floatingBar.copyCommandLink", title: String(localized: "Copy kkit:// Link"), symbol: "link") { [weak self] _ in
                self?.copy(link)
            })
        }
        if result.kind.isStorable {
            let isFavourite = model.history.isFavourite(result.id)
            actions.append(ResultAction(
                id: "floatingBar.favourite",
                title: isFavourite ? String(localized: "Remove from Favourites") : String(localized: "Add to Favourites"),
                symbol: isFavourite ? "star.slash" : "star",
                dismissesBar: false
            ) { [weak self] result in
                self?.model.toggleFavourite(result)
            })
            if model.history.recents.contains(where: { $0.id == result.id }) {
                actions.append(ResultAction(
                    id: "floatingBar.removeRecent",
                    title: String(localized: "Remove from Recent"),
                    symbol: "clock.badge.xmark",
                    dismissesBar: false
                ) { [weak self] result in
                    self?.model.removeRecent(result.id)
                })
            }
        }
        for feature in dependencies.features.runningFeatures {
            actions.append(contentsOf: feature.resultActions.filter { $0.appliesTo(result) })
        }
        return actions
    }
}

enum FloatingBarError: LocalizedError {
    case couldNotOpen(URL)

    var errorDescription: String? {
        switch self {
        case .couldNotOpen(let url):
            String(localized: "Couldn't open \(url.isFileURL ? url.lastPathComponent : url.absoluteString).")
        }
    }
}
