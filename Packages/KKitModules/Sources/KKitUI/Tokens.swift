import SwiftUI

/// Spacing on a 4-pt grid (DESIGN.md §5).
public enum KKSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
}

/// Corner radii (DESIGN.md §5).
public enum KKRadius {
    public static let control: CGFloat = 6
    public static let row: CGFloat = 10
    public static let panel: CGFloat = 16
}

/// Animations (DESIGN.md §5). Use `KKMotion.adapted(_:reduceMotion:)` so Reduce Motion
/// gets a cross-fade instead.
public enum KKMotion {
    /// Island grow/shrink.
    public static var island: Animation { .spring(response: 0.35, dampingFraction: 0.8) }
    /// HUD fades.
    public static var hudFade: Animation { .easeOut(duration: 0.12) }
    /// Small state changes (tiles, toggles).
    public static var quick: Animation { .easeInOut(duration: 0.15) }

    public static func adapted(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : animation
    }
}

/// Fixed sizes shared by hosts.
public enum KKMetrics {
    public static let menuBarPopoverWidth: CGFloat = 340
    public static let tileHeight: CGFloat = 72
    public static let featureIconSize: CGFloat = 22
}
