import KKitCore
import KKitServicesAPI

/// What the hosts read from: the features and their contributions, and the core
/// services they show (permissions, hotkeys).
@MainActor
public struct HostDependencies {
    public let features: FeatureManager
    public let commands: CommandRegistry
    public let settings: SettingsStore
    public let permissions: any PermissionsService
    public let hotkeys: any HotkeyService

    public init(
        features: FeatureManager,
        commands: CommandRegistry,
        settings: SettingsStore,
        permissions: any PermissionsService,
        hotkeys: any HotkeyService
    ) {
        self.features = features
        self.commands = commands
        self.settings = settings
        self.permissions = permissions
        self.hotkeys = hotkeys
    }

    /// Runs a command, logging failures.
    public func run(_ id: CommandID, source: CommandSource) {
        let commands = self.commands
        Task {
            do {
                try await commands.perform(id, CommandInvocation(source: source))
            } catch {
                KKitLog.logger("hosts").error("\(id.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// KKit's own settings (not a feature's).
public enum AppSettingKeys {
    /// Bool. Show a Dock icon (KKit is a menu bar app by default).
    public static let showDockIcon = "app.showDockIcon"
}

/// KKit's own command ids.
public enum AppCommandID {
    public static let openSettings: CommandID = "app.openSettings"
    public static let openMenu: CommandID = "app.openMenu"
}
