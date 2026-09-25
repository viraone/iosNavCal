import Foundation
import Testing
@testable import NavCal

@MainActor
struct NavigationRouterTests {
    private let address = Destination(query: "Fred Meyer #658 & Co, 3805 SE Hawthorne Blvd")

    @Test func encodesReservedCharacters() {
        #expect(NavigationRouter.encode("A&B=C+D #1/2, E") == "A%26B%3DC%2BD%20%231%2F2%2C%20E")
    }

    @Test func wazeLinks() {
        let links = NavigationRouter.links(for: address, app: .waze)
        let q = "Fred%20Meyer%20%23658%20%26%20Co%2C%203805%20SE%20Hawthorne%20Blvd"
        #expect(links.native?.absoluteString == "waze://?q=\(q)&navigate=yes")
        #expect(links.web.absoluteString == "https://waze.com/ul?q=\(q)&navigate=yes")
    }

    @Test func googleLinks() {
        let links = NavigationRouter.links(for: Destination(query: "Safeway 555"), app: .googleMaps)
        #expect(links.native?.absoluteString == "comgooglemaps://?daddr=Safeway%20555&directionsmode=driving")
        #expect(links.web.absoluteString
            == "https://www.google.com/maps/dir/?api=1&destination=Safeway%20555&travelmode=driving")
    }

    @Test func appleMapsLinkHasNoNativeScheme() {
        let links = NavigationRouter.links(for: Destination(query: "Safeway 555"), app: .appleMaps)
        #expect(links.native == nil)
        #expect(links.web.absoluteString == "http://maps.apple.com/?daddr=Safeway%20555&dirflg=d")
    }

    @Test func coordinatesTakePriority() {
        let dest = Destination(query: "Safeway", coordinate: .init(latitude: 45.5, longitude: -122.65))
        #expect(NavigationRouter.links(for: dest, app: .waze).native?.absoluteString
            == "waze://?ll=45.500000%2C-122.650000&navigate=yes")
        #expect(NavigationRouter.links(for: dest, app: .googleMaps).native?.absoluteString
            == "comgooglemaps://?daddr=45.500000%2C-122.650000&directionsmode=driving")
    }

    @Test func fallsBackToWebWhenAppMissing() async {
        let opener = FakeOpener(installed: [])
        let ok = await NavigationRouter(opener: opener).navigate(to: address, with: .waze)
        #expect(ok)
        #expect(opener.opened.map(\.scheme) == ["https"])
    }

    @Test func opensNativeAppWhenInstalled() async {
        let opener = FakeOpener(installed: ["comgooglemaps"])
        await NavigationRouter(opener: opener).navigate(to: address, with: .googleMaps)
        #expect(opener.opened.map(\.scheme) == ["comgooglemaps"])
    }
}

@MainActor
private final class FakeOpener: URLOpening {
    let installed: Set<String>
    private(set) var opened: [URL] = []

    init(installed: Set<String>) { self.installed = installed }

    func canOpenURL(_ url: URL) -> Bool {
        url.scheme.map { $0.hasPrefix("http") || installed.contains($0) } ?? false
    }

    func open(_ url: URL) async -> Bool {
        opened.append(url)
        return true
    }
}
