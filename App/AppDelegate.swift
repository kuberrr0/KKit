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
    private var island: IslandHost?
    private var floatingBar: FloatingBarHost?
    private var commandRunner: ExternalCommandRunner?
    private var workspaceEvents: WorkspaceEventsPublisher?

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

        // System services (M1). Each only starts listening when something subscribes.
        services.register((any AudioService).self, CoreAudioService())
        services.register((any DeviceUsageService).self, SystemDeviceUsageService())
        services.register((any PowerService).self, IOKitPowerService(events: events))
        services.register((any DisplayService).self, CoreGraphicsDisplayService(events: events))
        services.register((any SystemInfoService).self, MachSystemInfoService())
        services.register((any NotificationService).self, UserNotificationService())
        services.register((any SystemActionsService).self, MacSystemActionsService())
        services.register((any LocationService).self, CoreLocationService())
        // M2: Spotlight file search for the Floating Bar's file provider.
        services.register((any FileSearchService).self, SpotlightFileSearchService())
        // M3: the clipboard (polled only while Clipboard History listens) and ScreenCaptureKit.
        services.register((any PasteboardService).self, NSPasteboardService())
        services.register((any ScreenCaptureService).self, ScreenCaptureKitService())
        workspaceEvents = WorkspaceEventsPublisher(events: events)

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
        // The Island is a host and a service: features present activities through it.
        let island = IslandHost(dependencies: dependencies, events: events)
        services.register((any IslandService).self, island)
        self.island = island
        // The Floating Bar is a host and a service too: features open it with a query
        // or in one of their modes.
        let floatingBar = FloatingBarHost(dependencies: dependencies, storage: storage, island: island)
        services.register((any FloatingBarService).self, floatingBar)
        self.floatingBar = floatingBar
        menuBar = MenuBarHost(dependencies: dependencies)
        let settingsHost = SettingsHost(dependencies: dependencies, floatingBar: floatingBar)
        self.settingsHost = settingsHost
        floatingBar.openSettings = { [weak settingsHost] page in
            settingsHost?.show(page)
        }
        let commandRunner = ExternalCommandRunner(commands: commands, settings: settings, floatingBar: floatingBar)
        ExternalCommandRunner.shared = commandRunner
        self.commandRunner = commandRunner
        registerAppCommands()

        Task {
            await features.startEnabledFeatures()
            commandRunner.markReady()
            log.info("KKit started with \(features.runningFeatures.count) feature(s) running")
        }
    }

    /// `kkit://run/<command>?value=…` and `kkit://search?q=…` (ARCHITECTURE.md §5).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let commandRunner else { return }
        for url in urls {
            Task {
                do {
                    try await commandRunner.handle(url)
                } catch {
                    log.error("Link \(url.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    island?.showHUD(
                        IslandHUD(
                            id: "app.link",
                            symbol: "exclamationmark.triangle.fill",
                            title: error.localizedDescription,
                            tint: .warning,
                            duration: 3
                        ),
                        owner: .app
                    )
                }
            }
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
