import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Locks the keyboard (and optionally the mouse) while you clean it. DESIGN.md §3.18.
@MainActor
public final class CleanModeFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "cleanMode",
        name: String(localized: "Clean Mode"),
        symbol: "sparkles",
        summary: String(localized: "Locks the keyboard for a minute so you can wipe it."),
        category: .input,
        requiredPermissions: [.accessibility],
        enabledByDefault: false
    )

    private let context: FeatureContext
    let controller: CleanModeController

    public init(context: FeatureContext) {
        self.context = context
        self.controller = CleanModeController(input: context.input, overlays: context.overlays, settings: context.settings)
    }

    public func start() async throws {}

    public func stop() async {
        controller.unlock()
    }

    public var commands: [Command] {
        [
            Command(
                id: "cleanMode.start",
                title: String(localized: "Clean Keyboard"),
                subtitle: String(localized: "Locks the keyboard while you wipe it"),
                symbol: "sparkles",
                keywords: ["clean", "wipe", "lock keyboard", "clean mode"],
                state: { [weak self] in self?.controller.isLocked == true ? .on : .off }
            ) { [weak self] _ in
                guard let self else { return }
                if self.controller.isLocked {
                    self.controller.unlock()
                } else {
                    try self.controller.lock()
                }
            },
            Command(
                id: "cleanMode.lockKeyboard",
                title: String(localized: "Lock Keyboard for Cleaning"),
                symbol: "keyboard",
                keywords: ["clean", "wipe", "lock"]
            ) { [weak self] _ in
                try self?.controller.lock(.keyboard)
            },
            Command(
                id: "cleanMode.lockEverything",
                title: String(localized: "Lock Keyboard and Trackpad for Cleaning"),
                subtitle: String(localized: "Unlocks when the countdown ends"),
                symbol: "lock",
                keywords: ["clean", "wipe", "lock", "trackpad", "mouse"]
            ) { [weak self] _ in
                try self?.controller.lock(.everything)
            },
            Command(
                id: "cleanMode.stop",
                title: String(localized: "Unlock Keyboard"),
                symbol: "lock.open",
                keywords: ["clean", "unlock"],
                isEnabled: { [weak self] in self?.controller.isLocked == true }
            ) { [weak self] _ in
                self?.controller.unlock()
            },
        ]
    }

    public var quickToggles: [QuickToggle] {
        commands.filter { $0.id == "cleanMode.start" }.map {
            var command = $0
            command.title = String(localized: "Clean Mode")
            return QuickToggle(command)
        }
    }

    public var settingsPane: SettingsPane? {
        SettingsPane { [controller, context] in
            CleanModeSettingsView(
                controller: controller,
                inputStatus: { context.input.status == .running ? .running : .unavailable },
                requestAccess: {
                    let permissions = context.permissions
                    Task { await permissions.request(.accessibility) }
                }
            )
        }
    }
}
