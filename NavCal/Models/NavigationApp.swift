import SwiftUI

/// The navigation apps NavCal can hand a destination off to.
enum NavigationApp: String, CaseIterable, Identifiable, Sendable {
    case waze
    case googleMaps
    case appleMaps

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .waze: "Waze"
        case .googleMaps: "Google"
        case .appleMaps: "Maps"
        }
    }

    var accessibilityName: String {
        switch self {
        case .waze: "Waze"
        case .googleMaps: "Google Maps"
        case .appleMaps: "Apple Maps"
        }
    }

    var symbolName: String {
        switch self {
        case .waze: "car.fill"
        case .googleMaps: "map.fill"
        case .appleMaps: "location.north.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .waze: Color(red: 0.20, green: 0.80, blue: 1.00)
        case .googleMaps: Color(red: 0.20, green: 0.66, blue: 0.33)
        case .appleMaps: Color(red: 0.00, green: 0.48, blue: 1.00)
        }
    }
}
