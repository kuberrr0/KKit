import CoreGraphics
import KKitServicesAPI

/// Where KKit's chevron and Always Hidden divider are, and what that says about other
/// icons. Pure geometry, so it can be tested. Frames are in AppKit global coordinates.
///
/// Right to left the menu bar reads: shown icons, the ‹ chevron, hidden icons, the
/// Always Hidden divider, always-hidden icons. The chevron is also the Hidden divider:
/// while hidden icons are hidden it is ~10 000 pt long with its arrow at the right end,
/// pushing everything left of it off the screen (the Always Hidden divider does the
/// same for its section). So icons are compared with the items' right edges, which
/// stay put whether an item is collapsed or showing.
struct MenuBarLayout: Sendable, Equatable {
    var chevron: CGRect?
    var alwaysHiddenDivider: CGRect?

    func section(of frame: CGRect) -> MenuBarIconSection {
        guard let chevron else { return .shown }
        if frame.midX >= chevron.maxX {
            return .shown
        }
        if let alwaysHiddenDivider, frame.midX < alwaysHiddenDivider.maxX {
            return .alwaysHidden
        }
        return .hidden
    }

    /// The Always Hidden divider is right of the chevron.
    var isOutOfOrder: Bool {
        guard let chevron, let alwaysHiddenDivider else { return false }
        return alwaysHiddenDivider.maxX > chevron.maxX
    }

    /// Where to drop an icon so a ⌘-drag puts it in `section`. Needs both items
    /// showing (not collapsed). The point is in AppKit coordinates, at the icon's height.
    ///
    /// macOS puts a dragged icon on whichever side of a neighbour the pointer is past
    /// the middle of, so each point sits just past an edge.
    func dropPoint(for section: MenuBarIconSection, y: CGFloat) -> CGPoint? {
        guard let chevron else { return nil }
        switch section {
        case .shown:
            return CGPoint(x: chevron.maxX + 3, y: y)
        case .hidden:
            return CGPoint(x: chevron.minX - 2, y: y)
        case .alwaysHidden:
            guard let alwaysHiddenDivider else { return nil }
            return CGPoint(x: alwaysHiddenDivider.minX - 3, y: y)
        }
    }
}

/// A screen, as far as menu bar icons care.
struct MenuBarScreen: Sendable, Equatable {
    var frame: CGRect
    /// The notch, in global coordinates; `nil` on screens without one.
    var notch: CGRect?

    /// The notch: the gap between the areas either side of it
    /// (`NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, in global coordinates).
    static func notch(topLeft: CGRect?, topRight: CGRect?) -> CGRect? {
        guard let topLeft, let topRight, topRight.minX > topLeft.maxX else { return nil }
        return CGRect(
            x: topLeft.maxX,
            y: min(topLeft.minY, topRight.minY),
            width: topRight.minX - topLeft.maxX,
            height: max(topLeft.height, topRight.height)
        )
    }
}

enum MenuBarGeometry {
    /// On some screen, whole, and not under a notch.
    static func isOnScreen(_ frame: CGRect, screens: [MenuBarScreen]) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let inset = frame.insetBy(dx: 1, dy: 1)
        guard let screen = screens.first(where: { $0.frame.contains(inset) }) else { return false }
        if let notch = screen.notch, notch.intersects(inset) {
            return false
        }
        return true
    }

    /// A status window from the window server: `bounds` in Core Graphics coordinates
    /// (top-left origin), like Accessibility positions.
    struct StatusWindow: Sendable, Equatable {
        var id: UInt32
        var pid: Int32
        var bounds: CGRect
    }

    /// The window whose bounds match an icon's Accessibility frame. Same owner first;
    /// any owner next (macOS 26 can report another process as the owner).
    static func windowID(for axFrame: CGRect, pid: Int32, in windows: [StatusWindow], tolerance: CGFloat = 2) -> UInt32? {
        func matches(_ window: StatusWindow) -> Bool {
            abs(window.bounds.minX - axFrame.minX) <= tolerance
                && abs(window.bounds.minY - axFrame.minY) <= tolerance
                && abs(window.bounds.width - axFrame.width) <= tolerance
                && abs(window.bounds.height - axFrame.height) <= tolerance
        }
        return windows.first { $0.pid == pid && matches($0) }?.id
            ?? windows.first(where: matches)?.id
    }

    /// Unique keys for one app's icons: the identifier, else the title, else the
    /// position; a repeated key gets its position added.
    static func keys(prefix: String, entries: [(identifier: String?, title: String)]) -> [String] {
        var seen: [String: Int] = [:]
        return entries.enumerated().map { index, entry in
            let base: String
            if let identifier = entry.identifier, !identifier.isEmpty {
                base = identifier
            } else if !entry.title.isEmpty {
                base = entry.title
            } else {
                base = "#\(index)"
            }
            let count = seen[base, default: 0]
            seen[base] = count + 1
            return count == 0 ? "\(prefix)/\(base)" : "\(prefix)/\(base)#\(index)"
        }
    }

    /// Icons macOS won't let anyone move.
    static func canMove(bundleID: String?, identifier: String?) -> Bool {
        guard bundleID == "com.apple.controlcenter", let identifier else { return true }
        return !["com.apple.menuextra.clock", "com.apple.menuextra.controlcenter"].contains(identifier)
    }
}
