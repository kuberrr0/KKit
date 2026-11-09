import AppKit
import Foundation
import KKitCore
import KKitServicesAPI
import SwiftUI

/// Picks colours from the screen with the system loupe, copies them in the chosen
/// format and keeps the recent ones. The commands, the Floating Bar provider, the
/// Island page and the settings pane all go through this.
@MainActor
@Observable
final class ColorPickerController {
    let context: FeatureContext
    var settings: FeatureSettings { context.settings }

    /// Newest first.
    private(set) var history: [RGBAColor] = []
    /// The loupe is on screen.
    private(set) var isPicking = false

    /// The colour shown big on the Island page: the last one picked or copied.
    var current: RGBAColor? { history.first }

    /// Shows the loupe and returns the colour clicked (`nil` if ⎋). Replaced in tests.
    @ObservationIgnored var sample: @MainActor () async -> RGBAColor? = {
        await ColorPickerController.sampleScreen()
    }

    @ObservationIgnored private var pickedHandle: (any IslandHandle)?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    static let pickedActivity = "picked"
    /// How long the picked colour stays in the compact Island.
    static let pickedSeconds = 3.0

    init(context: FeatureContext) {
        self.context = context
        history = context.settings[ColorPickerSettings.history].compactMap(RGBAColor.init(hex:))
    }

    func tearDown() {
        dismissTask?.cancel()
        dismissTask = nil
        pickedHandle?.dismiss()
        pickedHandle = nil
    }

    // MARK: Picking

    /// The loupe; the colour clicked is copied in the chosen format.
    func pick() async {
        guard !isPicking else { return }
        isPicking = true
        let color = await sample()
        isPicking = false
        guard let color else { return }
        copy(color)
    }

    /// `color` in `format` (the chosen one if `nil`).
    func string(_ color: RGBAColor, format: ColorFormat? = nil) -> String {
        ColorFormatter.string(
            color,
            as: format ?? settings[ColorPickerSettings.format],
            lowercaseHex: settings[ColorPickerSettings.lowercaseHex]
        )
    }

    /// Copies `color` and moves it to the front of the history. `announce` shows it in
    /// the compact Island (not when the click came from the Island page itself).
    @discardableResult
    func copy(_ color: RGBAColor, format: ColorFormat? = nil, announce: Bool = true) -> String {
        let text = string(color, format: format)
        context.pasteboard.copy(text)
        remember(color)
        if announce, settings[ColorPickerSettings.showInIsland] {
            presentPicked(color)
        }
        return text
    }

    func remember(_ color: RGBAColor) {
        var colors = history.filter { $0.hex != color.hex }
        colors.insert(color, at: 0)
        history = Array(colors.prefix(ColorPickerSettings.maxHistory))
        save()
    }

    func remove(_ color: RGBAColor) {
        history.removeAll { $0.hex == color.hex }
        save()
    }

    func clearHistory() {
        history = []
        save()
    }

    private func save() {
        settings[ColorPickerSettings.history] = history.map(\.hex)
    }

    // MARK: Island

    /// The swatch and its HEX in the compact Island for a few seconds (longer while
    /// the Island is expanded on it).
    private func presentPicked(_ color: RGBAColor) {
        let activity = IslandActivity(
            id: Self.pickedActivity,
            title: String(localized: "Colour"),
            symbol: "eyedropper",
            priority: .high,
            compactLeading: AnyView(PickedSwatch(color: color)),
            compactTrailing: AnyView(
                Text(string(color, format: .hex))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            ),
            expanded: AnyView(ColorIslandPage(controller: self))
        )
        if let pickedHandle, pickedHandle.isActive {
            pickedHandle.update(activity)
        } else {
            pickedHandle = context.island.present(activity)
        }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.pickedSeconds))
            while !Task.isCancelled, self?.pickedHandle?.isExpanded == true {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled, let self else { return }
            self.pickedHandle?.dismiss()
            self.pickedHandle = nil
        }
    }

    // MARK: Screen

    /// `NSColorSampler`: the system loupe. It doesn't need Screen Recording.
    static func sampleScreen() async -> RGBAColor? {
        let sampler = NSColorSampler()
        let color: RGBAColor? = await withCheckedContinuation { continuation in
            sampler.show { picked in
                continuation.resume(returning: picked.flatMap(ColorPickerController.rgba(from:)))
            }
        }
        withExtendedLifetime(sampler) {}
        return color
    }

    nonisolated static func rgba(from color: NSColor) -> RGBAColor? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return RGBAColor(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent),
            alpha: Double(srgb.alphaComponent)
        )
    }
}
