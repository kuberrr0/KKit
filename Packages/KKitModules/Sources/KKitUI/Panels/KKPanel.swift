import AppKit

/// A borderless panel for KKit's overlays and hosts (Island, Floating Bar, pickers).
///
/// Only `OverlayService` and the hosts create these; features ask them instead.
public final class KKPanel: NSPanel {
    /// Whether the panel takes keyboard focus (Floating Bar: yes; HUDs, tints: no).
    public var acceptsKeyFocus: Bool

    public init(contentRect: NSRect, acceptsKeyFocus: Bool) {
        self.acceptsKeyFocus = acceptsKeyFocus
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    public override var canBecomeKey: Bool { acceptsKeyFocus }
    public override var canBecomeMain: Bool { false }
}
