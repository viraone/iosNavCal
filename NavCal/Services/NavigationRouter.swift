import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Abstraction over `UIApplication` URL opening so routing logic is testable.
@MainActor
protocol URLOpening {
    func canOpenURL(_ url: URL) -> Bool
    func open(_ url: URL) async -> Bool
}

#if canImport(UIKit)
extension UIApplication: URLOpening {
    func open(_ url: URL) async -> Bool {
        await open(url, options: [:])
    }
}
#endif

/// Builds deep links for Waze, Google Maps and Apple Maps and launches them,
/// falling back to the web URL when the native app isn't installed.
@MainActor
final class NavigationRouter {
    private let opener: URLOpening

    #if canImport(UIKit)
    convenience init() {
        self.init(opener: UIApplication.shared)
    }
    #endif

    init(opener: URLOpening) {
        self.opener = opener
    }

    /// Opens `destination` in `app`. Returns false if nothing could be opened.
    @discardableResult
    func navigate(to destination: Destination, with app: NavigationApp) async -> Bool {
        let links = Self.links(for: destination, app: app)
        if let native = links.native, opener.canOpenURL(native), await opener.open(native) {
            return true
        }
        return await opener.open(links.web)
    }

    // MARK: - URL construction

    struct Links: Equatable {
        /// App-specific scheme URL; nil when the web URL is itself handled natively (Apple Maps).
        let native: URL?
        let web: URL
    }

    nonisolated static func links(for destination: Destination, app: NavigationApp) -> Links {
        let query = destination.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let coordinate = destination.coordinate?.formatted

        switch app {
        case .waze:
            // Coordinates are unambiguous; otherwise let Waze search the text.
            let params: [(String, String)] = if let coordinate {
                [("ll", coordinate), ("navigate", "yes")]
            } else {
                [("q", query), ("navigate", "yes")]
            }
            return Links(native: url("waze://", params), web: url("https://waze.com/ul", params)!)

        case .googleMaps:
            let target = coordinate ?? query
            return Links(
                native: url("comgooglemaps://", [("daddr", target), ("directionsmode", "driving")]),
                web: url("https://www.google.com/maps/dir/", [
                    ("api", "1"), ("destination", target), ("travelmode", "driving"),
                ])!
            )

        case .appleMaps:
            // maps.apple.com links are intercepted by the system and open Maps directly.
            var params: [(String, String)] = [("daddr", coordinate ?? query), ("dirflg", "d")]
            if coordinate != nil, !query.isEmpty {
                params.append(("q", query)) // label for the dropped pin
            }
            return Links(native: nil, web: url("http://maps.apple.com/", params)!)
        }
    }

    /// Characters left unescaped in query values: RFC 3986 "unreserved" only.
    /// Anything else — including `&`, `=`, `+`, `#`, `/` and `,` inside an address — gets percent-encoded.
    nonisolated static let queryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    nonisolated static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? ""
    }

    private nonisolated static func url(_ base: String, _ params: [(String, String)]) -> URL? {
        let query = params.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        return URL(string: "\(base)?\(query)")
    }
}
