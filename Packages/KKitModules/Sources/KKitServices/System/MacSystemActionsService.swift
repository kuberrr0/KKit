import AppKit
import CoreWLAN
import Foundation
import KKitCore
import KKitServicesAPI

/// System switches for Quick Toggles. Each uses the least disruptive way available:
/// AppleScript for appearance and Dock settings (Automation permission, asked once per
/// target app), CoreWLAN for Wi-Fi, `diskutil`/`pmset` for disks and displays.
@MainActor
public final class MacSystemActionsService: SystemActionsService {
    private let log = KKitLog.logger("systemActions")

    public init() {}

    // MARK: Appearance

    public var isDarkMode: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    public func setDarkMode(_ on: Bool) async throws {
        try await ProcessRunner.appleScript(
            "tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)"
        )
    }

    // MARK: Dock and menu bar

    public var isDockAutohide: Bool {
        Self.preference("autohide", domain: "com.apple.dock")
    }

    public func setDockAutohide(_ on: Bool) async throws {
        try await ProcessRunner.appleScript(
            "tell application \"System Events\" to tell dock preferences to set autohide to \(on)"
        )
    }

    public var isMenuBarAutohide: Bool {
        UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
    }

    public func setMenuBarAutohide(_ on: Bool) async throws {
        try await ProcessRunner.appleScript(
            "tell application \"System Events\" to tell dock preferences to set autohide menu bar to \(on)"
        )
    }

    // MARK: Finder

    public var showsHiddenFiles: Bool {
        Self.preference("AppleShowAllFiles", domain: "com.apple.finder")
    }

    public func setShowsHiddenFiles(_ on: Bool) async throws {
        try await ProcessRunner.run("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", on ? "true" : "false"])
        // Finder only reads the setting at launch.
        _ = try? await ProcessRunner.run("/usr/bin/killall", ["Finder"])
    }

    public func emptyTrash() async throws {
        try await ProcessRunner.appleScript("tell application \"Finder\" to empty trash")
    }

    public func ejectAllDisks() async throws -> Int {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var ejected = 0
        var failures: [String] = []
        for volume in volumes {
            guard let values = try? volume.resourceValues(forKeys: Set(keys)),
                  values.volumeIsRootFileSystem != true
            else { continue }
            let isNetwork = values.volumeIsLocal == false
            let isEjectable = values.volumeIsEjectable == true || (values.volumeIsRemovable == true && values.volumeIsInternal != true)
            guard isNetwork || isEjectable else { continue }
            do {
                try await ProcessRunner.run("/usr/sbin/diskutil", [isNetwork ? "unmount" : "eject", volume.path])
                ejected += 1
            } catch {
                failures.append(volume.lastPathComponent)
                log.error("Couldn't eject \(volume.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if !failures.isEmpty {
            throw SystemActionError(String(localized: "Couldn't eject \(failures.formatted(.list(type: .and))). It may be in use."))
        }
        return ejected
    }

    // MARK: Wi-Fi

    public var isWiFiOn: Bool? {
        CWWiFiClient.shared().interface()?.powerOn()
    }

    public func setWiFi(_ on: Bool) async throws {
        guard let interface = CWWiFiClient.shared().interface() else {
            throw SystemActionError(String(localized: "This Mac has no Wi-Fi."))
        }
        try interface.setPower(on)
    }

    // MARK: Screen

    public func lockScreen() async throws {
        // login.framework's SACLockScreenImmediate is what the menu bar's "Lock Screen"
        // uses. It's private, so it's loaded dynamically with a public fallback.
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(path, RTLD_LAZY), let symbol = dlsym(handle, "SACLockScreenImmediate") {
            typealias LockScreen = @convention(c) () -> Int32
            let lock = unsafeBitCast(symbol, to: LockScreen.self)
            _ = lock()
            return
        }
        log.info("SACLockScreenImmediate unavailable; sleeping displays instead")
        try await sleepDisplays()
    }

    public func sleepDisplays() async throws {
        try await ProcessRunner.run("/usr/bin/pmset", ["displaysleepnow"])
    }

    public func startScreenSaver() async throws {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        guard NSWorkspace.shared.open(url) else {
            throw SystemActionError(String(localized: "Couldn't start the screen saver."))
        }
    }

    public func desktopImageURL(forDisplay displayID: UInt32) -> URL? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }

    // MARK: Private

    /// Reads another app's preference fresh from disk (UserDefaults caches).
    private static func preference(_ key: String, domain: String) -> Bool {
        CFPreferencesAppSynchronize(domain as CFString)
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else { return false }
        return (value as? Bool) ?? ((value as? NSNumber)?.boolValue ?? false)
    }
}
