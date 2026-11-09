import AppKit
import CoreGraphics
import KKitCore
import KKitServicesAPI
import Observation
import SwiftUI

/// Shows and hides the hidden icons, keeps the drop-down bar, opens icons and moves
/// them between sections. The menu bar work itself is `MenuBarItemsService`'s.
/// DESIGN.md §3.13.
@MainActor
@Observable
final class MenuBarManagerController: MenuBarIconsServicing {
    /// Icons from the last look, left to right.
    private(set) var icons: [MenuBarIcon] = []
    /// Pictures of icons, by icon id, taken while they were on screen.
    private(set) var images: [String: CapturedImage] = [:]
    /// Mirrors the service, so views and commands update.
    private(set) var revealed: Set<MenuBarIconSection> = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    /// The pointer is on the drop-down bar (it doesn't hide under the pointer).
    var isPointerOnDropDown = false

    let service: any MenuBarItemsService
    private let input: FeatureInput
    private let overlays: any OverlayService
    private let screenCapture: any ScreenCaptureService
    private let permissions: any PermissionsService
    private let settings: FeatureSettings
    private let revealDelay: Duration
    private let pointerLocation: @MainActor () -> CGPoint

    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var autoHideTask: Task<Void, Never>?
    @ObservationIgnored private var commandToken: InputHandlerToken?
    @ObservationIgnored private var commandRevealActive = false
    @ObservationIgnored private var revealedBeforeCommand: Set<MenuBarIconSection> = []
    @ObservationIgnored private var panel: (any OverlayHandle)?
    @ObservationIgnored private var isRunning = false

    /// `revealDelay` is how long the menu bar takes to lay itself out after a section
    /// shows; tests pass zero.
    init(
        service: any MenuBarItemsService,
        input: FeatureInput,
        overlays: any OverlayService,
        screenCapture: any ScreenCaptureService,
        permissions: any PermissionsService,
        settings: FeatureSettings,
        revealDelay: Duration = .milliseconds(250),
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    ) {
        self.service = service
        self.input = input
        self.overlays = overlays
        self.screenCapture = screenCapture
        self.permissions = permissions
        self.settings = settings
        self.revealDelay = revealDelay
        self.pointerLocation = pointerLocation
    }

    // MARK: Lifecycle

    func start() {
        isRunning = true
        let alwaysHidden = settings.changes(of: MenuBarManagerSettings.alwaysHiddenSection)
        tasks.append(Task { [weak self] in
            for await enabled in alwaysHidden {
                self?.install(alwaysHiddenSection: enabled)
            }
        })
        let command = settings.changes(of: MenuBarManagerSettings.showAllWithCommand)
        tasks.append(Task { [weak self] in
            for await enabled in command {
                self?.setCommandHandler(enabled)
            }
        })
    }

    func stop() {
        isRunning = false
        tasks.forEach { $0.cancel() }
        tasks = []
        autoHideTask?.cancel()
        autoHideTask = nil
        setCommandHandler(false)
        panel?.close()
        panel = nil
        service.uninstall()
        revealed = []
    }

    private func install(alwaysHiddenSection: Bool) {
        guard isRunning else { return }
        service.install(alwaysHiddenSection: alwaysHiddenSection) { [weak self] event in
            self?.chevron(event)
        }
        revealed = service.revealed
    }

    // MARK: Showing and hiding

    var isShowingHidden: Bool { revealed.contains(.hidden) }
    var isDropDownVisible: Bool { panel?.isVisible == true }

    func chevron(_ event: MenuBarChevronEvent) {
        switch event {
        case .hover:
            guard settings[MenuBarManagerSettings.revealOn] == .hover, !isShowingHidden, !isDropDownVisible else { return }
            show(all: false)
        case .click(let alternate):
            if isShowingHidden || isDropDownVisible {
                hideAll()
            } else {
                show(all: alternate)
            }
        }
    }

    /// Shows or hides the hidden icons (the chevron, `menuBarManager.toggle`).
    func toggle() {
        if isShowingHidden || isDropDownVisible {
            hideAll()
        } else {
            show(all: false)
        }
    }

    /// Hidden icons (and with `all`, always-hidden ones) in the menu bar or the
    /// drop-down bar, whichever the settings say.
    func show(all: Bool) {
        if usesDropDownBar {
            Task { await showDropDown() }
        } else {
            setRevealed(all ? [.hidden, .alwaysHidden] : [.hidden])
            scheduleAutoHide()
        }
    }

