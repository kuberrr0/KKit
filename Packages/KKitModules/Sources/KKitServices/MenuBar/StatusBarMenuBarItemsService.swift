import AppKit
import ApplicationServices
import CoreGraphics
import KKitCore
import KKitServicesAPI

/// Hides other apps' menu bar icons behind KKit's divider status items, lists them
/// through Accessibility and opens or moves them (ARCHITECTURE.md §7, DESIGN.md §3.13).
///
/// The technique is the one Hidden Bar and Ice use: a divider status item grows to
/// 10 000 pt, which pushes every icon left of it off the screen. KKit adds three
/// items, created right to left: the ‹ chevron (always visible, clicked to show), the
/// Hidden divider, and (optionally) the Always Hidden divider. macOS remembers where
/// the user ⌘-drags them through their autosave names.
@MainActor
public final class StatusBarMenuBarItemsService: MenuBarItemsService {
    static let chevronName = "kkit.menuBarManager.chevron"
    static let hiddenName = "kkit.menuBarManager.hidden"
    static let alwaysHiddenName = "kkit.menuBarManager.alwaysHidden"
    static var autosaveNames: [String] { [chevronName, hiddenName, alwaysHiddenName] }

    /// Icons are read again after this long.
    private let cacheLifetime: TimeInterval = 1
    private let engine = AXMenuBarEngine()
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let log = KKitLog.logger("menuBarItems")

    private var chevron: ChevronItem?
    private var hiddenDivider: DividerItem?
    private var alwaysHiddenDivider: DividerItem?
    private var onChevron: (@MainActor (MenuBarChevronEvent) -> Void)?
    private var cache: (date: Date, icons: [MenuBarIcon])?
    public private(set) var revealed: Set<MenuBarIconSection> = []

    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    // MARK: Dividers

    public var isInstalled: Bool { chevron != nil }
    public var hasAlwaysHiddenSection: Bool { alwaysHiddenDivider != nil }

    public func install(alwaysHiddenSection: Bool, onChevron: @escaping @MainActor (MenuBarChevronEvent) -> Void) {
        self.onChevron = onChevron
        // Newer status items go left of older ones, so create them right to left.
        if chevron == nil {
            chevron = ChevronItem(autosaveName: Self.chevronName) { [weak self] event in
                self?.onChevron?(event)
            }
        }
        if hiddenDivider == nil {
            hiddenDivider = DividerItem(autosaveName: Self.hiddenName, style: .hidden)
        }
        if alwaysHiddenSection, alwaysHiddenDivider == nil {
            alwaysHiddenDivider = DividerItem(autosaveName: Self.alwaysHiddenName, style: .alwaysHidden)
        } else if !alwaysHiddenSection, let divider = alwaysHiddenDivider {
            Self.keepingPositions { divider.remove() }
            alwaysHiddenDivider = nil
        }
        apply()
    }

    public func uninstall() {
        Self.keepingPositions {
            alwaysHiddenDivider?.remove()
            hiddenDivider?.remove()
            chevron?.remove()
        }
        alwaysHiddenDivider = nil
        hiddenDivider = nil
        chevron = nil
        onChevron = nil
        revealed = []
        cache = nil
    }

    public func resetDividers() {
        guard isInstalled, let onChevron else { return }
        let alwaysHidden = hasAlwaysHiddenSection
        uninstall()
        for name in Self.autosaveNames {
            UserDefaults.standard.removeObject(forKey: Self.positionKey(name))
        }
        install(alwaysHiddenSection: alwaysHidden, onChevron: onChevron)
    }

    public var dividersOutOfOrder: Bool {
        layout.isOutOfOrder
    }

    public func reveal(_ sections: Set<MenuBarIconSection>) {
        var sections = sections
        sections.remove(.shown)
        if sections.contains(.alwaysHidden) {
            sections.insert(.hidden)
        }
        guard sections != revealed else { return }
        revealed = sections
        cache = nil
        apply()
    }

