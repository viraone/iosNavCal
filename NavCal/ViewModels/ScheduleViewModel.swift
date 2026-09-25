import CoreLocation
import EventKitUI
import Observation

/// Drives the dashboard: loads each day's events and weather, and routes navigation taps.
@MainActor
@Observable
final class ScheduleViewModel {
    enum AccessState: Equatable {
        case loading
        case granted
        case denied
        case failed(String)
    }

    enum WeatherState: Equatable {
        case loading
        case loaded(WeatherReport)
        case unavailable(String)
    }

    /// What the weather banner shows on one day's page.
    enum DayWeather: Equatable {
        case loading
        /// Today: conditions now, plus today's high/low when available.
        case today(CurrentConditions, DailyForecast?, WeatherSource)
        /// A future day inside the forecast range.
        case forecast(DailyForecast, WeatherSource)
        /// A future day past the end of the forecast.
        case notYetAvailable(lastForecastDay: Date?)
        case unavailable(String)
    }

    /// How old weather can get before it's refetched when the app comes back to the front.
    static let weatherMaxAge: TimeInterval = 30 * 60

    private(set) var accessState: AccessState = .loading
    private(set) var weatherState: WeatherState = .loading
    var navigationError: String?

    /// Start of the current day; day pages are offsets from this.
    private(set) var today: Date
    /// Offset from `today` of the page being shown (0 = today, 1 = tomorrow, -1 = yesterday).
    private(set) var dayOffset = 0
    /// Events per start-of-day, filled lazily as pages come on screen.
    private(set) var eventsByDay: [Date: [CalendarEvent]] = [:]

    private let calendar = Calendar.current

    private let events: EventProviding
    private let location: LocationProviding
    private let weather: WeatherProviding
    private let router: NavigationRouter

    init(
        events: EventProviding,
        location: LocationProviding,
        weather: WeatherProviding,
        router: NavigationRouter
    ) {
        self.events = events
        self.location = location
        self.weather = weather
        self.router = router
        self.today = Calendar.current.startOfDay(for: .now)
        events.onChange = { [weak self] in self?.reloadEvents() }
    }

    /// First launch: ask for calendar access, then load everything.
    func start() async {
        async let weatherLoad: Void = loadWeather()
        do {
            _ = try await events.requestAccess()
        } catch {
            accessState = .failed(error.localizedDescription)
        }
        reloadEvents()
        await weatherLoad
    }

    func refresh() async {
        reloadEvents()
        await loadWeather()
    }

    // MARK: - Days

    var selectedDay: Date { day(at: dayOffset) }

    func day(at offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    func select(offset: Int) {
        dayOffset = offset
    }

    /// Moves "today" forward if the date changed while the app was open (e.g. past midnight).
    /// Returns true when it did, so the view can scroll back to the new today.
    @discardableResult
    func rollOverIfNeeded(now: Date = .now) -> Bool {
        let start = calendar.startOfDay(for: now)
        guard start != today else { return false }
        today = start
        dayOffset = 0
        eventsByDay = [:]
        reloadEvents()
        return true
    }

    /// Events for `day`, or nil if they haven't been loaded yet.
    func events(on day: Date) -> [CalendarEvent]? {
        eventsByDay[calendar.startOfDay(for: day)]
    }

    /// Fetches `day` the first time its page appears.
    func loadEventsIfNeeded(for day: Date) {
        let key = calendar.startOfDay(for: day)
        guard accessState == .granted, eventsByDay[key] == nil else { return }
        eventsByDay[key] = events.events(on: key)
    }

    /// Re-fetches the selected day and its neighbours; farther pages reload when swiped back into view.
    func reloadEvents() {
        guard events.hasAccess else {
            if events.isAccessDenied { accessState = .denied }
            eventsByDay = [:]
            return
        }
        accessState = .granted
        eventsByDay = Dictionary(uniqueKeysWithValues: (-1...1).map { delta in
            let day = day(at: dayOffset + delta)
            return (day, events.events(on: day))
        })
    }

    func loadWeather() async {
        if case .loaded = weatherState {} else { weatherState = .loading }
        do {
            let here = try await location.currentLocation()
            weatherState = .loaded(try await weather.report(at: here))
        } catch {
            weatherState = .unavailable(error.localizedDescription)
        }
    }

    /// Refetches weather if it's older than `weatherMaxAge`, e.g. after the app sat in the background.
    func refreshWeatherIfStale(now: Date = .now) async {
        guard case .loaded(let report) = weatherState,
              now.timeIntervalSince(report.fetchedAt) > Self.weatherMaxAge else { return }
        await loadWeather()
    }

    /// Weather for `day`'s page, or nil for past days (no banner).
    func weather(for day: Date) -> DayWeather? {
        let key = calendar.startOfDay(for: day)
        guard key >= today else { return nil }

        switch weatherState {
        case .loading:
            return .loading
        case .unavailable(let reason):
            return .unavailable(reason)
        case .loaded(let report):
            if key == today {
                return .today(report.current, report.forecast(for: key), report.source)
            }
            if let forecast = report.forecast(for: key) {
                return .forecast(forecast, report.source)
            }
            return .notYetAvailable(lastForecastDay: report.lastForecastDay)
        }
    }

    /// Store for the in-app event editor; nil when events can't be created (no access, or demo data).
    var eventStoreForEditing: EKEventStore? {
        events.hasAccess ? events.eventStore : nil
    }

    /// Whether tapping `event` should open the editor.
    func canEdit(_ event: CalendarEvent) -> Bool {
        eventStoreForEditing != nil && event.isEditable
    }

    /// The EventKit event to hand the editor for `event`, or nil if it's gone or read-only.
    func occurrenceForEditing(_ event: CalendarEvent) -> EKEvent? {
        guard canEdit(event) else { return nil }
        return eventStoreForEditing?.occurrence(of: event)
    }

    /// Called when the event editor is dismissed. Reloads right away so a new, changed or
    /// deleted event shows up without waiting for the `EKEventStoreChanged` notification.
    func eventEditorDidFinish(_ action: EKEventEditViewAction) {
        if action != .canceled { reloadEvents() }
    }

    func navigate(to event: CalendarEvent, with app: NavigationApp) {
        guard let destination = event.destination else { return }
        Task {
            if await !router.navigate(to: destination, with: app) {
                navigationError = "Couldn't open \(app.accessibilityName)."
            }
        }
    }
}
