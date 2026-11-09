import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Keeps the Mac (and optionally the display) awake: indefinitely, for a while, until
/// a time, or automatically by rule. DESIGN.md §3.4.
@MainActor
public final class PowerFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "power",
        name: String(localized: "Power"),
        symbol: "cup.and.saucer",
        summary: String(localized: "Keep your Mac awake for a while, until a time, or by rule."),
        category: .system,
        enabledByDefault: true
    )

    private let context: FeatureContext
    let controller: PowerController
    private var tasks: [Task<Void, Never>] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var activity: (any IslandHandle)?

    public init(context: FeatureContext) {
        self.context = context
        self.controller = PowerController(power: context.power, settings: context.settings)
    }

    public func start() async throws {
        let power = context.power.powerSourceUpdates()
        tasks.append(Task { [weak self] in
            for await _ in power {
                self?.refreshConditions()
            }
        })
        let displays = context.events.stream { $0 == .displaysChanged }
        tasks.append(Task { [weak self] in
            for await _ in displays {
                self?.refreshConditions()
            }
        })
        for key in [PowerSettings.awakeOnPowerAdapter, PowerSettings.awakeWithExternalDisplay, PowerSettings.keepDisplayAwake, PowerSettings.showInIsland] {
            watch(context.settings.changes(of: key))
        }
        watch(context.settings.changes(of: PowerSettings.batteryCutoff))
        watch(context.settings.changes(of: PowerSettings.awakeWhileApps))

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshConditions()
                }
            })
        }
        refreshConditions()
        observeController()
    }

    public func stop() async {
        tasks.forEach { $0.cancel() }
        tasks = []
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers = []
        controller.shutdown()
        activity?.dismiss()
        activity = nil
    }

    // MARK: Contributions

    public var commands: [Command] {
        [
            Command(
                id: "power.toggle",
                title: String(localized: "Toggle Keep Awake"),
                symbol: "cup.and.saucer",
                keywords: ["awake", "caffeinate", "amphetamine", "sleep"],
                state: { [weak self] in self?.state ?? .off }
            ) { [weak self] _ in
                self?.controller.toggle()
            },
            Command(
                id: "power.awakeFor",
                title: String(localized: "Keep Awake For…"),
                symbol: "timer",
                keywords: ["awake", "caffeinate"],
                parameter: .duration(default: .seconds(3600))
            ) { [weak self] invocation in
                let seconds = invocation.duration.map { Double($0.components.seconds) } ?? 3600
                self?.controller.keepAwake(for: seconds)
            },
            Command(
                id: "power.awakeIndefinitely",
                title: String(localized: "Keep Awake Indefinitely"),
                symbol: "infinity",
                keywords: ["awake", "caffeinate"]
            ) { [weak self] _ in
                self?.controller.keepAwake(for: nil)
            },
            Command(
                id: "power.awakeUntil",
                title: String(localized: "Keep Awake Until…"),
                subtitle: String(localized: "A time like 17:30 or 5pm"),
                symbol: "clock",
                keywords: ["awake", "caffeinate"],
                parameter: .text(placeholder: "17:30")
            ) { [weak self] invocation in
                guard let text = invocation.text,
                      let date = ClockTimeParser.nextDate(from: text, after: Date())
                else { throw PowerError.badTime }
                self?.controller.keepAwake(until: date)
            },
            Command(
                id: "power.allowSleep",
                title: String(localized: "Allow Sleep"),
                symbol: "moon.zzz",
                isEnabled: { [weak self] in self?.controller.session != nil }
            ) { [weak self] _ in
                self?.controller.allowSleep()
            },
        ]
    }

    public var quickToggles: [QuickToggle] {
        commands.filter { $0.id == "power.toggle" }.map {
            var command = $0
            command.title = String(localized: "Awake")
            return QuickToggle(command)
        }
    }

    public var islandPages: [IslandPage] {
        [IslandPage(id: "power", title: String(localized: "Power"), symbol: "cup.and.saucer") { [controller] in
            PowerIslandView(controller: controller)
        }]
    }

    public var settingsPane: SettingsPane? {
        SettingsPane { [controller] in
            PowerSettingsView(controller: controller)
        }
    }

    // MARK: Private

    private var state: CommandState {
        controller.statusText(at: Date()).map(CommandState.value) ?? .off
    }

    private func watch<Value: Sendable>(_ stream: AsyncStream<Value>) {
        tasks.append(Task { [weak self] in
            for await _ in stream {
                self?.controller.reevaluate()
                self?.updateIsland()
            }
        })
    }

    private func refreshConditions() {
        let source = context.power.powerSource
        let apps = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        controller.update(conditions: AwakeConditions(
            isOnAC: source.isOnAC,
            batteryLevel: source.batteryLevel,
            hasExternalDisplay: context.display.displays.contains { !$0.isBuiltIn },
            runningBundleIDs: apps
        ))
        updateIsland()
    }

    /// Re-runs `updateIsland` whenever the controller's state changes.
    private func observeController() {
        withObservationTracking {
            _ = controller.session
            _ = controller.ruleReasons
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateIsland()
                self?.observeController()
            }
        }
        updateIsland()
    }

    private func updateIsland() {
        guard controller.isAwake, context.settings[PowerSettings.showInIsland] else {
            activity?.dismiss()
            activity = nil
            return
        }
        let island = IslandActivity(
            id: "awake",
            title: String(localized: "Power"),
            symbol: "cup.and.saucer",
            priority: .low,
            compactLeading: AnyView(
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(.orange)
            ),
            compactTrailing: AnyView(PowerCompactTrailing(controller: controller)),
            expanded: AnyView(PowerIslandView(controller: controller))
        )
        if let activity, activity.isActive {
            activity.update(island)
        } else {
            activity = context.island.present(island)
        }
    }
}

enum PowerError: LocalizedError {
    case badTime

    var errorDescription: String? {
        switch self {
        case .badTime: String(localized: "Type a time like 17:30 or 5pm.")
        }
    }
}