    public var chevronFrame: CGRect? { chevron?.frame }

    private func apply() {
        hiddenDivider?.setRevealed(revealed.contains(.hidden))
        alwaysHiddenDivider?.setRevealed(revealed.contains(.alwaysHidden))
        chevron?.setOpen(revealed.contains(.hidden))
    }

    private var layout: MenuBarLayout {
        MenuBarLayout(chevron: chevron?.frame, hiddenDivider: hiddenDivider?.frame, alwaysHiddenDivider: alwaysHiddenDivider?.frame)
    }

    // MARK: Icons

    public func icons() async -> [MenuBarIcon] {
        guard isTrusted else { return [] }
        if let cache, Date().timeIntervalSince(cache.date) < cacheLifetime {
            return cache.icons
        }
        let windows = Self.statusWindows()
        var apps: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            apps[app.processIdentifier] = app
        }
        // Menu extras of system agents (background-only processes).
        for bundleID in ["com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.Spotlight", "com.apple.Siri"] {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                apps[app.processIdentifier] = app
            }
        }
        for window in windows where apps[window.pid] == nil {
            apps[window.pid] = NSRunningApplication(processIdentifier: window.pid)
        }
        // Never ask KKit itself (see AXMenuBarEngine).
        apps[ownPID] = nil
        var prefixes: [pid_t: String] = [:]
        for (pid, app) in apps {
            prefixes[pid] = app.bundleIdentifier ?? "pid\(pid)"
        }
        let raw = await engine.icons(prefixes: prefixes)
        let layout = self.layout
        let screens = Self.screens()
        let icons = raw.map { raw -> MenuBarIcon in
            let app = apps[raw.pid]
            let frame = AX.flip(raw.frame)
            return MenuBarIcon(
                id: raw.key,
                pid: raw.pid,
                bundleID: app?.bundleIdentifier,
                appName: app?.localizedName ?? raw.title,
                appURL: app?.bundleURL,
                title: raw.title,
                frame: frame,
                section: layout.section(of: frame),
                isOnScreen: MenuBarGeometry.isOnScreen(frame, screens: screens),
                canMove: MenuBarGeometry.canMove(bundleID: app?.bundleIdentifier, identifier: raw.identifier),
                windowID: MenuBarGeometry.windowID(for: raw.frame, pid: raw.pid, in: windows)
            )
        }
        .sorted { $0.frame.minX < $1.frame.minX }
        cache = (Date(), icons)
        return icons
    }

    public func press(_ icon: MenuBarIcon) async throws {
        guard isTrusted else { throw MenuBarItemsError.needsAccessibility }
        guard icon.pid != ownPID else { throw MenuBarItemsError.iconGone }
        cache = nil
        if await engine.press(icon.id) {
            return
        }
        // Apps that don't answer AXPress get a real click, if the icon can be seen.
        guard let axFrame = await engine.frame(of: icon.id) else { throw MenuBarItemsError.iconGone }
        let frame = AX.flip(axFrame)
        guard MenuBarGeometry.isOnScreen(frame, screens: Self.screens()) else { throw MenuBarItemsError.iconGone }
        SyntheticMouse.click(at: CGPoint(x: axFrame.midX, y: axFrame.midY))
    }

    public func move(_ icon: MenuBarIcon, to section: MenuBarIconSection) async throws {
        guard isTrusted else { throw MenuBarItemsError.needsAccessibility }
        guard isInstalled else { throw MenuBarItemsError.notInstalled }
        guard icon.canMove else { throw MenuBarItemsError.cannotMove }
        guard icon.section != section else { return }
        if section == .alwaysHidden, !hasAlwaysHiddenSection { throw MenuBarItemsError.moveFailed }

        let before = revealed
        reveal([.hidden, .alwaysHidden])
        defer { reveal(before) }
        // Let the menu bar lay itself out with every divider showing.
        try? await Task.sleep(for: .milliseconds(300))
        cache = nil
        _ = await icons()
        guard let axFrame = await engine.frame(of: icon.id) else { throw MenuBarItemsError.iconGone }
        let start = CGPoint(x: axFrame.midX, y: axFrame.midY)
        guard let drop = layout.dropPoint(for: section, y: AX.flip(axFrame).midY) else { throw MenuBarItemsError.moveFailed }
        let end = AX.flip(drop)
        await SyntheticMouse.commandDrag(from: start, to: end)
        try? await Task.sleep(for: .milliseconds(250))
        cache = nil
        let moved = await icons().first { $0.id == icon.id }
        guard moved?.section == section else {
            log.error("Moving \(icon.id, privacy: .public) to \(section.rawValue, privacy: .public) didn't take")
            throw MenuBarItemsError.moveFailed
        }
    }

    public var isMenuOpen: Bool {
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { entry in
            (entry[kCGWindowLayer as String] as? Int) == menuLevel
                && (entry[kCGWindowOwnerPID as String] as? Int32) != ownPID
        }
    }

    // MARK: Spacing

    private static let spacingKey = "NSStatusItemSpacing" as CFString
    private static let paddingKey = "NSStatusItemSelectionPadding" as CFString

    public var iconSpacing: MenuBarIconSpacing {
        let spacing = CFPreferencesCopyValue(Self.spacingKey, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int
        guard let spacing else { return .system }
        return MenuBarIconSpacing.allCases.first { $0.values?.spacing == spacing } ?? .system
    }

    public func setIconSpacing(_ spacing: MenuBarIconSpacing) {
        let values = spacing.values
        CFPreferencesSetValue(Self.spacingKey, values.map { NSNumber(value: $0.spacing) }, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSetValue(Self.paddingKey, values.map { NSNumber(value: $0.padding) }, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    // MARK: Helpers

    /// Where macOS keeps a status item's position.
    static func positionKey(_ autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    /// Removing a status item forgets where it was; put the positions back after.
    private static func keepingPositions(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let saved = autosaveNames.compactMap { name in defaults.object(forKey: positionKey(name)).map { (name, $0) } }
        body()
        for (name, value) in saved {
            defaults.set(value, forKey: positionKey(name))
        }
    }

    /// Status-level windows (menu bar icons) from the window server, on screen or not.
    static func statusWindows() -> [MenuBarGeometry.StatusWindow] {
        let level = Int(CGWindowLevelForKey(.statusWindow))
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == level,
                  let id = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return nil }
            return MenuBarGeometry.StatusWindow(id: id, pid: pid, bounds: bounds)
        }
    }

    static func screens() -> [MenuBarScreen] {
        NSScreen.screens.map { screen in
            var notch: CGRect?
            if var left = screen.auxiliaryTopLeftArea, var right = screen.auxiliaryTopRightArea {
                // Documented as the screen's own coordinates; make them global.
                if !screen.frame.contains(CGPoint(x: left.midX, y: left.midY)) {
                    left = left.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                    right = right.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                }
                notch = MenuBarScreen.notch(topLeft: left, topRight: right)
            }
            return MenuBarScreen(frame: screen.frame, notch: notch)
        }
    }
}

// MARK: - KKit's status items

/// The ‹ chevron: always visible, right of the hidden icons.
@MainActor
final class ChevronItem: NSResponder {
    private let statusItem: NSStatusItem
    private let onEvent: @MainActor (MenuBarChevronEvent) -> Void
    private var trackingArea: NSTrackingArea?

    init(autosaveName: String, onEvent: @escaping @MainActor (MenuBarChevronEvent) -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onEvent = onEvent
        super.init()
        statusItem.autosaveName = autosaveName
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = String(localized: "Show hidden menu bar icons (⌥-click: everything)")
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
            button.addTrackingArea(area)
            trackingArea = area
        }
        setOpen(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    var frame: CGRect? { statusItem.button?.window?.frame }

    func setOpen(_ open: Bool) {
        guard let button = statusItem.button else { return }
        let name = open ? "chevron.compact.right" : "chevron.compact.left"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        image?.isTemplate = true
        button.image = image
        button.setAccessibilityLabel(open
            ? String(localized: "Hide menu bar icons")
            : String(localized: "Show hidden menu bar icons"))
    }

    func remove() {
        if let trackingArea {
            statusItem.button?.removeTrackingArea(trackingArea)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func clicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let alternate = event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true
        onEvent(.click(alternate: alternate))
    }

    override func mouseEntered(with event: NSEvent) {
        onEvent(.hover)
    }
}

/// A divider: a faint line while its section shows, 10 000 pt of nothing while it's
/// hidden.
@MainActor
final class DividerItem {
    enum Style {
        case hidden
        case alwaysHidden
    }

    static let collapsedLength: CGFloat = 10_000
    static let shownLength: CGFloat = 12

    private let statusItem: NSStatusItem
    private let style: Style

    init(autosaveName: String, style: Style) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: Self.collapsedLength)
        self.style = style
        statusItem.autosaveName = autosaveName
        statusItem.button?.setAccessibilityLabel(style == .hidden
            ? String(localized: "KKit: hidden icons start here")
            : String(localized: "KKit: always-hidden icons start here"))
        statusItem.button?.toolTip = style == .hidden
            ? String(localized: "⌘-drag icons left of this line to hide them")
            : String(localized: "⌘-drag icons left of this line to keep them hidden")
        setRevealed(false)
    }

    var frame: CGRect? { statusItem.button?.window?.frame }

    func setRevealed(_ revealed: Bool) {
        statusItem.length = revealed ? Self.shownLength : Self.collapsedLength
        statusItem.button?.image = revealed ? Self.image(style) : nil
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Drawn whenever AppKit likes, so nothing main-actor in the drawing handler.
    nonisolated private static func image(_ style: Style) -> NSImage {
        let image = NSImage(size: NSSize(width: 6, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            switch style {
            case .hidden:
                NSBezierPath(roundedRect: NSRect(x: rect.midX - 0.75, y: 2, width: 1.5, height: 12), xRadius: 0.75, yRadius: 0.75).fill()
            case .alwaysHidden:
                for index in 0..<4 {
                    NSBezierPath(ovalIn: NSRect(x: rect.midX - 1, y: 2 + CGFloat(index) * 3.5, width: 2, height: 2)).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Synthetic mouse

/// Clicks and ⌘-drags posted at the HID level, marked so KKit's own tap ignores them.
/// Points are in Core Graphics coordinates (top-left origin).
@MainActor
enum SyntheticMouse {
    static func click(at point: CGPoint) {
        let saved = CGEvent(source: nil)?.location
        post(.leftMouseDown, at: point)
        post(.leftMouseUp, at: point)
        if let saved {
            CGWarpMouseCursorPosition(saved)
        }
    }

    static func commandDrag(from start: CGPoint, to end: CGPoint) async {
        let saved = CGEvent(source: nil)?.location
        postCommand(down: true)
        post(.mouseMoved, at: start, flags: .maskCommand)
        post(.leftMouseDown, at: start, flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(60))
        let steps = 16
        for step in 1...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
            post(.leftMouseDragged, at: point, flags: .maskCommand)
            try? await Task.sleep(for: .milliseconds(16))
        }
        try? await Task.sleep(for: .milliseconds(80))
        post(.leftMouseUp, at: end, flags: .maskCommand)
        postCommand(down: false)
        if let saved {
            CGWarpMouseCursorPosition(saved)
        }
    }

    private static func post(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags = []) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: CGEventTapInputService.ownEventMarker)
        event.post(tap: .cghidEventTap)
    }

    private static func postCommand(down: Bool) {
        // kVK_Command
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: down) else { return }
        event.type = .flagsChanged
        event.flags = down ? .maskCommand : []
        event.setIntegerValueField(.eventSourceUserData, value: CGEventTapInputService.ownEventMarker)
        event.post(tap: .cghidEventTap)
    }
}
