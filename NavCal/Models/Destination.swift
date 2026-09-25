import CoreLocation

/// Where a navigation app should route to: free-text query plus optional exact coordinates.
struct Destination: Hashable, Sendable {
    /// Human-readable address or place name, e.g. "Safeway 555" or "123 Main St, Portland, OR".
    let query: String
    /// Exact coordinates when the calendar provides a structured location.
    let coordinate: Coordinate?

    struct Coordinate: Hashable, Sendable {
        let latitude: Double
        let longitude: Double

        /// "lat,lon" with fixed precision, as expected by all three navigation apps.
        var formatted: String {
            String(format: "%.6f,%.6f", latitude, longitude)
        }
    }

    init(query: String, coordinate: Coordinate? = nil) {
        self.query = query
        self.coordinate = coordinate
    }

    init(query: String, location: CLLocation?) {
        self.query = query
        self.coordinate = location.map {
            Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
    }
}
