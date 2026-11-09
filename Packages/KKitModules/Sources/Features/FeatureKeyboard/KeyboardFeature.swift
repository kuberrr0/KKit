import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// The Hyper key, app and action bindings, leader sequences and a cheat sheet.
/// DESIGN.md §3.9. Plain command hotkeys stay in Settings › Shortcuts (Carbon hotkeys,
/// no permission); everything here runs on the shared input tap.
@MainActor
public final class KeyboardFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "keyboard",
        name: String(localized: "Keyboard"),
        symbol: "keyboard",
        summary: String(localized: "Caps Lock as a Hyper key, keys that open apps and run things, and leader sequences."),
        category: .input,
        requiredPermissions: [.accessibility],
        enabledByDefault: false
    )

    private let context: FeatureContext
    let controller: KeyboardController

    public init(context: FeatureContext) {
        self.context = context
        self.controller = KeyboardController(context: context)
    }

    public func start() async throws {
        controller.start()
    }

    public func stop() async {
        await controller.stop()
    }

    public var commands: [Command] {
        [
            Command(
                id: "keyboard.showCheatSheet",
                title: String(localized: "Show Hyper Key Cheat Sheet"),
                symbol: "keyboard",
                keywords: ["hyper", "bindings", "keys", "help"]
            ) { [weak self] _ in
                self?.controller.toggleCheatSheet()
            },
            Command(
                id: "keyboard.startLeader",
                title: String(localized: "Start Leader Sequence"),
                subtitle: String(localized: "Then type a sequence's keys"),
                symbol: "text.cursor",
                keywords: ["leader", "sequence"],
                isEnabled: { [weak self] in
                    self.map { !$0.context.settings[KeyboardSettings.sequences].isEmpty } ?? false
                }
            ) { [weak self] _ in
                self?.controller.beginLeader()
            },
            Command(
                id: "keyboard.toggleHyper",
                title: String(localized: "Toggle Hyper Key"),
                subtitle: String(localized: "Caps Lock as ⌃⌥⇧⌘"),
                symbol: "capslock",
                keywords: ["caps lock", "hyper"],
                state: { [weak self] in
                    self?.context.settings[KeyboardSettings.hyperEnabled] == true ? .on : .off
                }
            ) { [weak self] _ in
                guard let self else { return }
                self.context.settings[KeyboardSettings.hyperEnabled].toggle()
            },
        ]
    }

    public var settingsPane: SettingsPane? {
        SettingsPane { [controller] in
            KeyboardSettingsView(controller: controller)
        }
    }
}
