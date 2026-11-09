import Foundation
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Colour Picker: the system loupe picks a colour anywhere on screen, copies it as HEX,
/// RGB, HSL, CSS, SwiftUI or NSColor, and keeps the recent ones in the Island, the
/// Floating Bar (`#`) and Settings. DESIGN.md §3.6.
@MainActor
public final class ColorPickerFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "colorPicker",
        name: String(localized: "Colour Picker"),
        symbol: "eyedropper",
        summary: String(localized: "Pick a colour anywhere on screen and copy it as HEX, RGB, HSL, CSS or code."),
        category: .capture,
        enabledByDefault: true
    )

    static let pickCommand: CommandID = "colorPicker.pick"
    static let pageID = "colors"

    private let context: FeatureContext
    let controller: ColorPickerController
    let provider: ColorProvider

    public init(context: FeatureContext) {
        self.context = context
        controller = ColorPickerController(context: context)
        provider = ColorProvider(controller: controller)
    }

    public func start() async throws {}

    public func stop() async {
        controller.tearDown()
    }

    // MARK: Contributions

    public var commands: [Command] {
        let controller = controller
        return [
            Command(
                id: Self.pickCommand,
                title: String(localized: "Pick Colour"),
                subtitle: String(localized: "Copies the colour under the loupe"),
                symbol: "eyedropper",
                keywords: [
                    "color picker", "colour picker", "pick color", "eyedropper", "dropper",
                    "hex", "rgb", "hsl", "sample", "color", "colour",
                ],
                defaultShortcut: Shortcut(keyCode: Shortcut.Key.p, modifiers: [.control, .option])
            ) { _ in
                await controller.pick()
            },
            Command(
                id: "colorPicker.showColors",
                title: String(localized: "Show Recent Colours"),
                subtitle: String(localized: "The Colours page in the Island"),
                symbol: "swatchpalette",
                keywords: ["color history", "colour history", "colors", "colours", "palette", "recent"]
            ) { [weak self] _ in
                self?.showColors()
            },
            Command(
                id: "colorPicker.clearHistory",
                title: String(localized: "Clear Recent Colours"),
                symbol: "trash",
                keywords: ["color", "colour", "history", "clear"],
                isEnabled: { !controller.history.isEmpty }
            ) { _ in
                controller.clearHistory()
            },
        ]
    }

    public var searchProviders: [any SearchProvider] {
        [provider]
    }

    public var islandPages: [IslandPage] {
        guard context.settings[ColorPickerSettings.showIslandPage] else { return [] }
        let controller = controller
        return [
            IslandPage(id: Self.pageID, title: String(localized: "Colours"), symbol: "eyedropper") {
                ColorIslandPage(controller: controller)
            },
        ]
    }

    /// The Colours page, or `#` in the Floating Bar when the page is turned off.
    private func showColors() {
        if context.settings[ColorPickerSettings.showIslandPage] {
            context.island.showPage(Self.pageID)
        } else {
            context.floatingBar.show(query: ColorProvider.prefixText)
        }
    }

    public var settingsPane: SettingsPane? {
        let controller = controller
        return SettingsPane {
            ColorPickerSettingsView(controller: controller)
        }
    }
}
