import SwiftUI

@main
struct NavCalApp: App {
    @State private var viewModel: ScheduleViewModel = {
        // Launch with -NavCalDemo to show a sample schedule (handy in the simulator).
        let demo = ProcessInfo.processInfo.arguments.contains("-NavCalDemo")
        return ScheduleViewModel(
            events: demo ? SampleEventProvider() : CalendarService(),
            location: LocationService(),
            // Apple Weather needs a paid developer account; Open-Meteo is the free fallback.
            weather: demo
                ? MockWeatherProvider()
                : FallbackWeatherProvider(providers: [WeatherKitProvider(), OpenMeteoProvider()]),
            router: NavigationRouter()
        )
    }()

    var body: some Scene {
        WindowGroup {
            ScheduleView(viewModel: viewModel)
        }
    }
}
