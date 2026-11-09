import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import Observation

enum BrightnessSettings {
    /// KKit handles the brightness keys and shows the Island HUD instead of macOS's.
    static let takeOverKeys = SettingKey("takeOverKeys", default: true)
    /// One step as a fraction: 1/16, like macOS.
    static let step = SettingKey("step", default: 0.0625)
    static let showHUD = SettingKey("showHUD", default: true)
}

enum BrightnessError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        String(localized: "KKit can't change this display's brightness.")
    }
}

/// What a brightness key does.
enum BrightnessKeyAction: Equatable {
    case step(up: Bool, fine: Bool)
    case swallow
    case pass

    /// Apple keyboards send the brightness keys as key presses (144, 145); older ones
    /// and some third-party keyboards as media keys.
    static let upKeyCode = 144
    static let downKeyCode = 145

    static func action(forKeyCode keyCode: Int, isDown: Bool, modifiers: Shortcut.Modifiers) -> BrightnessKeyAction {
        guard keyCode == upKeyCode || keyCode == downKeyCode else { return .pass }
        guard isDown else { return .swallow }
        return .step(up: keyCode == upKeyCode, fine: isFine(modifiers))
    }

    static func action(for media: MediaKeyEvent, modifiers: Shortcut.Modifiers) -> BrightnessKeyAction {
        guard media.key == .brightnessUp || media.key == .brightnessDown else { return .pass }
        guard media.isDown else { return .swallow }
        return .step(up: media.key == .brightnessUp, fine: isFine(modifiers))
    }

    /// ⇧⌥ gives quarter steps, like macOS.
    static func isFine(_ modifiers: Shortcut.Modifiers) -> Bool {
        modifiers.contains(.shift) && modifiers.contains(.option)
    }
}

/// Built-in display brightness with KKit's step size and the Island HUD.
@MainActor
@Observable
final class BrightnessController {
    /// The brightness of the display KKit last read or set, 0…1.
    private(set) var level: Double?
    private(set) var displayName: String?

    private let display: any DisplayService
    private let overlays: any OverlayService
    private let settings: FeatureSettings
    @ObservationIgnored var onHUD: (@MainActor (IslandHUD) -> Void)?

    init(display: any DisplayService, overlays: any OverlayService, settings: FeatureSettings) {
        self.display = display
        self.overlays = overlays
        self.settings = settings
    }

    var step: Double { min(max(settings[BrightnessSettings.step], 0.01), 0.25) }

    /// The display under the pointer if KKit can control it, else the built-in one.
    var target: DisplayInfo? {
        let displays = display.displays
        let mouse = NSEvent.mouseLocation
        let underCursor = overlays.screens.first { $0.frame.contains(mouse) }.flatMap { screen in
            displays.first { $0.id == screen.id }
        }
        let candidates = [underCursor, display.builtInDisplay].compactMap { $0 } + displays
        return candidates.first { display.brightness(of: $0.id) != nil }
    }

    var isAvailable: Bool { target != nil }

    func refresh() {
        guard let target else {
            level = nil
            displayName = nil
            return
        }
        level = display.brightness(of: target.id)
        displayName = target.name
    }

    func set(_ value: Double, showHUD: Bool = true) throws {
        guard let target else { throw BrightnessError.unavailable }
        let clamped = min(max(value, 0), 1)
        display.setBrightness(clamped, for: target.id)
        level = clamped
        displayName = target.name
        if showHUD {
            show(level: clamped)
        }
    }

    func stepBrightness(up: Bool, fine: Bool = false, fromKey: Bool = false) throws {
        guard let target, let current = display.brightness(of: target.id) else { throw BrightnessError.unavailable }
        let size = fine ? step / 4 : step
        let index = current / size
        let next = up ? (index + 1e-6).rounded(.down) + 1 : (index - 1e-6).rounded(.up) - 1
        try set(next * size, showHUD: false)
        if fromKey || settings[BrightnessSettings.showHUD] {
            show(level: level ?? 0, force: fromKey)
        }
    }

    /// A brightness key from the tap. Returns whether KKit used it; keys for displays
    /// KKit can't control go to macOS.
    func handle(_ action: BrightnessKeyAction) -> Bool {
        switch action {
        case .pass:
            return false
        case .swallow:
            return isAvailable
        case .step(let up, let fine):
            do {
                try stepBrightness(up: up, fine: fine, fromKey: true)
                return true
            } catch {
                return false
            }
        }
    }

    private func show(level: Double, force: Bool = false) {
        guard force || settings[BrightnessSettings.showHUD] else { return }
        onHUD?(IslandHUD(
            id: "brightness",
            symbol: level < 0.01 ? "sun.min" : (level < 0.5 ? "sun.min.fill" : "sun.max.fill"),
            title: displayName,
            level: level,
            detail: KKFormat.percent(level)
        ))
    }
}
