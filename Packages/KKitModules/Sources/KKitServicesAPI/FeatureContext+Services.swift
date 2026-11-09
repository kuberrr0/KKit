import KKitCore

/// Typed access to the core services every feature can use. The app registers all
/// of them at launch (and `TestEnvironment` registers fakes), so `require` is safe.
public extension FeatureContext {
    var permissions: any PermissionsService {
        services.require((any PermissionsService).self)
    }

    var hotkeys: any HotkeyService {
        services.require((any HotkeyService).self)
    }

    var overlays: any OverlayService {
        services.require((any OverlayService).self)
    }

    var storage: FeatureStorage {
        FeatureStorage(featureID: id, service: services.require((any StorageService).self))
    }

    /// The Island host. Activities are dropped automatically when the feature stops.
    var island: FeatureIsland {
        FeatureIsland(owner: id, service: services.require((any IslandService).self))
    }

    var audio: any AudioService {
        services.require((any AudioService).self)
    }

    var deviceUsage: any DeviceUsageService {
        services.require((any DeviceUsageService).self)
    }

    var power: any PowerService {
        services.require((any PowerService).self)
    }

    var display: any DisplayService {
        services.require((any DisplayService).self)
    }

    var systemInfo: any SystemInfoService {
        services.require((any SystemInfoService).self)
    }

    var notifications: any NotificationService {
        services.require((any NotificationService).self)
    }

    var systemActions: any SystemActionsService {
        services.require((any SystemActionsService).self)
    }

    var location: any LocationService {
        services.require((any LocationService).self)
    }

    /// The Floating Bar host (M2).
    var floatingBar: FeatureFloatingBar {
        FeatureFloatingBar(owner: id, service: services.require((any FloatingBarService).self))
    }

    var fileSearch: any FileSearchService {
        services.require((any FileSearchService).self)
    }

    /// The general clipboard (M3).
    var pasteboard: any PasteboardService {
        services.require((any PasteboardService).self)
    }

    /// Screenshots and recordings (M3).
    var screenCapture: any ScreenCaptureService {
        services.require((any ScreenCaptureService).self)
    }
}
