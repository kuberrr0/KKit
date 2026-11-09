import Foundation
import KKitCore
import KKitServices
import KKitServicesAPI
import SwiftUI

/// Permissions you set by hand. Starts with everything `.notDetermined` unless granted.
@MainActor
public final class FakePermissionsService: PermissionsService {
    public var statuses: [Permission: PermissionStatus]
    public var onChange: (@MainActor () -> Void)?
    public private(set) var requested: [Permission] = []
    public private(set) var opened: [Permission] = []
    public private(set) var refreshCount = 0

    public init(granted: Set<Permission> = []) {
        var statuses: [Permission: PermissionStatus] = [:]
        for permission in Permission.allCases {
            statuses[permission] = granted.contains(permission) ? .granted : .notDetermined
        }
        self.statuses = statuses
    }

    public func status(of permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    public func refresh() {
        refreshCount += 1
    }

    @discardableResult
    public func request(_ permission: Permission) async -> PermissionStatus {
        requested.append(permission)
        return status(of: permission)
    }

    public func openSystemSettings(for permission: Permission) {
        opened.append(permission)
    }

    public func set(_ status: PermissionStatus, for permission: Permission) {
        statuses[permission] = status
        onChange?()
    }
}

/// Hotkeys kept in a dictionary.
@MainActor
public final class FakeHotkeyService: HotkeyService {
    public var shortcuts: [CommandID: Shortcut] = [:]
    public var defaults: [CommandID: Shortcut] = [:]

    public init() {}

    public func shortcut(for command: CommandID) -> Shortcut? {
        shortcuts[command]
    }

    public func setShortcut(_ shortcut: Shortcut?, for command: CommandID) {
        shortcuts[command] = shortcut
    }

    public func resetShortcut(for command: CommandID) {
        shortcuts[command] = defaults[command]
    }

    public func conflicts(for command: CommandID) -> [CommandID] {
        guard let mine = shortcuts[command] else { return [] }
        return shortcuts.filter { $0.key != command && $0.value == mine }.map(\.key).sorted()
    }

    public func displayString(for shortcut: Shortcut) -> String {
        "key \(shortcut.keyCode) mods \(shortcut.modifiers.rawValue)"
    }

    public func recorder(for command: CommandID) -> AnyView {
        AnyView(Text(shortcuts[command].map { displayString(for: $0) } ?? "None"))
    }
}

/// Records panels instead of showing them.
@MainActor
public final class FakeOverlayService: OverlayService {
    public private(set) var panels: [FakeOverlayHandle] = []
    /// What the next `pickRegion` returns (`nil` = the user pressed ⎋).
    public var nextRegion: RegionSelection?
    public private(set) var regionRequests: [RegionPickerOptions] = []
    public var screens: [ScreenInfo] = [
        ScreenInfo(
            id: 1,
            name: "Built-in Display",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            notchHeight: 38,
            isMain: true
        ),
    ]

    public init() {}

    public func makePanel(_ configuration: OverlayConfiguration, content: AnyView) -> any OverlayHandle {
        let handle = FakeOverlayHandle(configuration: configuration)
        panels.append(handle)
        return handle
    }

    public func pickRegion(_ options: RegionPickerOptions) async -> RegionSelection? {
        regionRequests.append(options)
        return nextRegion
    }

    /// Panels not yet closed.
    public var openPanels: [FakeOverlayHandle] { panels.filter { !$0.isClosed } }
}

@MainActor
public final class FakeOverlayHandle: OverlayHandle {
    public private(set) var configuration: OverlayConfiguration
    public private(set) var isVisible = false
    public private(set) var isClosed = false

    init(configuration: OverlayConfiguration) {
        self.configuration = configuration
    }

    public func show() { isVisible = true }
    public func hide() { isVisible = false }
    public func setContent(_ content: AnyView) {}
    public func setConfiguration(_ configuration: OverlayConfiguration) { self.configuration = configuration }
    public func close() {
        isVisible = false
        isClosed = true
    }
}

/// Keeps JSON in memory; `directory(for:)` returns a throwaway temporary folder.
public final class InMemoryStorageService: StorageService, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("KKitTests-\(UUID().uuidString)", isDirectory: true)

    public init() {}

