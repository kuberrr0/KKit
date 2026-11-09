import CoreLocation
import Foundation
import KKitServicesAPI

/// A one-off, kilometre-accuracy location for sunset and sunrise times.
@MainActor
public final class CoreLocationService: NSObject, LocationService, CLLocationManagerDelegate {
    public struct LocationError: LocalizedError {
        public var errorDescription: String?
    }

    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<Coordinate, any Error>] = []

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    public func currentCoordinate() async throws -> Coordinate {
        try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            if waiting.count == 1 {
                begin()
            }
        }
    }

    private func begin() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.failure(LocationError(errorDescription: String(localized: "KKit isn't allowed to use your location. Allow it in System Settings › Privacy & Security › Location Services."))))
        default:
            manager.requestLocation()
        }
    }

    private func finish(_ result: Result<Coordinate, any Error>) {
        let continuations = waiting
        waiting = []
        for continuation in continuations {
            continuation.resume(with: result)
        }
    }

    // CLLocationManager calls its delegate on the thread it was created on: main.

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        MainActor.assumeIsolated {
            self.finish(.success(coordinate))
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            self.finish(.failure(LocationError(errorDescription: message)))
        }
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard !self.waiting.isEmpty else { return }
            switch self.manager.authorizationStatus {
            case .notDetermined:
                break
            default:
                self.begin()
            }
        }
    }
}
