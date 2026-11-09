import Foundation
import os

/// Everything a feature gets from the app.
///
/// KKitServicesAPI adds typed accessors for the core services on top of this
/// (`context.permissions`, `context.hotkeys`, `context.overlays`, `context.storage`).
@MainActor
public struct FeatureContext: Sendable {
    public let id: FeatureID
    /// Namespaced: keys are stored as "<id>.<name>".
    public let settings: FeatureSettings
    /// Category = feature id.
    public let log: Logger
    public let events: EventBus
    /// Resolve core and feature-published services; publish your own.
    public let services: FeatureServices

    public init(
        id: FeatureID,
        settings: FeatureSettings,
        log: Logger,
        events: EventBus,
        services: FeatureServices
    ) {
        self.id = id
        self.settings = settings
        self.log = log
        self.events = events
        self.services = services
    }
}
