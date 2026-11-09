import Foundation
import Observation
import os

/// Where a feature is in its lifecycle (ARCHITECTURE.md §4.4).
public enum FeatureState: Sendable, Hashable {
    case disabled
    /// The Mac's macOS is older than the manifest's `minimumOS`.
    case unsupported
    case waitingForPermissions(Set<Permission>)
    case starting
    case running
    case failed(String)

    public var isRunning: Bool { self == .running }

    public var missingPermissions: Set<Permission> {
        if case .waitingForPermissions(let missing) = self { missing } else { [] }
    }
}

/// Creates, starts and stops features, and keeps their contributions registered while
/// they run. One broken feature never takes the app down: a throwing `start()` moves
/// it to `.failed` with a message and a Retry button in Settings.
@MainActor
@Observable
public final class FeatureManager {
    /// Manifests of every feature in the catalog, in catalog order.
    public let manifests: [FeatureManifest]
    public private(set) var states: [FeatureID: FeatureState] = [:]
    private var instances: [FeatureID: any Feature] = [:]

    private let types: [FeatureID: any Feature.Type]
    private let store: SettingsStore
    private let commands: CommandRegistry
    private let services: ServiceRegistry
    private let events: EventBus
    private let permissions: any PermissionStatusProviding
    private let log = KKitLog.logger("features")
    @ObservationIgnored private var recheckTask: Task<Void, Never>?

    /// How often to re-check permissions while a feature is waiting for one.
    @ObservationIgnored public var recheckInterval: Duration = .seconds(3)

    public init(
        catalog: [any Feature.Type],
        settings: SettingsStore,
        commands: CommandRegistry,
        services: ServiceRegistry,
        events: EventBus,
        permissions: any PermissionStatusProviding
    ) {
        var manifests: [FeatureManifest] = []
        var types: [FeatureID: any Feature.Type] = [:]
        let log = KKitLog.logger("features")
        for type in catalog {
            let manifest = type.manifest
            guard manifest.id.isValid, manifest.id != .app else {
                log.fault("Feature id \(manifest.id.rawValue, privacy: .public) is invalid; skipping it")
                continue
            }
            guard types[manifest.id] == nil else {
                log.fault("Duplicate feature id \(manifest.id.rawValue, privacy: .public); skipping it")
                continue
            }
            types[manifest.id] = type
            manifests.append(manifest)
        }
        self.manifests = manifests
        self.types = types
        self.store = settings
        self.commands = commands
        self.services = services
        self.events = events
        self.permissions = permissions
        for manifest in manifests {
            states[manifest.id] = .disabled
        }
    }

    // MARK: Reading

    public func manifest(for id: FeatureID) -> FeatureManifest? {
        manifests.first { $0.id == id }
    }

    public func state(of id: FeatureID) -> FeatureState {
        states[id] ?? .disabled
    }

    /// The user's on/off choice (or the manifest default).
    public func isEnabled(_ id: FeatureID) -> Bool {
        guard let info = manifest(for: id) else { return false }
        return store.value(for: Self.enabledKey(id), default: info.enabledByDefault)
    }

    /// The running instance, if the feature is running.
    public func runningFeature(_ id: FeatureID) -> (any Feature)? {
        state(of: id).isRunning ? instances[id] : nil
    }

    /// Running features in catalog order. Hosts read contributions from these.
    public var runningFeatures: [any Feature] {
        manifests.compactMap { runningFeature($0.id) }
    }

    /// The settings view for a feature, whether or not it's running.
    public func settings(for id: FeatureID) -> FeatureSettings {
        FeatureSettings(featureID: id, store: store)
    }

    /// Permissions some enabled feature needs but doesn't have.
    public var missingPermissions: Set<Permission> {
        states.values.reduce(into: Set<Permission>()) { $0.formUnion($1.missingPermissions) }
    }

    // MARK: Lifecycle

    /// Starts every enabled feature. Call once at launch.
    public func startEnabledFeatures() async {
        for manifest in manifests where isEnabled(manifest.id) {
            await activate(manifest.id)
        }
    }

    public func setEnabled(_ enabled: Bool, for id: FeatureID) async {
        guard manifest(for: id) != nil else { return }
        store.set(enabled, for: Self.enabledKey(id))
        if enabled {
            await activate(id)
        } else {
            await deactivate(id, to: .disabled)
        }
    }

