import CoreLocation
import WeatherKit

/// Supplies current conditions and a daily forecast for a location.
protocol WeatherProviding: Sendable {
    func report(at location: CLLocation) async throws -> WeatherReport
}

/// Live data from Apple WeatherKit.
///
/// Requires a paid Apple Developer Program membership, the WeatherKit capability on the
/// App ID, and the `com.apple.developer.weatherkit` entitlement (see README). Without
/// them, requests fail and `FallbackWeatherProvider` moves on to Open-Meteo.
struct WeatherKitProvider: WeatherProviding {
    func report(at location: CLLocation) async throws -> WeatherReport {
        let service = WeatherService.shared
        async let weather = service.weather(for: location, including: .current, .daily)
        async let attribution = service.attribution
        let ((current, daily), credit) = try await (weather, attribution)
        let calendar = Calendar.current

        return WeatherReport(
            current: CurrentConditions(
                temperature: current.temperature,
                conditionDescription: current.condition.description,
                symbolName: current.symbolName
            ),
            daily: daily.forecast.map { day in
                DailyForecast(
                    date: calendar.startOfDay(for: day.date),
                    high: day.highTemperature,
                    low: day.lowTemperature,
                    conditionDescription: day.condition.description,
                    symbolName: day.symbolName,
                    precipitationChance: day.precipitationChance
                )
            },
            source: .appleWeather(legalPage: credit.legalPageURL),
            fetchedAt: .now
        )
    }
}

/// Placeholder weather for demo mode and previews, clearly labeled "Sample" in the UI.
struct MockWeatherProvider: WeatherProviding {
    func report(at location: CLLocation) async throws -> WeatherReport {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let pattern: [(high: Double, low: Double, name: String, symbol: String, rain: Double)] = [
            (17, 8, "Partly Cloudy", "cloud.sun.fill", 0.1),
            (14, 9, "Rain", "cloud.rain.fill", 0.8),
            (19, 10, "Clear", "sun.max.fill", 0.0),
        ]
        let daily = (0..<10).map { offset in
            let day = pattern[offset % pattern.count]
            return DailyForecast(
                date: calendar.date(byAdding: .day, value: offset, to: today)!,
                high: Measurement(value: day.high, unit: .celsius),
                low: Measurement(value: day.low, unit: .celsius),
                conditionDescription: day.name,
                symbolName: day.symbol,
                precipitationChance: day.rain
            )
        }
        return WeatherReport(
            current: CurrentConditions(
                temperature: Measurement(value: 12, unit: .celsius),
                conditionDescription: "Partly Cloudy",
                symbolName: "cloud.sun.fill"
            ),
            daily: daily,
            source: .sample,
            fetchedAt: .now
        )
    }
}

/// Tries each provider in order and returns the first report that succeeds.
struct FallbackWeatherProvider: WeatherProviding {
    let providers: [WeatherProviding]

    func report(at location: CLLocation) async throws -> WeatherReport {
        var lastError: Error = URLError(.cannotLoadFromNetwork)
        for provider in providers {
            do {
                return try await provider.report(at: location)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
