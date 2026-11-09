import KKitCore

/// The Floating Bar host, as features see it (`context.floatingBar`).
@MainActor
public protocol FloatingBarService: AnyObject {
    var isVisible: Bool { get }
    /// Opens the Floating Bar, optionally with `query` typed in (`"= "`, `"f report"`).
    func show(query: String?)
    /// Opens the Floating Bar in one of `owner`'s modes (`FloatingBarMode.id`).
    func showMode(_ modeID: String, owner: FeatureID, text: String?)
    func hide()
}

/// A feature's handle on the Floating Bar.
@MainActor
public struct FeatureFloatingBar {
    public let owner: FeatureID
    public let service: any FloatingBarService

    public init(owner: FeatureID, service: any FloatingBarService) {
        self.owner = owner
        self.service = service
    }

    public var isVisible: Bool { service.isVisible }

    public func show(query: String? = nil) {
        service.show(query: query)
    }

    /// Opens one of this feature's modes.
    public func showMode(_ modeID: String, text: String? = nil) {
        service.showMode(modeID, owner: owner, text: text)
    }

    public func hide() {
        service.hide()
    }
}
