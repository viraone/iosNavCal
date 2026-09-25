import SwiftUI

/// Weather card at the top of a day's page: conditions now on today's page, that day's
/// forecast on future pages. Its gradient follows the conditions (sunny, rainy, night…).
struct WeatherHeaderView: View {
    let weather: ScheduleViewModel.DayWeather

    private static let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        Group {
            switch weather {
            case .loading:
                plain {
                    ProgressView()
                    Text("Checking weather…").foregroundStyle(.secondary)
                }

            case .today(let now, let today, let source):
                hero(symbol: now.symbolName, source: source) {
                    Text(now.temperature.weatherFormatted)
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                    Text(now.conditionDescription).font(.headline)
                    if let today {
                        Text("H:\(today.high.weatherFormatted)  L:\(today.low.weatherFormatted)")
                            .font(.subheadline.weight(.medium))
                            .opacity(0.85)
                    }
                    rainChip(today)
                }

            case .forecast(let day, let source):
                hero(symbol: day.symbolName, source: source) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(day.high.weatherFormatted)
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                        Text(day.low.weatherFormatted)
                            .font(.system(.title2, design: .rounded, weight: .medium))
                            .opacity(0.7)
                    }
                    Text(day.conditionDescription).font(.headline)
                    rainChip(day)
                }

            case .notYetAvailable(let lastDay):
                plain {
                    Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No forecast yet").font(.subheadline.weight(.semibold))
                        if let lastDay {
                            Text("Forecasts go through \(lastDay.formatted(.dateTime.month(.abbreviated).day())).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

            case .unavailable(let reason):
                plain {
                    Image(systemName: "cloud.slash").font(.title2).foregroundStyle(.secondary)
                    Text("Weather unavailable · \(reason)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weather-header")
    }

    // MARK: - Layouts

    private func hero<Content: View>(
        symbol: String, source: WeatherSource, @ViewBuilder content: () -> Content
    ) -> some View {
        let theme = WeatherTheme(symbolName: symbol)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2, content: content)
            Spacer(minLength: 8)
            VStack(alignment: .trailing) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 44))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                Spacer(minLength: 12)
                attribution(source)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Self.shape
                .fill(LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .bottomTrailing) {
                    // Oversized, faded symbol for depth.
                    Image(systemName: symbol)
                        .font(.system(size: 150))
                        .foregroundStyle(.white.opacity(0.08))
                        .offset(x: 30, y: 40)
                }
                .clipShape(Self.shape)
                .shadow(color: theme.colors.last!.opacity(0.35), radius: 18, y: 8)
        }
    }

    private func plain<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: Self.shape)
    }

    /// "88% chance of rain", shown only when it's worth mentioning.
    @ViewBuilder
    private func rainChip(_ day: DailyForecast?) -> some View {
        if let chance = day?.precipitationChance, chance >= 0.1 {
            Label("\(chance.formatted(.percent.precision(.fractionLength(0)))) chance of rain",
                  systemImage: "drop.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.2), in: Capsule())
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func attribution(_ source: WeatherSource) -> some View {
        switch source {
        case .appleWeather(let legalPage):
            Link(destination: legalPage) {
                Text("\u{F8FF} Weather").font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
        case .openMeteo:
            Link(destination: URL(string: "https://open-meteo.com/")!) {
                Text("Open-Meteo").font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
        case .sample:
            Text("Sample")
                .font(.caption2.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.white.opacity(0.2), in: Capsule())
        }
    }
}

/// Gradient for a weather card, picked from the condition's SF Symbol name.
struct WeatherTheme {
    let colors: [Color]

    init(symbolName name: String) {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        colors = if name.contains("bolt") {
            [rgb(0.29, 0.25, 0.45), rgb(0.12, 0.10, 0.22)]
        } else if name.contains("snow") || name.contains("sleet") {
            [rgb(0.55, 0.72, 0.88), rgb(0.29, 0.42, 0.62)]
        } else if name.contains("rain") || name.contains("drizzle") {
            [rgb(0.30, 0.45, 0.66), rgb(0.13, 0.20, 0.38)]
        } else if name.contains("moon") {
            [rgb(0.15, 0.20, 0.45), rgb(0.04, 0.06, 0.18)]
        } else if name.contains("fog") || name.contains("smoke") || name.contains("haze") {
            [rgb(0.56, 0.60, 0.66), rgb(0.33, 0.37, 0.44)]
        } else if name.contains("cloud") {
            [rgb(0.42, 0.58, 0.78), rgb(0.24, 0.35, 0.55)]
        } else {
            // Clear and sunny.
            [rgb(0.24, 0.62, 0.98), rgb(0.07, 0.36, 0.80)]
        }
    }
}
