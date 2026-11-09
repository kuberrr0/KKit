import KKitCore

/// Which mouse action resizes while the move modifiers are held.
enum ResizeTrigger: String, Codable, CaseIterable, Sendable {
    /// Right-drag with the move modifiers.
    case rightDrag
    /// Left-drag with the move modifiers plus ⇧.
    case shiftLeftDrag
    /// Both.
    case both

    var title: String {
        switch self {
        case .rightDrag: String(localized: "Right-drag")
        case .shiftLeftDrag: String(localized: "⇧ + left-drag")
        case .both: String(localized: "Either")
        }
    }
}

enum WindowsSettings {
    // Modifier + mouse
    static let mouseEnabled = SettingKey("mouseEnabled", default: true)
    /// ⌃⌥ by default.
    static let moveModifiers = SettingKey("moveModifiers", default: Shortcut.Modifiers([.control, .option]))
    static let resizeTrigger = SettingKey("resizeTrigger", default: ResizeTrigger.both)
    /// Resize from the corner nearest the cursor rather than always bottom-right.
    static let resizeFromNearestCorner = SettingKey("resizeFromNearestCorner", default: true)
    static let raiseOnDrag = SettingKey("raiseOnDrag", default: true)
    /// Snap to edges and corners at the end of a modifier-drag too.
    static let snapWhileModifierDragging = SettingKey("snapWhileModifierDragging", default: false)
    /// Modifier + double-click maximises or restores.
    static let doubleClickToMaximize = SettingKey("doubleClickToMaximize", default: true)

    // Snapping
    static let dragToSnap = SettingKey("dragToSnap", default: true)
    /// Stay out of the way while macOS 15's own edge tiling is on.
    static let deferToSystemTiling = SettingKey("deferToSystemTiling", default: true)
    /// Points between snapped windows and the screen edge.
    static let gap = SettingKey("gap", default: 0.0)
    /// Pressing a half's shortcut again cycles ½ → ⅓ → ⅔.
    static let cycleSizes = SettingKey("cycleSizes", default: true)
    /// Bundle ids KKit leaves alone (games, remote desktops).
    static let excludedApps = SettingKey("excludedApps", default: [String]())
}
