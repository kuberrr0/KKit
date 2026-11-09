import Foundation

public struct Coordinate: Sendable, Codable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A one-off approximate location (for sunset and sunrise times). Asks for the
/// Location permission the first time.
@MainActor
public protocol LocationService: AnyObject {
    func currentCoordinate() async throws -> Coordinate
}
