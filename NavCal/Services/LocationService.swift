import CoreLocation

/// Supplies the device's current location.
@MainActor
protocol LocationProviding: AnyObject {
    func currentLocation() async throws -> CLLocation
}

/// One-shot "where am I" lookup used for the weather header.
@MainActor
final class LocationService: NSObject, LocationProviding {
    enum LocationError: LocalizedError {
        case denied
        case busy

        var errorDescription: String? {
            switch self {
            case .denied: "Location access is off"
            case .busy: "A location request is already in progress"
            }
        }
    }

    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        // City-level accuracy is plenty for weather and resolves much faster.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation() async throws -> CLLocation {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: break
        default: throw LocationError.denied
        }

        // Reuse a recent fix rather than waiting on the GPS again.
        if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -600 {
            return cached
        }

        guard locationContinuation == nil else { throw LocationError.busy }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            // Fires once at creation with the current status; only resume after the user decides.
            guard status != .notDetermined else { return }
            authContinuation?.resume()
            authContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }
}
