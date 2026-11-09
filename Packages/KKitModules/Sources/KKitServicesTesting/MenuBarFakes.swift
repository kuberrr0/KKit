import CoreGraphics
import Foundation
import KKitCore
import KKitServicesAPI

/// Menu bar icons kept in a list (`iconList`, in menu bar order). `install` and `reveal` only record what was asked;
/// `move` changes the icon's section; `sendChevron` plays a click or hover.
@MainActor
public final class FakeMenuBarItemsService: MenuBarItemsService {
    public var isTrusted = true
    public var iconList: [MenuBarIcon] = []
    public var dividersOutOfOrder = false
    public var isMenuOpen = false
    public var chevronFrame: CGRect? = CGRect(x: 1200, y: 875, width: 20, height: 24)
    public var pressError: (any Error)?
    public private(set) var isInstalled = false
    public private(set) var hasAlwaysHiddenSection = false
    public private(set) var revealed: Set<MenuBarIconSection> = []
    public private(set) var revealHistory: [Set<MenuBarIconSection>] = []
    public private(set) var pressed: [MenuBarIcon] = []
    /// What each pressed icon's section showed when it was pressed.
    public private(set) var revealedWhenPressed: [Set<MenuBarIconSection>] = []
    public private(set) var moves: [(id: String, section: MenuBarIconSection)] = []
    public private(set) var resetCount = 0
    public private(set) var iconSpacing: MenuBarIconSpacing = .system
    private var onChevron: (@MainActor (MenuBarChevronEvent) -> Void)?

    public init() {}

    public func install(alwaysHiddenSection: Bool, onChevron: @escaping @MainActor (MenuBarChevronEvent) -> Void) {
        isInstalled = true
        hasAlwaysHiddenSection = alwaysHiddenSection
        self.onChevron = onChevron
    }

    public func uninstall() {
        isInstalled = false
        hasAlwaysHiddenSection = false
        revealed = []
        onChevron = nil
    }

    public func reveal(_ sections: Set<MenuBarIconSection>) {
        var sections = sections
        sections.remove(.shown)
        if sections.contains(.alwaysHidden) {
            sections.insert(.hidden)
        }
        revealed = sections
        revealHistory.append(sections)
    }

    public func icons() async -> [MenuBarIcon] {
        guard isTrusted else { return [] }
        return iconList.map { icon in
            var icon = icon
            // Hidden icons are on screen only while their section shows; shown ones keep
            // what they were given (behind the notch or not).
            if icon.section != .shown {
                icon.isOnScreen = revealed.contains(icon.section)
            }
            return icon
        }
    }

    public func press(_ icon: MenuBarIcon) async throws {
        guard isTrusted else { throw MenuBarItemsError.needsAccessibility }
        if let pressError { throw pressError }
        pressed.append(icon)
        revealedWhenPressed.append(revealed)
    }

    public func move(_ icon: MenuBarIcon, to section: MenuBarIconSection) async throws {
        guard isTrusted else { throw MenuBarItemsError.needsAccessibility }
        guard icon.canMove else { throw MenuBarItemsError.cannotMove }
        guard let index = iconList.firstIndex(where: { $0.id == icon.id }) else { throw MenuBarItemsError.iconGone }
        iconList[index].section = section
        moves.append((icon.id, section))
    }

    public func resetDividers() {
        resetCount += 1
    }

    public func setIconSpacing(_ spacing: MenuBarIconSpacing) {
        iconSpacing = spacing
    }

    // MARK: Driving it

    public func sendChevron(_ event: MenuBarChevronEvent) {
        onChevron?(event)
    }

    @discardableResult
    public func addIcon(
        _ id: String,
        appName: String = "App",
        title: String = "",
        section: MenuBarIconSection = .shown,
        x: CGFloat = 900,
        canMove: Bool = true,
        windowID: UInt32? = nil
    ) -> MenuBarIcon {
        let icon = MenuBarIcon(
            id: id,
            pid: 200 + Int32(iconList.count),
            bundleID: "com.example.\(appName.lowercased())",
            appName: appName,
            title: title,
            frame: CGRect(x: x, y: 875, width: 24, height: 24),
            section: section,
            canMove: canMove,
            windowID: windowID
        )
        iconList.append(icon)
        return icon
    }
}
