import Foundation

/// Where weather data came from; decides the attribution shown next to it.
enum WeatherSource: Hashable, Sendable {
    /// Apple WeatherKit. Its legal page must be linked wherever the data is shown.
    case appleWeather(legalPage: URL)
    /// Open-Meteo (CC BY 4.0), used when WeatherKit isn't available.
    case openMeteo
    /// Placeholder data for demo mode and previews.
    case sample
}

/// Conditions right now, shown on today's page.
struct CurrentConditions: Hashable, Sendable {
    let temperature: Measurement<UnitTemperature>
    let conditionDescription: String
    /// SF Symbol name; uses night variants (moon) after dark.
    let symbolName: String
}

/// One day's forecast.
struct DailyForecast: Hashable, Sendable {
    /// Start of the day, in the device's time zone.
    let date: Date
    let high: Measurement<UnitTemperature>
    let low: Measurement<UnitTemperature>
    let conditionDescription: String
    let symbolName: String
    /// 0...1, or nil when the source doesn't say.
    let precipitationChance: Double?
}

/// Everything one weather fetch returns: now, plus a multi-day forecast.
struct WeatherReport: Hashable, Sendable {
    let current: CurrentConditions
    /// Consecutive days starting today.
    let daily: [DailyForecast]
    let source: WeatherSource
    let fetchedAt: Date

    func forecast(for day: Date, calendar: Calendar = .current) -> DailyForecast? {
        daily.first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// The farthest day the forecast covers.
    var lastForecastDay: Date? { daily.last?.date }
}

extension Measurement where UnitType == UnitTemperature {
    /// "48°" in the user's preferred unit.
    var weatherFormatted: String {
        formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
