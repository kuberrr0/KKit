import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Hides menu bar icons behind a ‹ chevron, keeps some out of the way for good, and
/// shows hidden and behind-the-notch icons in a drop-down bar. DESIGN.md §3.13.
///
/// The fragile part (dividers, reading and pressing other apps' icons) is
/// `MenuBarItemsService`; turning this feature off takes KKit's dividers out of the
/// menu bar and every icon comes back.
@MainActor
public final class MenuBarManagerFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "menuBarManager",
        name: String(localized: "Menu Bar Manager"),
        symbol: "menubar.rectangle",
        summary: String(localized: "Hides menu bar icons behind a chevron, with a drop-down bar for the ones behind the notch."),
        category: .system,
        optionalPermissions: [.accessibility, .screenRecording],
        enabledByDefault: false
    )

    private let context: FeatureContext
    let controller: MenuBarManagerController

    public init(context: FeatureContext) {
        self.context = context
        self.controller = MenuBarManagerController(
            service: context.menuBarItems,
            input: context.input,
            overlays: context.overlays,
            screenCapture: context.screenCapture,
            permissions: context.permissions,
            settings: context.settings
        )
    }

    public func start() async throws {
        controller.start()
        context.services.publish((any MenuBarIconsServicing).self, controller)
    }

    public func stop() async {
        controller.stop()
    }

    // MARK: Contributions

    public var commands: [Command] {
        [
            Command(
                id: "menuBarManager.toggle",
                title: String(localized: "Show Hidden Menu Bar Icons"),
                subtitle: String(localized: "The icons left of the ‹ chevron"),
                symbol: "menubar.arrow.down.rectangle",
                keywords: ["menu bar", "icons", "hidden", "status items", "chevron", "extras"],
                state: { [weak self] in
                    guard let self else { return .off }
                    return self.controller.isShowingHidden ? .on : .off
                }
            ) { [weak self] _ in
                self?.controller.toggle()
            },
            Command(
                id: "menuBarManager.showAll",
                title: String(localized: "Show All Menu Bar Icons"),
                subtitle: String(localized: "Including Always Hidden ones, to ⌘-drag them"),
                symbol: "menubar.rectangle",
                keywords: ["menu bar", "icons", "always hidden", "rearrange"]
            ) { [weak self] _ in
                self?.controller.showAll()
            },
            Command(
                id: "menuBarManager.dropDown",
                title: String(localized: "Open Menu Bar Drop-Down"),
                subtitle: String(localized: "Hidden icons and the ones behind the notch"),
                symbol: "rectangle.topthird.inset.filled",
                keywords: ["menu bar", "notch", "icons", "hidden"]
            ) { [weak self] _ in
                guard let self else { return }
                if self.controller.isDropDownVisible {
                    self.controller.hideDropDown()
                } else {
                    await self.controller.showDropDown()
                }
            },
            Command(
                id: "menuBarManager.hide",
                title: String(localized: "Hide Menu Bar Icons"),
                symbol: "menubar.arrow.up.rectangle",
                keywords: ["menu bar", "icons", "hide", "tidy"],
                isEnabled: { [weak self] in
                    guard let self else { return false }
                    return self.controller.isShowingHidden || self.controller.isDropDownVisible
                }
            ) { [weak self] _ in
                self?.controller.hideAll()
            },
        ]
    }

    public var quickToggles: [QuickToggle] {
        commands.filter { $0.id == "menuBarManager.toggle" }.map {
            var command = $0
            command.title = String(localized: "Hidden Icons")
            return QuickToggle(command)
        }
    }

    public var settingsPane: SettingsPane? {
        SettingsPane { [controller, context] in
            MenuBarManagerSettingsView(
                controller: controller,
                commandKeyAvailable: { context.permissions.status(of: .accessibility).isGranted }
            )
        }
    }
}
