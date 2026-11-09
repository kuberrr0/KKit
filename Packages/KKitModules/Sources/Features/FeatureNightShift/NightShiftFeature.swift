import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Warms the screen with gamma tables, from a gentle tint to well past macOS's own
/// limit, with a schedule and extra dim. DESIGN.md §3.10.
@MainActor
public final class NightShiftFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "nightShift",
        name: String(localized: "Night Shift"),
        symbol: "moon.stars",
        summary: String(localized: "Warm the screen up to 200%, on a schedule, with extra dim."),
        category: .display,
        optionalPermissions: [.location],
        enabledByDefault: true
    )

    private let context: FeatureContext
    let controller: NightShiftController
    private var tasks: [Task<Void, Never>] = []
    private var tickTask: Task<Void, Never>?

    public init(context: FeatureContext) {
        self.context = context
        self.controller = NightShiftController(display: context.display, settings: context.settings)
    }

    public func start() async throws {
        controller.frontmostAppChanged(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        controller.update(animated: false)

        let frontmost = context.events.stream { event in
            if case .frontmostAppChanged = event { return true }
            return false
        }
        tasks.append(Task { [weak self] in
            for await event in frontmost {
                if case .frontmostAppChanged(let bundleID) = event {
                    self?.controller.frontmostAppChanged(bundleID)
                }
            }
        })
        // A new display needs its tint; wake resets are handled by DisplayService.
        let displays = context.events.stream { $0 == .displaysChanged }
        tasks.append(Task { [weak self] in
            for await _ in displays {
                self?.controller.apply(force: true)
            }
        })
        watch(context.settings.changes(of: NightShiftSettings.intensity))
        watch(context.settings.changes(of: NightShiftSettings.mode))
        watch(context.settings.changes(of: NightShiftSettings.extraDim))
        watch(context.settings.changes(of: NightShiftSettings.disabledDisplays))
        watchSchedule(context.settings.changes(of: NightShiftSettings.schedule))
        watchSchedule(context.settings.changes(of: NightShiftSettings.customStart))
        watchSchedule(context.settings.changes(of: NightShiftSettings.customEnd))
        watchSchedule(context.settings.changes(of: NightShiftSettings.coordinate))
        watchSchedule(context.settings.changes(of: NightShiftSettings.disabledApps))
        scheduleTick()
    }

    public func stop() async {
        tasks.forEach { $0.cancel() }
        tasks = []
        tickTask?.cancel()
        tickTask = nil
        controller.shutdown()
    }

    // MARK: Contributions

    public var commands: [Command] {
        [
            Command(
                id: "nightShift.toggle",
                title: String(localized: "Toggle Night Shift"),
                symbol: "moon.stars",
                keywords: ["night", "warm", "blue light", "flux"],
                defaultShortcut: Shortcut(keyCode: Shortcut.Key.n, modifiers: [.control, .option]),
                state: { [weak self] in self?.state ?? .off }
            ) { [weak self] _ in
                self?.controller.toggle()
            },
            Command(
                id: "nightShift.setIntensity",
                title: String(localized: "Set Night Shift Intensity…"),
                subtitle: String(localized: "0–200%"),
                symbol: "slider.horizontal.3",
                keywords: ["night", "warm"],
                parameter: .percent(default: 70)
            ) { [weak self] invocation in
                self?.controller.setIntensity((invocation.percent ?? 70) / 100)
            },
            Command(
                id: "nightShift.stronger",
                title: String(localized: "Night Shift Stronger"),
                symbol: "plus.circle",
                keywords: ["night", "warmer"]
            ) { [weak self] _ in
                self?.controller.adjustIntensity(by: 0.1)
            },
            Command(
                id: "nightShift.weaker",
                title: String(localized: "Night Shift Weaker"),
                symbol: "minus.circle",
                keywords: ["night", "cooler"]
            ) { [weak self] _ in
                self?.controller.adjustIntensity(by: -0.1)
            },
            Command(
                id: "nightShift.darkroom",
                title: String(localized: "Toggle Darkroom Mode"),
                subtitle: String(localized: "Red only, for night use"),
                symbol: "circle.lefthalf.filled",
                keywords: ["night", "red"]
            ) { [weak self] _ in
                self?.toggleDarkroom()
            },
            Command(
                id: "nightShift.pause",
                title: String(localized: "Pause Night Shift for an Hour"),
                symbol: "pause.circle",
                keywords: ["night"],
                state: { [weak self] in self?.controller.isPaused == true ? .on : .off }
            ) { [weak self] _ in
                guard let controller = self?.controller else { return }
                if controller.isPaused {
                    controller.resume()
                } else {
                    controller.pause(for: 3600)
                }
            },
        ]
    }

    public var quickToggles: [QuickToggle] {
        commands.filter { $0.id == "nightShift.toggle" }.map {
            var command = $0
            command.title = String(localized: "Night")
            return QuickToggle(command)
        }
    }

    public var menuBarSections: [MenuBarSection] {
        [MenuBarSection(id: "intensity", order: 200) { [controller] in
            NightShiftMenuSection(controller: controller)
        }]
    }

    public var settingsPane: SettingsPane? {
        SettingsPane { [controller, context] in
            NightShiftSettingsView(controller: controller, display: context.display, location: context.location)
        }
    }

    // MARK: Private

    private var state: CommandState {
        controller.isActive ? .value(KKFormat.percent(context.settings[NightShiftSettings.intensity])) : .off
    }

    private func toggleDarkroom() {
        let settings = context.settings
        if settings[NightShiftSettings.mode] == .darkroom, controller.isActive {
            settings[NightShiftSettings.mode] = .warm
        } else {
            settings[NightShiftSettings.mode] = .darkroom
            if !controller.isActive {
                controller.setOn(true)
            }
        }
    }

    private func watch<Value: Sendable>(_ stream: AsyncStream<Value>) {
        tasks.append(Task { [weak self] in
            for await _ in stream {
                self?.controller.apply(force: true)
            }
        })
    }

    private func watchSchedule<Value: Sendable>(_ stream: AsyncStream<Value>) {
        tasks.append(Task { [weak self] in
            for await _ in stream {
                self?.controller.tick()
                self?.scheduleTick()
            }
        })
    }

    /// Wakes up at the next schedule change (or within a minute) to re-check.
    private func scheduleTick() {
        tickTask?.cancel()
        let delay = controller.nextTickDelay()
        tickTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.controller.tick()
            self.scheduleTick()
        }
    }
}
