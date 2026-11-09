import AppKit
import ApplicationServices
import KKitCore
import KKitServicesAPI

/// The app in front, its menu bar and the selected text, through the Accessibility API.
@MainActor
public final class AXAccessibilityService: AccessibilityService {
    private let engine = AXMenuEngine()
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    /// Menus are read again after this long (apps change them as their state changes).
    private let cacheLifetime: TimeInterval = 8
    private var cache: [pid_t: (date: Date, items: [MenuItemInfo])] = [:]

    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func frontmostApp() -> FrontmostApp? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID else { return nil }
        return FrontmostApp(pid: app.processIdentifier, bundleID: app.bundleIdentifier, name: app.localizedName ?? "")
    }

    public func menuItems(of pid: Int32) async -> [MenuItemInfo] {
        guard isTrusted else { return [] }
        if let cached = cache[pid], Date().timeIntervalSince(cached.date) < cacheLifetime {
            return cached.items
        }
        let items = await engine.menuItems(pid: pid)
        cache[pid] = (Date(), items)
        // Forget apps that quit.
        let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        cache = cache.filter { running.contains($0.key) }
        return items
    }

    public func press(_ item: MenuItemInfo) async throws {
        guard isTrusted else { throw AccessibilityError.needsAccessibility }
        cache[item.pid] = nil
        guard await engine.press(path: item.path, pid: item.pid) else {
            throw AccessibilityError.itemGone
        }
    }

    public func selectedText() async -> String? {
        guard isTrusted else { return nil }
        return await engine.selectedText()
    }
}

actor AXMenuEngine {
    private let maxItems = 3000
    private let maxDepth = 4

    func menuItems(pid: pid_t) -> [MenuItemInfo] {
        let app = AX.application(pid)
        guard let menuBar = AX.element(app, "AXMenuBar") else { return [] }
        var items: [MenuItemInfo] = []
        // The first menu is the Apple menu, which is the same in every app.
        for top in AX.elements(menuBar, "AXChildren").dropFirst() {
            guard let title = AX.string(top, "AXTitle"), !title.isEmpty else { continue }
            for menu in AX.elements(top, "AXChildren") {
                collect(menu, path: [title], pid: pid, depth: 1, into: &items)
            }
            if items.count >= maxItems { break }
        }
        return items
    }

    func press(path: [String], pid: pid_t) -> Bool {
        let app = AX.application(pid)
        guard let menuBar = AX.element(app, "AXMenuBar"), !path.isEmpty else { return false }
        var current: [AXUIElement] = AX.elements(menuBar, "AXChildren")
        var target: AXUIElement?
        for (index, title) in path.enumerated() {
            guard let match = current.first(where: { AX.string($0, "AXTitle") == title }) else { return false }
            if index == path.count - 1 {
                target = match
            } else {
                // A menu bar item or submenu item holds one AXMenu whose children are items.
                current = AX.elements(match, "AXChildren").flatMap { AX.elements($0, "AXChildren") }
            }
        }
        guard let target else { return false }
        return AX.perform(target, "AXPress")
    }

    func selectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, AX.messagingTimeout)
        guard let focused = AX.element(systemWide, "AXFocusedUIElement"),
              let text = AX.string(focused, "AXSelectedText"),
              !text.isEmpty else { return nil }
        return text
    }

    private func collect(_ menu: AXUIElement, path: [String], pid: pid_t, depth: Int, into items: inout [MenuItemInfo]) {
        guard depth <= maxDepth else { return }
        for item in AX.elements(menu, "AXChildren") {
            guard items.count < maxItems else { return }
            guard let title = AX.string(item, "AXTitle"), !title.isEmpty else { continue }
            let submenus = AX.elements(item, "AXChildren")
            let itemPath = path + [title]
            if !submenus.isEmpty {
                for submenu in submenus {
                    collect(submenu, path: itemPath, pid: pid, depth: depth + 1, into: &items)
                }
                continue
            }
            items.append(MenuItemInfo(
                path: itemPath,
                shortcut: Self.shortcut(of: item),
                isEnabled: AX.bool(item, "AXEnabled") ?? true,
                isChecked: !(AX.string(item, "AXMenuItemMarkChar") ?? "").isEmpty,
                pid: pid
            ))
        }
    }

    /// "⇧⌘S" from the item's command character and modifier mask (bit 0 shift, bit 1
    /// option, bit 2 control, bit 3 "no command").
    static func shortcut(of item: AXUIElement) -> String? {
        guard let character = AX.string(item, "AXMenuItemCmdChar"), !character.isEmpty else { return nil }
        return shortcutText(character: character, modifiers: AX.int(item, "AXMenuItemCmdModifiers") ?? 0)
    }

    static func shortcutText(character: String, modifiers: Int) -> String {
        var text = ""
        if modifiers & 4 != 0 { text += "⌃" }
        if modifiers & 2 != 0 { text += "⌥" }
        if modifiers & 1 != 0 { text += "⇧" }
        if modifiers & 8 == 0 { text += "⌘" }
        return text + character.uppercased()
    }
}
