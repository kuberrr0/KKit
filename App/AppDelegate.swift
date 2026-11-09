import AppKit
import KKitCore
import KKitHosts
import KKitServices
import KKitServicesAPI

/// Boots the core: settings, events, services, the feature manager and the hosts.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = KKitLog.logger("app")

    private let settings = SettingsStore()
    private let events = EventBus()
    private let services = ServiceRegistry()
    private let commands = CommandRegistry()

    private var features: FeatureManager?
    private var menuBar: MenuBarHost?
    private var settingsHost: SettingsHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(target: self)
        DockIconPolicy.apply(showDockIcon: settings.value(for: AppSettingKeys.showDockIcon, default: false))

        // Core services, registered before any feature is created.
        let permissions = SystemPermissionsService()
        let hotkeys = KeyboardShortcutsHotkeyService(commands: commands)
        let overlays = AppKitOverlayService(events: events)
        let storage: any StorageService
        do {
            storage = try FileStorageService.applicationSupport()
        } catch {
            log.fault("No Application Support folder: \(error.localizedDescription, privacy: .public)")
            storage = FileStorageService(root: FileManager.default.temporaryDirectory.appendingPathComponent("KKit"))
        }
        services.register((any PermissionsService).self, permissions)
        services.register((any HotkeyService).self, hotkeys)
        services.register((any OverlayService).self, overlays)
        services.register((any StorageService).self, storage)

        let features = FeatureManager(
            catalog: FeatureCatalog.all,
            settings: settings,
            commands: commands,
            services: services,
            events: events,
            permissions: permissions
        )
        self.features = features
        permissions.onChange = { [weak features] in
            guard let features else { return }
            Task { await features.reevaluatePermissions() }
        }

        let dependencies = HostDependencies(
            features: features,
            commands: commands,
            settings: settings,
            permissions: permissions,
            hotkeys: hotkeys
        )
        menuBar = MenuBarHost(dependencies: dependencies)
        settingsHost = SettingsHost(dependencies: dependencies)
        registerAppCommands()

        Task {
            await features.startEnabledFeatures()
            log.info("KKit started with \(features.runningFeatures.count) feature(s) running")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening KKit again from Finder or Spotlight shows Settings.
        if !flag {
            settingsHost?.show()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let features else { return .terminateNow }
        Task {
            await features.stopAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: Commands

    /// KKit's own commands, owned by the reserved `app` id.
    private func registerAppCommands() {
        commands.register([
            Command(
                id: AppCommandID.openSettings,
                title: String(localized: "Open KKit Settings"),
                symbol: "gearshape",
                keywords: ["preferences", "settings"]
            ) { [weak self] _ in
                self?.settingsHost?.show()
            },
            Command(
                id: AppCommandID.openMenu,
                title: String(localized: "Open KKit Menu"),
                subtitle: String(localized: "The menu bar popover with quick toggles"),
                symbol: "square.grid.2x2"
            ) { [weak self] _ in
                self?.menuBar?.showPopover()
            },
        ], owner: .app)
    }

    @objc func showSettings(_ sender: Any?) {
        settingsHost?.show()
    }
}
