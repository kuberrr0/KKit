import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Switch between windows, not just apps, with live previews; takes over ⌘Tab.
/// DESIGN.md §3.19.
@MainActor
public final class WindowSwitcherFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "windowSwitcher",
        name: String(localized: "Window Switcher"),
        symbol: "rectangle.on.rectangle",
        summary: String(localized: "⌘Tab through every window, with live previews, instead of only apps."),
        category: .windows,
        requiredPermissions: [.accessibility],
        optionalPermissions: [.screenRecording],
        enabledByDefault: true
    )

    private let context: FeatureContext
    let controller: WindowSwitcherController

    public convenience init(context: FeatureContext) {
        self.init(context: context, apps: WorkspaceApps())
    }

    init(context: FeatureContext, apps: any SwitcherAppControlling) {
        self.context = context
        self.controller = WindowSwitcherController(
            input: context.input,
            windowService: context.windows,
            capture: context.screenCapture,
            overlays: context.overlays,
            settings: context.settings,
            apps: apps
        )
    }

    public func start() async throws {
        controller.start()
    }

    public func stop() async {
        controller.stop()
    }

    // MARK: Contributions

    public var commands: [Command] {
        [
            Command(
                id: "windowSwitcher.show",
                title: String(localized: "Switch Windows"),
                subtitle: String(localized: "Stays open until you pick a window"),
                symbol: "rectangle.on.rectangle",
                keywords: ["window", "switch", "alt tab", "cmd tab", "app switcher"]
            ) { [weak self] _ in
                self?.controller.open(sticky: true)
            },
        ]
    }

    public var settingsPane: SettingsPane? {
        SettingsPane { [context] in
            WindowSwitcherSettingsView(
                screenRecordingGranted: context.permissions.status(of: .screenRecording) == .granted,
                requestScreenRecording: {
                    let permissions = context.permissions
                    Task { await permissions.request(.screenRecording) }
                }
            )
        }
    }
}