    public func directory(for feature: FeatureID) throws -> URL {
        let url = root.appendingPathComponent(feature.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func readJSON<Value: Decodable>(_ type: Value.Type, named name: String, for feature: FeatureID) throws -> Value? {
        let data = lock.withLock { files["\(feature.rawValue)/\(name)"] }
        guard let data else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    public func writeJSON<Value: Encodable>(_ value: Value, named name: String, for feature: FeatureID) throws {
        let data = try JSONEncoder().encode(value)
        lock.withLock { files["\(feature.rawValue)/\(name)"] = data }
    }

    public func removeJSON(named name: String, for feature: FeatureID) throws {
        _ = lock.withLock { files.removeValue(forKey: "\(feature.rawValue)/\(name)") }
    }

    /// A private in-memory SQLite database (the real implementation, so SQL is tested).
    public func openDatabase(named name: String, for feature: FeatureID) throws -> any Database {
        try SQLiteDatabase(url: nil)
    }
}

/// A complete set of core services backed by fakes, for feature tests.
@MainActor
public struct TestEnvironment {
    public let settings: SettingsStore
    public let commands: CommandRegistry
    public let services: ServiceRegistry
    public let events: EventBus
    public let permissions: FakePermissionsService
    public let hotkeys: FakeHotkeyService
    public let overlays: FakeOverlayService
    public let storage: InMemoryStorageService
    public let island: FakeIslandService
    public let audio: FakeAudioService
    public let deviceUsage: FakeDeviceUsageService
    public let power: FakePowerService
    public let display: FakeDisplayService
    public let systemInfo: FakeSystemInfoService
    public let notifications: FakeNotificationService
    public let systemActions: FakeSystemActionsService
    public let location: FakeLocationService
    public let floatingBar: FakeFloatingBarService
    public let fileSearch: FakeFileSearchService
    public let pasteboard: FakePasteboardService
    public let screenCapture: FakeScreenCaptureService
    public let input: FakeInputTapService
    public let windows: FakeWindowService
    public let accessibility: FakeAccessibilityService
    public let commandRunner: FakeCommandRunner
    public let menuBarItems: FakeMenuBarItemsService

    /// - Parameter granted: permissions that start granted.
    public init(granted: Set<Permission> = []) {
        let suite = "KKitTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        settings = SettingsStore(defaults: defaults)
        commands = CommandRegistry()
        services = ServiceRegistry()
        events = EventBus()
        permissions = FakePermissionsService(granted: granted)
        hotkeys = FakeHotkeyService()
        overlays = FakeOverlayService()
        storage = InMemoryStorageService()
        island = FakeIslandService()
        audio = FakeAudioService()
        deviceUsage = FakeDeviceUsageService()
        power = FakePowerService()
        display = FakeDisplayService()
        systemInfo = FakeSystemInfoService()
        notifications = FakeNotificationService()
        systemActions = FakeSystemActionsService()
        location = FakeLocationService()
        floatingBar = FakeFloatingBarService()
        fileSearch = FakeFileSearchService()
        pasteboard = FakePasteboardService()
        screenCapture = FakeScreenCaptureService()
        input = FakeInputTapService()
        windows = FakeWindowService()
        accessibility = FakeAccessibilityService()
        commandRunner = FakeCommandRunner()
        menuBarItems = FakeMenuBarItemsService()
        services.register((any PermissionsService).self, permissions)
        services.register((any HotkeyService).self, hotkeys)
        services.register((any OverlayService).self, overlays)
        services.register((any StorageService).self, storage)
        services.register((any IslandService).self, island)
        services.register((any AudioService).self, audio)
        services.register((any DeviceUsageService).self, deviceUsage)
        services.register((any PowerService).self, power)
        services.register((any DisplayService).self, display)
        services.register((any SystemInfoService).self, systemInfo)
        services.register((any NotificationService).self, notifications)
        services.register((any SystemActionsService).self, systemActions)
        services.register((any LocationService).self, location)
        services.register((any FloatingBarService).self, floatingBar)
        services.register((any FileSearchService).self, fileSearch)
        services.register((any PasteboardService).self, pasteboard)
        services.register((any ScreenCaptureService).self, screenCapture)
        services.register((any InputTapService).self, input)
        services.register((any WindowService).self, windows)
        services.register((any AccessibilityService).self, accessibility)
        services.register((any CommandRunnerService).self, commandRunner)
        services.register((any MenuBarItemsService).self, menuBarItems)
    }

    /// Lets queued main-actor work (stream deliveries) run.
    public func settle(_ rounds: Int = 5) async {
        for _ in 0..<rounds {
            await Task.yield()
        }
    }

    public func makeFeatureManager(catalog: [any Feature.Type]) -> FeatureManager {
        FeatureManager(
            catalog: catalog,
            settings: settings,
            commands: commands,
            services: services,
            events: events,
            permissions: permissions
        )
    }

    public func makeContext(for id: FeatureID) -> FeatureContext {
        FeatureContext(
            id: id,
            settings: FeatureSettings(featureID: id, store: settings),
            log: KKitLog.logger(id.rawValue),
            events: events,
            services: FeatureServices(featureID: id, registry: services)
        )
    }
}