    /// Every section in the menu bar, for ⌘-dragging.
    func showAll() {
        hideDropDown()
        setRevealed([.hidden, .alwaysHidden])
        scheduleAutoHide()
    }

    func hideAll() {
        autoHideTask?.cancel()
        autoHideTask = nil
        hideDropDown()
        setRevealed([])
    }

    private func setRevealed(_ sections: Set<MenuBarIconSection>) {
        let wasHidden = revealed.isEmpty
        service.reveal(sections)
        revealed = service.revealed
        if wasHidden, !revealed.isEmpty {
            // Take pictures of the icons now they're on screen.
            let delay = revealDelay
            Task { [weak self] in
                try? await Task.sleep(for: delay + .milliseconds(150))
                await self?.refreshIcons()
            }
        }
    }

    /// Whether hidden icons go in the drop-down bar.
    var usesDropDownBar: Bool {
        switch settings[MenuBarManagerSettings.openStyle] {
        case .dropDownBar: true
        case .inPlace: false
        case .automatic: (chevronScreen?.notchHeight ?? 0) > 0
        }
    }

    private var chevronScreen: ScreenInfo? {
        guard let frame = service.chevronFrame else { return overlays.screens.first(where: \.isMain) }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        return overlays.screens.first { $0.frame.contains(point) } ?? overlays.screens.first(where: \.isMain)
    }

    // MARK: Auto-hide

    func scheduleAutoHide() {
        autoHideTask?.cancel()
        let delay = settings[MenuBarManagerSettings.autoHideDelay]
        guard delay > 0 else {
            autoHideTask = nil
            return
        }
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            while !Task.isCancelled {
                guard let self else { return }
                if self.shouldPostponeHiding {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                self.hideAll()
                return
            }
        }
    }

    /// Not while a menu is open, the pointer is on the menu bar or the drop-down bar,
    /// or ⌘ is showing everything.
    var shouldPostponeHiding: Bool {
        commandRevealActive || isPointerOnDropDown || isPointerOnMenuBar || service.isMenuOpen
    }

    var isPointerOnMenuBar: Bool {
        let point = pointerLocation()
        return overlays.screens.contains { screen in
            let height = Self.menuBarHeight(of: screen)
            return point.x >= screen.frame.minX && point.x <= screen.frame.maxX
                && point.y <= screen.frame.maxY && point.y >= screen.frame.maxY - height
        }
    }

    static func menuBarHeight(of screen: ScreenInfo) -> CGFloat {
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        return max(reserved, screen.notchHeight, 24)
    }

    // MARK: ⌘ over the menu bar

    private func setCommandHandler(_ enabled: Bool) {
        if enabled, commandToken == nil, isRunning {
            commandToken = input.add(priority: .low, interests: [.flagsChanged]) { [weak self] event in
                self?.flagsChanged(event.modifiers)
                return .pass
            }
        } else if !enabled, let token = commandToken {
            input.remove(token)
            commandToken = nil
            if commandRevealActive {
                commandRevealActive = false
                restoreAfterCommand()
            }
        }
    }

    /// Runs inside the tap callback: decide now, do the menu bar work in a task.
    func flagsChanged(_ modifiers: Shortcut.Modifiers) {
        if modifiers == [.command], !commandRevealActive, isPointerOnMenuBar {
            commandRevealActive = true
            revealedBeforeCommand = revealed
            Task { [weak self] in
                guard let self, self.commandRevealActive else { return }
                self.hideDropDown()
                self.setRevealed([.hidden, .alwaysHidden])
            }
        } else if !modifiers.contains(.command), commandRevealActive {
            commandRevealActive = false
            Task { [weak self] in
                // Let a ⌘-drag finish dropping first.
                try? await Task.sleep(for: .milliseconds(300))
                self?.restoreAfterCommand()
            }
        }
    }

    private func restoreAfterCommand() {
        guard !commandRevealActive else { return }
        if revealedBeforeCommand.isEmpty {
            hideAll()
        } else {
            setRevealed(revealedBeforeCommand)
            scheduleAutoHide()
        }
    }

    // MARK: Icons

