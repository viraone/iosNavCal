import CoreLocation
import Foundation

/// Free forecasts from Open-Meteo (https://open-meteo.com). No account or API key needed.
///
/// Data is CC BY 4.0, so the UI links to Open-Meteo wherever it's shown. The free API is for
/// non-commercial use; a commercial release needs one of their paid plans.
/// Coordinates are rounded to about 1 km before being sent.
struct OpenMeteoProvider: WeatherProviding {
    var session: URLSession = .shared

    func report(at location: CLLocation) async throws -> WeatherReport {
        let url = Self.requestURL(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try Self.parse(data, fetchedAt: .now)
    }

    static func requestURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "16"),
        ]
        return components.url!
    }

    // MARK: - Parsing

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int?]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_probability_max: [Int?]?
        }
        let current: Current
        let daily: Daily
    }

    static func parse(_ data: Data, calendar: Calendar = .current, fetchedAt: Date) throws -> WeatherReport {
        let response = try JSONDecoder().decode(Response.self, from: data)

        let current = WeatherCode.describe(response.current.weather_code, isDay: response.current.is_day == 1)

        // Daily dates are plain "yyyy-MM-dd" in the forecast location's time zone.
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let d = response.daily
        let daily: [DailyForecast] = d.time.indices.compactMap { i in
            guard let date = dayFormatter.date(from: d.time[i]),
                  let code = d.weather_code[safe: i] ?? nil,
                  let high = d.temperature_2m_max[safe: i] ?? nil,
                  let low = d.temperature_2m_min[safe: i] ?? nil else { return nil }
            let condition = WeatherCode.describe(code, isDay: true)
            let rain = (d.precipitation_probability_max?[safe: i] ?? nil).map { Double($0) / 100 }
            return DailyForecast(
                date: calendar.startOfDay(for: date),
                high: Measurement(value: high, unit: .celsius),
                low: Measurement(value: low, unit: .celsius),
                conditionDescription: condition.description,
                symbolName: condition.symbolName,
                precipitationChance: rain
            )
        }

        return WeatherReport(
            current: CurrentConditions(
                temperature: Measurement(value: response.current.temperature_2m, unit: .celsius),
                conditionDescription: current.description,
                symbolName: current.symbolName
            ),
            daily: daily,
            source: .openMeteo,
            fetchedAt: fetchedAt
        )
    }
}

/// WMO weather interpretation codes, as used by Open-Meteo.
enum WeatherCode {
    static func describe(_ code: Int, isDay: Bool) -> (description: String, symbolName: String) {
        switch code {
        case 0: ("Clear", isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1: ("Mostly Clear", isDay ? "sun.max.fill" : "moon.stars.fill")
        case 2: ("Partly Cloudy", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: ("Cloudy", "cloud.fill")
        case 45, 48: ("Fog", "cloud.fog.fill")
        case 51, 53, 55: ("Drizzle", "cloud.drizzle.fill")
        case 56, 57: ("Freezing Drizzle", "cloud.sleet.fill")
        case 61, 63: ("Rain", "cloud.rain.fill")
        case 65: ("Heavy Rain", "cloud.heavyrain.fill")
        case 66, 67: ("Freezing Rain", "cloud.sleet.fill")
        case 71, 73, 77: ("Snow", "cloud.snow.fill")
        case 75: ("Heavy Snow", "cloud.snow.fill")
        case 80, 81: ("Showers", isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill")
        case 82: ("Heavy Showers", "cloud.heavyrain.fill")
        case 85, 86: ("Snow Showers", "cloud.snow.fill")
        case 95: ("Thunderstorms", "cloud.bolt.rain.fill")
        case 96, 99: ("Thunderstorms with Hail", "cloud.bolt.rain.fill")
        default: ("Unknown", "cloud.fill")
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
