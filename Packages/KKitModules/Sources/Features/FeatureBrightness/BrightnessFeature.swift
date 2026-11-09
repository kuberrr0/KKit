import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// The built-in display's brightness: the brightness keys with an Island HUD, a menu bar
/// slider and commands.
@MainActor
public final class BrightnessFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "brightness",
        name: String(localized: "Brightness"),
        symbol: "sun.max",
        summary: String(localized: "Brightness keys with the Island HUD, finer steps and a menu slider."),
        category: .display,
        optionalPermissions: [.accessibility],
        enabledByDefault: true
    )

    private let context: FeatureContext
    let controller: BrightnessController
    private var tasks: [Task<Void, Never>] = []
    private var keyToken: InputHandlerToken?

    public init(context: FeatureContext) {
        self.context = context
        self.controller = BrightnessController(display: context.display, overlays: context.overlays, settings: context.settings)
    }

    public func start() async throws {
        let island = context.island
        controller.onHUD = { hud in island.showHUD(hud) }
        controller.refresh()
        let takeOver = context.settings.changes(of: BrightnessSettings.takeOverKeys)
        tasks.append(Task { [weak self] in
            for await _ in takeOver {
                self?.updateKeyHandler()
            }
        })
        updateKeyHandler()
    }

    public func stop() async {
        tasks.forEach { $0.cancel() }
        tasks = []
        context.input.removeAll()
        keyToken = nil
        controller.onHUD = nil
    }

    public var commands: [Command] {
        [
            Command(
                id: "brightness.up",
                title: String(localized: "Brightness Up"),
                symbol: "sun.max",
                keywords: ["brighter", "screen", "display"],
                isEnabled: { [weak self] in self?.controller.isAvailable ?? false }
            ) { [weak self] _ in
                try self?.controller.stepBrightness(up: true)
            },
            Command(
                id: "brightness.down",
                title: String(localized: "Brightness Down"),
                symbol: "sun.min",
                keywords: ["dimmer", "darker", "screen", "display"],
                isEnabled: { [weak self] in self?.controller.isAvailable ?? false }
            ) { [weak self] _ in
                try self?.controller.stepBrightness(up: false)
            },
            Command(
                id: "brightness.set",
                title: String(localized: "Set Brightness…"),
                subtitle: String(localized: "0–100%"),
                symbol: "sun.max",
                keywords: ["bright", "screen", "display", "dim"],
                parameter: .percent(default: 50),
                isEnabled: { [weak self] in self?.controller.isAvailable ?? false }
            ) { [weak self] invocation in
                try self?.controller.set((invocation.percent ?? 50) / 100)
            },
        ]
    }

    public var menuBarSections: [MenuBarSection] {
        guard controller.isAvailable else { return [] }
        return [MenuBarSection(id: "brightness", order: 110) { [controller] in
            BrightnessMenuSection(controller: controller)
        }]
    }

    public var settingsPane: SettingsPane? {
        SettingsPane { [controller, context] in
            BrightnessSettingsView(
                controller: controller,
                inputTapRunning: { context.input.status == .running },
                requestAccess: {
                    let permissions = context.permissions
                    Task { await permissions.request(.accessibility) }
                }
            )
        }
    }

    // MARK: Private

    private func updateKeyHandler() {
        let enabled = context.settings[BrightnessSettings.takeOverKeys]
        if enabled, keyToken == nil {
            keyToken = context.input.add(priority: .normal, interests: [.keyDown, .keyUp, .systemDefined]) { [weak self] event in
                guard let self else { return .pass }
                let action: BrightnessKeyAction
                if let media = event.mediaKey {
                    action = BrightnessKeyAction.action(for: media, modifiers: event.modifiers)
                } else if event.type == .keyDown || event.type == .keyUp {
                    action = BrightnessKeyAction.action(forKeyCode: event.keyCode, isDown: event.type == .keyDown, modifiers: event.modifiers)
                } else {
                    return .pass
                }
                return self.controller.handle(action) ? .consume : .pass
            }
        } else if !enabled, let token = keyToken {
            context.input.remove(token)
            keyToken = nil
        }
    }
}
