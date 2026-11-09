import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Output volume, mute, device switching with priorities, global mic mute, and an
/// Island HUD. DESIGN.md §3.1. Per-app volume and the volume-key takeover arrive in M4.
@MainActor
public final class VolumeFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "volume",
        name: String(localized: "Volume & Audio"),
        symbol: "speaker.wave.2",
        summary: String(localized: "Finer volume, device switching with priorities, and one-key mic mute."),
        category: .audio,
        enabledByDefault: true
    )

    private let context: FeatureContext
    let controller: VolumeController
    private var tasks: [Task<Void, Never>] = []

    public init(context: FeatureContext) {
        self.context = context
        self.controller = VolumeController(audio: context.audio, settings: context.settings)
    }

    public func start() async throws {
        let island = context.island
        controller.onHUD = { hud in island.showHUD(hud) }

        let updates = context.audio.updates()
        tasks.append(Task { [weak self] in
            for await state in updates {
                self?.controller.receive(state)
            }
        })
        let scrollSetting = context.settings.changes(of: VolumeSettings.scrollOnIsland)
        tasks.append(Task { [weak self] in
            for await _ in scrollSetting {
                self?.updateScrollHandler()
            }
        })
        let limit = context.settings.changes(of: VolumeSettings.volumeLimit)
        tasks.append(Task { [weak self] in
            for await _ in limit {
                guard let self else { return }
                self.controller.receive(self.context.audio.state)
            }
        })
        updateScrollHandler()
    }

    public func stop() async {
        tasks.forEach { $0.cancel() }
        tasks = []
        controller.onHUD = nil
        context.island.setScrollHandler(nil)
    }

    // MARK: Contributions

    public var commands: [Command] {
        [
            Command(
                id: "volume.up",
                title: String(localized: "Volume Up"),
                symbol: "speaker.wave.3",
                keywords: ["louder", "vol"]
            ) { [weak self] _ in
                self?.controller.stepVolume(up: true)
            },
            Command(
                id: "volume.down",
                title: String(localized: "Volume Down"),
                symbol: "speaker.wave.1",
                keywords: ["quieter", "vol"]
            ) { [weak self] _ in
                self?.controller.stepVolume(up: false)
            },
            Command(
                id: "volume.set",
                title: String(localized: "Set Volume…"),
                subtitle: String(localized: "0–100%"),
                symbol: "speaker.wave.2",
                keywords: ["vol", "sound"],
                parameter: .percent(default: 50)
            ) { [weak self] invocation in
                self?.controller.setVolume((invocation.percent ?? 50) / 100)
            },
            Command(
                id: "volume.toggleMute",
                title: String(localized: "Toggle Mute"),
                symbol: "speaker.slash",
                keywords: ["mute", "sound", "silence"],
                state: { [weak self] in self?.controller.state.outputMuted == true ? .on : .off }
            ) { [weak self] _ in
                self?.controller.toggleMute()
            },
            Command(
                id: "volume.toggleMicMute",
                title: String(localized: "Toggle Mic Mute"),
                subtitle: String(localized: "Mutes the microphone in every app"),
                symbol: "mic.slash",
                keywords: ["mute mic", "microphone", "zoom", "meet"],
                defaultShortcut: Shortcut(keyCode: Shortcut.Key.m, modifiers: [.control, .option]),
                isEnabled: { [weak self] in self?.controller.state.defaultInput != nil },
                state: { [weak self] in self?.controller.isMicMuted == true ? .value(String(localized: "Muted")) : .off }
            ) { [weak self] _ in
                self?.controller.toggleMicMute()
            },
            Command(
                id: "volume.setOutput",
                title: String(localized: "Switch Output To…"),
                subtitle: String(localized: "A device name, like AirPods"),
                symbol: "hifispeaker",
                keywords: ["output", "speakers", "headphones", "device"],
                parameter: .text(placeholder: "AirPods")
            ) { [weak self] invocation in
                try self?.switchDevice(named: invocation.text, scope: .output)
            },
            Command(
                id: "volume.setInput",
                title: String(localized: "Switch Input To…"),
                subtitle: String(localized: "A microphone name"),
                symbol: "mic",
                keywords: ["input", "microphone", "device"],
                parameter: .text(placeholder: "MacBook Pro Microphone")
            ) { [weak self] invocation in
                try self?.switchDevice(named: invocation.text, scope: .input)
            },
            Command(
                id: "volume.nextOutput",
                title: String(localized: "Next Output Device"),
                symbol: "arrow.triangle.2.circlepath",
                keywords: ["output", "cycle", "device"]
            ) { [weak self] _ in
                self?.controller.nextOutput()
            },
        ]
    }

    public var quickToggles: [QuickToggle] {
        commands.filter { $0.id == "volume.toggleMicMute" }.map {
            var command = $0
            command.title = String(localized: "Mic Mute")
            return QuickToggle(command)
        }
    }

    public var menuBarSections: [MenuBarSection] {
        [MenuBarSection(id: "volume", order: 100) { [controller] in
            VolumeMenuSection(controller: controller)
        }]
    }

    public var settingsPane: SettingsPane? {
        SettingsPane { [controller] in
            VolumeSettingsView(controller: controller)
        }
    }

    // MARK: Private

    private func updateScrollHandler() {
        if context.settings[VolumeSettings.scrollOnIsland] {
            context.island.setScrollHandler { [weak self] event in
                self?.controller.handleScroll(event)
            }
        } else {
            context.island.setScrollHandler(nil)
        }
    }

    private func switchDevice(named name: String?, scope: AudioScope) throws {
        let devices = scope == .output ? controller.state.outputDevices : controller.state.inputDevices
        guard let name, let device = AudioDevicePicker.match(name, in: devices) else {
            throw VolumeError.noDevice(name ?? "")
        }
        controller.setDefault(device, for: scope)
    }
}

enum VolumeError: LocalizedError {
    case noDevice(String)

    var errorDescription: String? {
        switch self {
        case .noDevice(let name):
            String(localized: "No audio device matches “\(name)”.")
        }
    }
}
