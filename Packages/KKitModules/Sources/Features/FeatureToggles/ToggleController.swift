import Foundation
import KKitServicesAPI
import Observation

/// Reads and flips the system switches. `revision` changes after every action, so
/// tiles that read `isOn` re-render.
@MainActor
@Observable
final class ToggleController {
    private(set) var revision = 0
    private(set) var busy: Set<SystemToggle> = []

    private let actions: any SystemActionsService
    private let desktop: DesktopCover

    /// Shows a short Island HUD for one-shot actions ("Ejected 2 disks").
    @ObservationIgnored var onHUD: (@MainActor (IslandHUD) -> Void)?

    init(actions: any SystemActionsService, desktop: DesktopCover) {
        self.actions = actions
        self.desktop = desktop
    }

    /// Whether a switch is on. `nil` for actions and for unavailable switches.
    func isOn(_ toggle: SystemToggle) -> Bool? {
        _ = revision
        switch toggle {
        case .darkMode: return actions.isDarkMode
        case .hideDesktopIcons: return desktop.isHidingIcons
        case .hiddenFiles: return actions.showsHiddenFiles
        case .wifi: return actions.isWiFiOn
        case .dockAutohide: return actions.isDockAutohide
        case .menuBarAutohide: return actions.isMenuBarAutohide
        case .ejectDisks, .emptyTrash, .lockScreen, .sleepDisplays, .screenSaver: return nil
        }
    }

    func isAvailable(_ toggle: SystemToggle) -> Bool {
        toggle != .wifi || actions.isWiFiOn != nil
    }

    func perform(_ toggle: SystemToggle) async throws {
        guard !busy.contains(toggle) else { return }
        busy.insert(toggle)
        defer {
            busy.remove(toggle)
            revision += 1
        }
        do {
            try await run(toggle)
        } catch {
            onHUD?(IslandHUD(
                id: "toggleError",
                symbol: "exclamationmark.triangle.fill",
                title: error.localizedDescription,
                tint: .warning,
                duration: 4
            ))
            throw error
        }
    }

    private func run(_ toggle: SystemToggle) async throws {
        switch toggle {
        case .darkMode:
            try await actions.setDarkMode(!actions.isDarkMode)
        case .hideDesktopIcons:
            desktop.setHidingIcons(!desktop.isHidingIcons)
        case .hiddenFiles:
            try await actions.setShowsHiddenFiles(!actions.showsHiddenFiles)
        case .wifi:
            guard let on = actions.isWiFiOn else { throw SystemActionError(String(localized: "This Mac has no Wi-Fi.")) }
            try await actions.setWiFi(!on)
        case .dockAutohide:
            try await actions.setDockAutohide(!actions.isDockAutohide)
        case .menuBarAutohide:
            try await actions.setMenuBarAutohide(!actions.isMenuBarAutohide)
        case .ejectDisks:
            let count = try await actions.ejectAllDisks()
            onHUD?(IslandHUD(
                id: "eject",
                symbol: "eject.fill",
                title: count == 0 ? String(localized: "Nothing to eject") : String(localized: "Ejected \(count) disks")
            ))
        case .emptyTrash:
            try await actions.emptyTrash()
            onHUD?(IslandHUD(id: "trash", symbol: "trash.fill", title: String(localized: "Trash emptied")))
        case .lockScreen:
            try await actions.lockScreen()
        case .sleepDisplays:
            try await actions.sleepDisplays()
        case .screenSaver:
            try await actions.startScreenSaver()
        }
    }

    /// Something else changed a switch (System Settings, another app).
    func invalidate() {
        revision += 1
    }
}
