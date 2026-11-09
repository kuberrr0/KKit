import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// One-tap system switches and actions, each also a command and hotkey.
/// DESIGN.md §3.14.
@MainActor
public final class TogglesFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "quickToggles",
        name: String(localized: "Quick Toggles"),
        symbol: "square.grid.2x2",
        summary: String(localized: "Dark mode, Wi-Fi, hide desktop icons, lock screen and more, one tap away."),
        category: .system,
        optionalPermissions: [.automation],
        enabledByDefault: true
    )

    private let context: FeatureContext
    private var desktop: DesktopCover?
    private var controller: ToggleController?
    private var tasks: [Task<Void, Never>] = []

    public init(context: FeatureContext) {
        self.context = context
    }

    /// Created lazily so `init` stays cheap and doesn't touch services.
    private func ensureController() -> ToggleController {
        if let controller { return controller }
        let desktop = DesktopCover(overlays: context.overlays, actions: context.systemActions)
        let controller = ToggleController(actions: context.systemActions, desktop: desktop)
        self.desktop = desktop
        self.controller = controller
        return controller
    }

    public func start() async throws {
        let controller = ensureController()
        let island = context.island
        controller.onHUD = { hud in island.showHUD(hud) }

        let displays = context.events.stream { $0 == .displaysChanged }
        tasks.append(Task { [weak self] in
            for await _ in displays {
                self?.desktop?.rebuild()
            }
        })
        // Switches can change in System Settings; re-read them when apps change.
        let frontmost = context.events.stream { event in
            if case .frontmostAppChanged = event { return true }
            return false
        }
        tasks.append(Task { [weak self] in
            for await _ in frontmost {
                self?.controller?.invalidate()
            }
        })
    }

    public func stop() async {
        tasks.forEach { $0.cancel() }
        tasks = []
        desktop?.tearDown()
        controller?.onHUD = nil
    }

    // MARK: Contributions

    public var commands: [Command] {
        let controller = ensureController()
        return SystemToggle.allCases.map { (toggle: SystemToggle) -> Command in
            let state: (@MainActor @Sendable () -> CommandState)? = toggle.isSwitch
                ? { [weak controller] in controller?.isOn(toggle) == true ? .on : .off }
                : nil
            return Command(
                id: toggle.commandID,
                title: toggle.commandTitle,
                symbol: toggle.symbol,
                keywords: toggle.keywords,
                isEnabled: { [weak controller] in
                    guard let controller else { return false }
                    return controller.isAvailable(toggle) && !controller.busy.contains(toggle)
                },
                state: state
            ) { [weak controller] _ in
                try await controller?.perform(toggle)
            }
        }
    }

    public var quickToggles: [QuickToggle] {
        let all = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })
        return context.settings[ToggleSettings.tiles].compactMap { toggle in
            guard var command = all[toggle.commandID] else { return nil }
            command.title = toggle.title
            return QuickToggle(command)
        }
    }

    public var settingsPane: SettingsPane? {
        SettingsPane {
            TogglesSettingsView()
        }
    }
}