    /// Tries a failed feature again.
    public func retry(_ id: FeatureID) async {
        guard isEnabled(id) else { return }
        await activate(id)
    }

    /// Re-reads permissions: starts features that were waiting and now can run, and
    /// stops running ones that lost a required permission.
    public func reevaluatePermissions() async {
        permissions.refresh()
        for manifest in manifests {
            switch state(of: manifest.id) {
            case .waitingForPermissions:
                await activate(manifest.id)
            case .running:
                let missing = lackingPermissions(for: manifest)
                if !missing.isEmpty {
                    log.info("\(manifest.id.rawValue, privacy: .public) lost permissions; stopping")
                    await deactivate(manifest.id, to: .waitingForPermissions(missing))
                }
            default:
                break
            }
        }
        updateRecheckLoop()
    }

    /// Stops everything (app termination).
    public func stopAll() async {
        recheckTask?.cancel()
        recheckTask = nil
        for manifest in manifests.reversed() where state(of: manifest.id) != .disabled {
            await deactivate(manifest.id, to: .disabled)
        }
    }

    // MARK: Private

    static func enabledKey(_ id: FeatureID) -> String {
        "app.featureEnabled.\(id.rawValue)"
    }

    private func lackingPermissions(for manifest: FeatureManifest) -> Set<Permission> {
        manifest.requiredPermissions.filter { !permissions.status(of: $0).isGranted }
    }

    private func activate(_ id: FeatureID) async {
        guard let type = types[id], let info = manifest(for: id) else { return }
        switch state(of: id) {
        case .running, .starting:
            return
        default:
            break
        }
        guard info.isSupportedOnThisOS else {
            setState(.unsupported, for: id)
            return
        }
        let missing = lackingPermissions(for: info)
        guard missing.isEmpty else {
            setState(.waitingForPermissions(missing), for: id)
            updateRecheckLoop()
            return
        }

        setState(.starting, for: id)
        let feature = type.init(context: makeContext(for: id))
        instances[id] = feature
        do {
            try await feature.start()
        } catch {
            log.error("\(id.rawValue, privacy: .public) failed to start: \(error.localizedDescription, privacy: .public)")
            await feature.stop()
            services.unpublishAll(by: id)
            if state(of: id) == .starting {
                instances[id] = nil
                setState(.failed(error.localizedDescription), for: id)
            }
            updateRecheckLoop()
            return
        }

        // The user may have turned it off while it was starting.
        guard state(of: id) == .starting, instances[id] === feature else {
            await feature.stop()
            services.unpublishAll(by: id)
            return
        }
        commands.register(feature.commands, owner: id)
        setState(.running, for: id)
        log.info("\(id.rawValue, privacy: .public) running")
        updateRecheckLoop()
    }

    /// Stops a feature without changing the user's on/off choice.
    private func deactivate(_ id: FeatureID, to newState: FeatureState) async {
        let previous = state(of: id)
        let feature = instances.removeValue(forKey: id)
        setState(newState, for: id)
        commands.unregister(owner: id)
        // A feature that is still starting is stopped by `activate` when start returns.
        if previous == .running, let feature {
            await feature.stop()
        }
        services.unpublishAll(by: id)
        updateRecheckLoop()
    }

    private func setState(_ state: FeatureState, for id: FeatureID) {
        guard states[id] != state else { return }
        states[id] = state
        events.publish(.featureStateChanged(id))
    }

    private func makeContext(for id: FeatureID) -> FeatureContext {
        FeatureContext(
            id: id,
            settings: FeatureSettings(featureID: id, store: store),
            log: KKitLog.logger(id.rawValue),
            events: events,
            services: FeatureServices(featureID: id, registry: services)
        )
    }

    /// Polls permissions only while some feature is waiting for one.
    private func updateRecheckLoop() {
        let isWaiting = states.values.contains { !$0.missingPermissions.isEmpty }
        if isWaiting {
            guard recheckTask == nil else { return }
            let interval = recheckInterval
            recheckTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    guard !Task.isCancelled, let manager = self else { return }
                    await manager.reevaluatePermissions()
                }
            }
        } else {
            recheckTask?.cancel()
            recheckTask = nil
        }
    }
}
