import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Snapping with hotkeys and by dragging, modifier + mouse move and resize, moving
/// between displays, and saved layouts. DESIGN.md §3.12.
@MainActor
public final class WindowsFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "windows",
        name: String(localized: "Window Management"),
        symbol: "rectangle.split.2x1",
        summary: String(localized: "Snap windows with keys or by dragging, move and resize with a modifier, and save layouts."),
        category: .windows,
        requiredPermissions: [.accessibility],
        enabledByDefault: false
    )

    private let context: FeatureContext
    let controller: WindowsController
    let drag: WindowDragController
    private lazy var layoutsProvider = LayoutsProvider(controller: controller)

    public init(context: FeatureContext) {
        self.context = context
        let controller = WindowsController(
            windows: context.windows,
            overlays: context.overlays,
            settings: context.settings,
            storage: context.storage,
            island: context.island
        )
        self.controller = controller
        self.drag = WindowDragController(
            input: context.input,
            windows: context.windows,
            overlays: context.overlays,
            settings: context.settings,
            controller: controller
        )
    }

    public func start() async throws {
        controller.load()
        drag.start()
    }

    public func stop() async {
        drag.stop()
    }

    // MARK: Contributions

    public var commands: [Command] {
        var commands = SnapAction.allCases.map { action in
            Command(
                id: CommandID("windows.\(action.rawValue)"),
                title: action.title,
                subtitle: action.cycles ? String(localized: "Press again for ⅓ and ⅔") : nil,
                symbol: action.symbol,
                keywords: ["window", "snap", action.choiceName],
                defaultShortcut: action.defaultShortcut
            ) { [weak self] _ in
                try await self?.controller.snapFocused(action)
            }
        }
        commands += [
            Command(
                id: "windows.snap",
                title: String(localized: "Snap Window To…"),
                subtitle: String(localized: "left, right, top left, max…"),
                symbol: "rectangle.split.2x1",
                keywords: ["win", "window", "snap", "tile"],
                parameter: .choice(SnapAction.allCases.map(\.choiceName))
            ) { [weak self] invocation in
                guard let name = invocation.text, let action = SnapAction.named(name) else { return }
                try await self?.controller.snapFocused(action)
            },
            Command(
                id: "windows.restore",
                title: String(localized: "Restore Window"),
                subtitle: String(localized: "Back to its size before KKit moved it"),
                symbol: "arrow.uturn.backward",
                keywords: ["window", "undo", "unsnap"],
                defaultShortcut: Shortcut(keyCode: Shortcut.Key.delete, modifiers: [.control, .option])
            ) { [weak self] _ in
                try await self?.controller.restoreFocused()
            },
            Command(
                id: "windows.nextDisplay",
                title: String(localized: "Move Window to Next Display"),
                symbol: "rectangle.portrait.and.arrow.right",
                keywords: ["window", "screen", "monitor"],
                defaultShortcut: Shortcut(keyCode: Shortcut.Key.rightArrow, modifiers: [.control, .option, .command]),
                isEnabled: { [weak self] in (self?.controller.screenFrames.count ?? 0) > 1 }
            ) { [weak self] _ in
                try await self?.controller.moveFocusedToDisplay(next: true)
            },
            Command(
                id: "windows.previousDisplay",
                title: String(localized: "Move Window to Previous Display"),
                symbol: "rectangle.portrait.and.arrow.forward",
                keywords: ["window", "screen", "monitor"],
                defaultShortcut: Shortcut(keyCode: Shortcut.Key.leftArrow, modifiers: [.control, .option, .command]),
                isEnabled: { [weak self] in (self?.controller.screenFrames.count ?? 0) > 1 }
            ) { [weak self] _ in
                try await self?.controller.moveFocusedToDisplay(next: false)
            },
            Command(
                id: "windows.grow",
                title: String(localized: "Make Window Larger"),
                symbol: "arrow.up.left.and.arrow.down.right",
                keywords: ["window", "grow", "bigger"],
                defaultShortcut: Shortcut(keyCode: Shortcut.Key.equal, modifiers: [.control, .option])
            ) { [weak self] _ in
                try await self?.controller.resizeFocused(grow: true)
            },
            Command(
                id: "windows.shrink",
                title: String(localized: "Make Window Smaller"),
                symbol: "arrow.down.right.and.arrow.up.left",
                keywords: ["window", "shrink", "smaller"],
                defaultShortcut: Shortcut(keyCode: Shortcut.Key.minus, modifiers: [.control, .option])
            ) { [weak self] _ in
                try await self?.controller.resizeFocused(grow: false)
            },
            Command(
                id: "windows.saveLayout",
                title: String(localized: "Save Window Layout…"),
                subtitle: String(localized: "Remembers where every window is"),
                symbol: "rectangle.3.group",
                keywords: ["layout", "arrangement", "workspace"],
                parameter: .text(placeholder: String(localized: "Coding"))
            ) { [weak self] invocation in
                try await self?.controller.saveLayout(named: invocation.text ?? "")
            },
            Command(
                id: "windows.restoreLayout",
                title: String(localized: "Restore Window Layout…"),
                symbol: "rectangle.3.group.fill",
                keywords: ["layout", "arrangement", "workspace"],
                parameter: .text(placeholder: String(localized: "Coding")),
                isEnabled: { [weak self] in !(self?.controller.layouts.isEmpty ?? true) }
            ) { [weak self] invocation in
                try await self?.controller.restoreLayout(named: invocation.text ?? "")
            },
        ]
        return commands
    }

    public var searchProviders: [any SearchProvider] {
        [layoutsProvider]
    }

    public var settingsPane: SettingsPane? {
        SettingsPane { [controller, context] in
            WindowsSettingsView(
                controller: controller,
                systemTilingOn: context.windows.isSystemEdgeTilingEnabled,
                openDesktopSettings: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
        }
    }
}
