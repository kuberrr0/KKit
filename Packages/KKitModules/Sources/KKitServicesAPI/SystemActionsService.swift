import Foundation

/// System switches and actions for Quick Toggles. Each is implemented the least
/// disruptive way available (DESIGN.md §3.14); some use AppleScript and so ask for
/// Automation permission per target app the first time.
@MainActor
public protocol SystemActionsService: AnyObject {
    var isDarkMode: Bool { get }
    func setDarkMode(_ on: Bool) async throws

    var isDockAutohide: Bool { get }
    func setDockAutohide(_ on: Bool) async throws

    var isMenuBarAutohide: Bool { get }
    func setMenuBarAutohide(_ on: Bool) async throws

    /// Finder's "show hidden files". Changing it relaunches Finder.
    var showsHiddenFiles: Bool { get }
    func setShowsHiddenFiles(_ on: Bool) async throws

    /// `nil` on Macs without Wi-Fi.
    var isWiFiOn: Bool? { get }
    func setWiFi(_ on: Bool) async throws

    /// Ejects every ejectable volume. Returns how many were ejected.
    @discardableResult
    func ejectAllDisks() async throws -> Int
    func emptyTrash() async throws
    func lockScreen() async throws
    func sleepDisplays() async throws
    func startScreenSaver() async throws

    /// The wallpaper of a display, for the "hide desktop icons" cover.
    func desktopImageURL(forDisplay displayID: UInt32) -> URL?
}

/// Thrown by system actions.
public struct SystemActionError: LocalizedError, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
