import CoreGraphics
import KKitCore
import SwiftUI

/// How high a KKit panel floats.
public enum OverlayLevel: Sendable, Hashable {
    /// Just above the desktop icons, below every app window (hide desktop icons).
    case aboveDesktopIcons
    /// Above normal windows (Floating Bar, pickers).
    case floating
    /// Level with the menu bar (Island).
    case statusBar
    /// Above everything, including full-screen apps' menus (tints, lock overlays).
    case screenSaver
}

/// Which screen a panel goes on.
public enum OverlayScreen: Sendable, Hashable {
    case main
    case withCursor
    /// `CGDirectDisplayID`
    case display(UInt32)
}

/// Where a panel goes on its screen.
public enum OverlayPlacement: Sendable, Equatable {
    /// Centred, `size` points.
    case centered(size: CGSize)
    /// Horizontally centred, `offset` points below the top of the visible frame.
    case topCenter(size: CGSize, offset: CGFloat)
    /// Covers the whole screen (tints, region pickers).
    case fullScreen
    /// An explicit frame in global screen coordinates.
    case frame(CGRect)
}

public struct OverlayConfiguration: Sendable, Equatable {
    public var level: OverlayLevel
    public var screen: OverlayScreen
    public var placement: OverlayPlacement
    /// Takes keyboard focus when shown (Floating Bar). Never activates KKit.
    public var acceptsKeyFocus: Bool
    /// Mouse events pass through to the windows below (tints, HUDs).
    public var ignoresMouseEvents: Bool
    public var hasShadow: Bool
    /// Hide when the panel loses key focus (Floating Bar).
    public var hidesOnResignKey: Bool
    /// Can be dragged around by its background (pinned screenshots).
    public var isMovable: Bool

    public init(
        level: OverlayLevel = .floating,
        screen: OverlayScreen = .withCursor,
        placement: OverlayPlacement,
        acceptsKeyFocus: Bool = false,
        ignoresMouseEvents: Bool = false,
        hasShadow: Bool = true,
        hidesOnResignKey: Bool = false,
        isMovable: Bool = false
    ) {
        self.level = level
        self.screen = screen
        self.placement = placement
        self.acceptsKeyFocus = acceptsKeyFocus
        self.ignoresMouseEvents = ignoresMouseEvents
        self.hasShadow = hasShadow
        self.hidesOnResignKey = hidesOnResignKey
        self.isMovable = isMovable
    }
}

/// A KKit panel created by the overlay service.
@MainActor
public protocol OverlayHandle: AnyObject {
    var isVisible: Bool { get }
    func show()
    func hide()
    func setContent(_ content: AnyView)
    func setConfiguration(_ configuration: OverlayConfiguration)
    /// Hides and releases the panel. The handle is unusable afterwards.
    func close()
}

/// A screen, for features that lay things out per display.
public struct ScreenInfo: Sendable, Equatable, Identifiable {
    public var id: UInt32
    public var name: String
    public var frame: CGRect
    public var visibleFrame: CGRect
    /// Height of the notch area; 0 on screens without a notch.
    public var notchHeight: CGFloat
    public var isMain: Bool

    public init(id: UInt32, name: String, frame: CGRect, visibleFrame: CGRect, notchHeight: CGFloat, isMain: Bool) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.notchHeight = notchHeight
        self.isMain = isMain
    }
}

/// What the region picker lets the user choose.
public enum RegionPickerStyle: Sendable, Hashable {
    /// Drag out a rectangle. Space switches to picking a window.
    case area
    /// Click a window. Space switches to dragging an area.
    case window
    /// Click a whole screen.
    case screen
}

public struct RegionPickerOptions: Sendable, Hashable {
    public var style: RegionPickerStyle
    /// Shown at the top of the screen: "Select text to copy".
    public var prompt: String?

    public init(style: RegionPickerStyle = .area, prompt: String? = nil) {
        self.style = style
        self.prompt = prompt
    }
}

/// What the user picked.
public struct RegionSelection: Sendable, Hashable {
    /// The display the selection is on (`CGDirectDisplayID`).
    public var displayID: UInt32
    /// In global screen coordinates (points, bottom-left origin, like `NSScreen.frame`).
    public var rect: CGRect
    /// Set when a window was picked (`CGWindowID`).
    public var windowID: UInt32?

    public init(displayID: UInt32, rect: CGRect, windowID: UInt32? = nil) {
        self.displayID = displayID
        self.rect = rect
        self.windowID = windowID
    }
}

/// Creates KKit's panels with the right level, Spaces, full-screen and multi-display
/// behaviour, and posts `AppEvent.displaysChanged` when screens change.
///
/// Features never create `NSWindow`/`NSPanel` themselves; they ask this service.
@MainActor
public protocol OverlayService: AnyObject {
    func makePanel(_ configuration: OverlayConfiguration, content: AnyView) -> any OverlayHandle
    var screens: [ScreenInfo] { get }
    /// Dims every screen and lets the user drag out an area or click a window.
    /// ⎋ cancels (`nil`).
    func pickRegion(_ options: RegionPickerOptions) async -> RegionSelection?
}