    /// Reads the icons again, and takes pictures of the ones on screen that have none.
    func refreshIcons() async {
        guard service.isTrusted else {
            icons = []
            return
        }
        isLoading = true
        icons = await service.icons()
        isLoading = false
        await captureMissingImages()
    }

    /// The drop-down bar's icons: behind the notch, hidden, always hidden.
    var dropDownGroups: [[MenuBarIcon]] {
        let behindNotch = icons.filter { $0.section == .shown && !$0.isOnScreen }
        let hidden = icons.filter { $0.section == .hidden }
        let alwaysHidden = icons.filter { $0.section == .alwaysHidden }
        return [behindNotch, hidden, alwaysHidden].filter { !$0.isEmpty }
    }

    func icons(in section: MenuBarIconSection) -> [MenuBarIcon] {
        icons.filter { $0.section == section }
    }

    var canTakePictures: Bool {
        permissions.status(of: .screenRecording).isGranted
    }

    /// Views read this rather than `service.isTrusted`: the permissions service is
    /// observable, so a grant made while Settings is open shows up straight away.
    var hasAccessibility: Bool {
        permissions.status(of: .accessibility).isGranted
    }

    private func captureMissingImages() async {
        guard settings[MenuBarManagerSettings.showsIconImages], canTakePictures else { return }
        let wanted = icons.filter { $0.isOnScreen && $0.windowID != nil && images[$0.id] == nil }.prefix(40)
        for icon in wanted {
            guard let windowID = icon.windowID,
                  let captured = try? await screenCapture.capture(.window(windowID), showsCursor: false) else { continue }
            images[icon.id] = captured
        }
    }

    /// Opens an icon's menu. A hidden icon's section shows first (apps open their menus
    /// under the icon) and hides again on the usual timer.
    func open(_ icon: MenuBarIcon) async throws {
        hideDropDown()
        var target = icon
        if !service.isRevealed(icon.section) {
            setRevealed(icon.section == .alwaysHidden ? [.hidden, .alwaysHidden] : [.hidden])
            try? await Task.sleep(for: revealDelay)
            if let fresh = await service.icons().first(where: { $0.id == icon.id }) {
                target = fresh
            }
            scheduleAutoHide()
        }
        do {
            try await service.press(target)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func move(_ icon: MenuBarIcon, to section: MenuBarIconSection) async {
        do {
            try await service.move(icon, to: section)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refreshIcons()
    }

    func move(id: String, to section: MenuBarIconSection) async {
        guard let icon = icons.first(where: { $0.id == id }) else { return }
        await move(icon, to: section)
    }

    // MARK: MenuBarIconsServicing (the Floating Bar's `m `)

    func searchableIcons() async -> [MenuBarIcon] {
        await refreshIcons()
        return icons
    }

    // MARK: Drop-down bar

    func showDropDown() async {
        await refreshIcons()
        guard isRunning, let screen = chevronScreen else { return }
        let frame = dropDownFrame(on: screen)
        let configuration = OverlayConfiguration(
            level: .statusBar,
            screen: .display(screen.id),
            placement: .frame(frame),
            acceptsKeyFocus: true,
            hasShadow: true,
            hidesOnResignKey: true
        )
        let content = AnyView(DropDownBarView(controller: self))
        if let panel {
            panel.setConfiguration(configuration)
            panel.setContent(content)
        } else {
            panel = overlays.makePanel(configuration, content: content)
        }
        panel?.show()
        scheduleAutoHide()
    }

    func hideDropDown() {
        panel?.hide()
        isPointerOnDropDown = false
    }

    /// Under the menu bar, its right edge under the chevron.
    func dropDownFrame(on screen: ScreenInfo) -> CGRect {
        let size = DropDownBarView.size(for: dropDownGroups.map(\.count), hasMessage: dropDownGroups.isEmpty || !hasAccessibility)
        let anchorX = service.chevronFrame?.maxX ?? (screen.frame.maxX - 200)
        let maxX = min(anchorX + 8, screen.frame.maxX - 8)
        let x = max(screen.frame.minX + 8, maxX - size.width)
        let top = screen.frame.maxY - Self.menuBarHeight(of: screen) - 4
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    // MARK: Permissions

    func requestAccessibility() {
        let permissions = self.permissions
        Task { await permissions.request(.accessibility) }
    }

    func requestScreenRecording() {
        let permissions = self.permissions
        Task { await permissions.request(.screenRecording) }
    }
}
