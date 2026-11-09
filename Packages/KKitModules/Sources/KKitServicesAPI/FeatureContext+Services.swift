import KKitCore

/// Typed access to the core services every feature can use.
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
}
