import Foundation
import Observation

/// Finds services by protocol type.
///
/// The app registers the core services (permissions, hotkeys, overlays, storage…) at
/// launch. Features can also *publish* a service for other features to use optionally,
/// without importing each other:
///
/// ```swift
/// // Shelf, in start():
/// context.services.publish((any ShelfServicing).self, controller)
/// // Screen Tools:
/// if let shelf = context.services.resolve((any ShelfServicing).self) { … }
/// ```
///
/// A feature's published services are removed automatically when it stops.
@MainActor
@Observable
public final class ServiceRegistry {
    private struct Entry {
        let instance: Any
        let publisher: FeatureID?
    }

    @ObservationIgnored private var entries: [ObjectIdentifier: Entry] = [:]
    /// Bumped when anything is published or removed, so views re-check `resolve`.
    private var revision = 0
    private let log = KKitLog.logger("services")

    public init() {}

    /// Registers a core service. Replaces any existing one.
    public func register<Service>(_ type: Service.Type, _ instance: Service) {
        entries[ObjectIdentifier(type)] = Entry(instance: instance, publisher: nil)
        revision &+= 1
    }

    /// Publishes a service owned by `feature`.
    public func publish<Service>(_ type: Service.Type, _ instance: Service, by feature: FeatureID) {
        let key = ObjectIdentifier(type)
        if let existing = entries[key], existing.publisher != feature {
            log.error("\(feature.rawValue, privacy: .public) replaced the provider of \(String(describing: type), privacy: .public)")
        }
        entries[key] = Entry(instance: instance, publisher: feature)
        revision &+= 1
    }

    public func unpublish<Service>(_ type: Service.Type) {
        guard entries.removeValue(forKey: ObjectIdentifier(type)) != nil else { return }
        revision &+= 1
    }

    /// Removes every service `feature` published.
    public func unpublishAll(by feature: FeatureID) {
        let keys = entries.filter { $0.value.publisher == feature }.map(\.key)
        guard !keys.isEmpty else { return }
        for key in keys {
            entries[key] = nil
        }
        revision &+= 1
    }

    public func resolve<Service>(_ type: Service.Type) -> Service? {
        _ = revision
        return entries[ObjectIdentifier(type)]?.instance as? Service
    }

    /// For core services the app always registers. Crashes if it's missing, which is a
    /// programming error caught at launch.
    public func require<Service>(_ type: Service.Type) -> Service {
        guard let service = resolve(type) else {
            fatalError("Service \(String(describing: type)) is not registered")
        }
        return service
    }
}

/// A feature's handle on the registry: publishing records the feature as the owner.
@MainActor
public struct FeatureServices: Sendable {
    public let featureID: FeatureID
    public let registry: ServiceRegistry

    public init(featureID: FeatureID, registry: ServiceRegistry) {
        self.featureID = featureID
        self.registry = registry
    }

    public func publish<Service>(_ type: Service.Type, _ instance: Service) {
        registry.publish(type, instance, by: featureID)
    }

    public func unpublish<Service>(_ type: Service.Type) {
        registry.unpublish(type)
    }

    public func resolve<Service>(_ type: Service.Type) -> Service? {
        registry.resolve(type)
    }

    public func require<Service>(_ type: Service.Type) -> Service {
        registry.require(type)
    }
}
