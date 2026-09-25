import SwiftUI

/// Weather banner at the top of a day's page: conditions now on today's page,
/// that day's forecast on future pages.
struct WeatherHeaderView: View {
    let weather: ScheduleViewModel.DayWeather

    var body: some View {
        HStack(spacing: 12) {
            switch weather {
            case .loading:
                ProgressView()
                Text("Checking weather…").foregroundStyle(.secondary)
                Spacer()

            case .today(let now, let today, let source):
                symbol(now.symbolName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(now.temperature.weatherFormatted).font(.title2.bold())
                    Text(todaySummary(now, today)).font(.subheadline).foregroundStyle(.secondary)
                    if let rain = rainText(today) { rain }
                }
                Spacer()
                attribution(source)

            case .forecast(let day, let source):
                symbol(day.symbolName)
                VStack(alignment: .leading, spacing: 2) {
                    Text("H:\(day.high.weatherFormatted)  L:\(day.low.weatherFormatted)").font(.title3.bold())
                    Text(day.conditionDescription).font(.subheadline).foregroundStyle(.secondary)
                    if let rain = rainText(day) { rain }
                }
                Spacer()
                attribution(source)

            case .notYetAvailable(let lastDay):
                Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No forecast yet").font(.subheadline.weight(.semibold))
                    if let lastDay {
                        Text("Forecasts go through \(lastDay.formatted(.dateTime.month(.abbreviated).day())).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()

            case .unavailable(let reason):
                Image(systemName: "cloud.slash").font(.title2).foregroundStyle(.secondary)
                Text("Weather unavailable · \(reason)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weather-header")
    }

    private func symbol(_ name: String) -> some View {
        // Weather symbols draw clouds in white, so give them a backdrop that works in light mode too.
        Image(systemName: name)
            .symbolRenderingMode(.multicolor)
            .font(.title2)
            .frame(width: 48, height: 48)
            .background(Color(.systemGray3), in: Circle())
    }

    private func todaySummary(_ now: CurrentConditions, _ today: DailyForecast?) -> String {
        guard let today else { return now.conditionDescription }
        return "\(now.conditionDescription) · H:\(today.high.weatherFormatted) L:\(today.low.weatherFormatted)"
    }

    /// "40% chance of rain", shown only when it's worth mentioning.
    private func rainText(_ day: DailyForecast?) -> Text? {
        guard let chance = day?.precipitationChance, chance >= 0.1 else { return nil }
        return Text("\(Image(systemName: "drop.fill")) \(chance.formatted(.percent.precision(.fractionLength(0)))) chance of rain")
            .font(.caption)
            .foregroundStyle(.blue)
    }

    @ViewBuilder
    private func attribution(_ source: WeatherSource) -> some View {
        switch source {
        case .appleWeather(let legalPage):
            Link(destination: legalPage) {
                Text("\u{F8FF} Weather").font(.caption2).foregroundStyle(.secondary)
            }
        case .openMeteo:
            Link(destination: URL(string: "https://open-meteo.com/")!) {
                Text("Open-Meteo").font(.caption2).foregroundStyle(.secondary)
            }
        case .sample:
            Text("Sample")
                .font(.caption2.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
    }
}
