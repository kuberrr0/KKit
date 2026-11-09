import ApplicationServices
import CoreGraphics
import Foundation

/// Reads other apps' menu bar icons (each app's `AXExtrasMenuBar`) and presses them.
/// Holds the `AXUIElement`s, off the main thread. Frames are in Accessibility
/// coordinates (top-left origin of the main display).
///
/// Never give it KKit's own process id: KKit would answer the query itself on this
/// actor's thread, and SwiftUI can't be read off the main thread.
actor AXMenuBarEngine {
    struct RawIcon: Sendable {
        var key: String
        var pid: pid_t
        var identifier: String?
        var title: String
        var frame: CGRect
    }

    /// Shorter than the windows' timeout: every running app is asked.
    private let timeout: Float = 0.15
    private var elements: [String: AXUIElement] = [:]

    /// `prefixes` names each process for the icons' keys (its bundle id).
    func icons(prefixes: [pid_t: String]) -> [RawIcon] {
        var icons: [RawIcon] = []
        var elements: [String: AXUIElement] = [:]
        for (pid, prefix) in prefixes.sorted(by: { $0.key < $1.key }) {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, timeout)
            guard let extras = AX.element(app, "AXExtrasMenuBar") else { continue }
            let children = AX.elements(extras, "AXChildren")
            guard !children.isEmpty else { continue }
            let described = children.map { child in
                (element: child, identifier: AX.string(child, "AXIdentifier"), title: Self.title(of: child))
            }
            let keys = MenuBarGeometry.keys(prefix: prefix, entries: described.map { (identifier: $0.identifier, title: $0.title) })
            for (entry, key) in zip(described, keys) {
                guard let frame = AX.frame(entry.element), frame.width > 0 else { continue }
                elements[key] = entry.element
                icons.append(RawIcon(key: key, pid: pid, identifier: entry.identifier, title: entry.title, frame: frame))
            }
        }
        self.elements = elements
        return icons
    }

    /// The icon's current frame, or `nil` if it's gone.
    func frame(of key: String) -> CGRect? {
        guard let element = elements[key] else { return nil }
        return AX.frame(element)
    }

    /// Presses the icon. Opening a menu keeps the app busy until the menu closes, so
    /// "can't complete" (a timeout) counts as pressed.
    func press(_ key: String) -> Bool {
        guard let element = elements[key] else { return false }
        AXUIElementSetMessagingTimeout(element, timeout)
        let result = AXUIElementPerformAction(element, "AXPress" as CFString)
        return result == .success || result == .cannotComplete
    }

    private static func title(of element: AXUIElement) -> String {
        for attribute in ["AXTitle", "AXDescription", "AXHelp"] {
            if let text = AX.string(element, attribute)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        return ""
    }
}
