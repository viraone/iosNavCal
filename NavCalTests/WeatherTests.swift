import CoreLocation
import Foundation
import Testing
@testable import NavCal

struct OpenMeteoTests {
    /// Trimmed real response shape: Thursday night, clear and cold; Friday rain; Saturday missing rain chance.
    private let fixture = Data("""
    {
      "current": { "time": "2026-09-24T20:00", "temperature_2m": 7.4, "weather_code": 0, "is_day": 0 },
      "daily": {
        "time": ["2026-09-24", "2026-09-25", "2026-09-26"],
        "weather_code": [1, 63, 2],
        "temperature_2m_max": [16.2, 12.8, 18.0],
        "temperature_2m_min": [5.1, 7.9, 6.3],
        "precipitation_probability_max": [3, 80, null]
      }
    }
    """.utf8)

    @Test func parsesCurrentConditionsWithNightSymbol() throws {
        let report = try OpenMeteoProvider.parse(fixture, fetchedAt: .now)
        #expect(report.current.temperature == Measurement(value: 7.4, unit: .celsius))
        #expect(report.current.conditionDescription == "Clear")
        #expect(report.current.symbolName == "moon.stars.fill")
        #expect(report.source == .openMeteo)
    }

    @Test func parsesEachDaysForecast() throws {
        let report = try OpenMeteoProvider.parse(fixture, fetchedAt: .now)
        #expect(report.daily.count == 3)

        let friday = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 25)))
        let forecast = try #require(report.forecast(for: friday))
        #expect(forecast.high == Measurement(value: 12.8, unit: .celsius))
        #expect(forecast.low == Measurement(value: 7.9, unit: .celsius))
        #expect(forecast.conditionDescription == "Rain")
        #expect(forecast.symbolName == "cloud.rain.fill")
        #expect(forecast.precipitationChance == 0.8)

        #expect(report.daily[2].precipitationChance == nil)
        #expect(report.lastForecastDay == Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 26)))
    }

    @Test func requestRoundsCoordinatesAndAsksForDailyForecast() throws {
        let url = OpenMeteoProvider.requestURL(latitude: 45.523064, longitude: -122.676483)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query["latitude"] == "45.52")
        #expect(query["longitude"] == "-122.68")
        #expect(query["daily"]?.contains("temperature_2m_max") == true)
        #expect(query["forecast_days"] == "16")
    }

    @Test(arguments: [
        (0, true, "sun.max.fill"), (0, false, "moon.stars.fill"), (3, true, "cloud.fill"),
        (65, true, "cloud.heavyrain.fill"), (75, true, "cloud.snow.fill"), (95, false, "cloud.bolt.rain.fill"),
        (1234, true, "cloud.fill"),
    ])
    func mapsWeatherCodesToSymbols(code: Int, isDay: Bool, symbol: String) {
        #expect(WeatherCode.describe(code, isDay: isDay).symbolName == symbol)
    }
}

@MainActor
struct DayWeatherTests {
    @Test func eachPageGetsItsOwnDaysWeather() async throws {
        let provider = StubWeather()
        let viewModel = makeViewModel(provider)
        await viewModel.loadWeather()
        let today = viewModel.today

        guard case .today(_, let todayForecast, .sample) = viewModel.weather(for: today) else {
            Issue.record("Today should show current conditions"); return
        }
        #expect(todayForecast?.conditionDescription == "Partly Cloudy")

        let tomorrow = viewModel.day(at: 1)
        guard case .forecast(let friday, .sample) = viewModel.weather(for: tomorrow) else {
            Issue.record("Tomorrow should show its forecast"); return
        }
        #expect(friday.date == tomorrow)
        #expect(friday.conditionDescription == "Rain")

        // Mock covers 10 days; day 20 is past the end.
        #expect(viewModel.weather(for: viewModel.day(at: 20)) == .notYetAvailable(lastForecastDay: viewModel.day(at: 9)))
        // No banner for past days.
        #expect(viewModel.weather(for: viewModel.day(at: -1)) == nil)
    }

    @Test func staleWeatherIsRefetchedFreshWeatherIsNot() async throws {
        let provider = StubWeather()
        let viewModel = makeViewModel(provider)
        await viewModel.loadWeather()
        #expect(provider.calls == 1)

        await viewModel.refreshWeatherIfStale(now: .now.addingTimeInterval(10 * 60))
        #expect(provider.calls == 1)

        await viewModel.refreshWeatherIfStale(now: .now.addingTimeInterval(31 * 60))
        #expect(provider.calls == 2)
    }

    @Test func fallbackUsesNextProviderWhenOneFails() async throws {
        let fallback = FallbackWeatherProvider(providers: [FailingWeather(), MockWeatherProvider()])
        let report = try await fallback.report(at: CLLocation(latitude: 45.5, longitude: -122.7))
        #expect(report.source == .sample)
    }

    private func makeViewModel(_ weather: WeatherProviding) -> ScheduleViewModel {
        ScheduleViewModel(
            events: SampleEventProvider(), location: FixedLocation(),
            weather: weather, router: NavigationRouter(opener: NoopURLOpener())
        )
    }
}

@MainActor
private final class FixedLocation: LocationProviding {
    func currentLocation() async throws -> CLLocation { CLLocation(latitude: 45.52, longitude: -122.68) }
}

private final class StubWeather: WeatherProviding, @unchecked Sendable {
    private(set) var calls = 0
    func report(at location: CLLocation) async throws -> WeatherReport {
        calls += 1
        return try await MockWeatherProvider().report(at: location)
    }
}

private struct FailingWeather: WeatherProviding {
    func report(at location: CLLocation) async throws -> WeatherReport { throw URLError(.notConnectedToInternet) }
}

@MainActor
private struct NoopURLOpener: URLOpening {
    func canOpenURL(_ url: URL) -> Bool { false }
    func open(_ url: URL) async -> Bool { false }
}
