import EventKitUI
import Testing
@testable import NavCal

/// Covers the pieces of in-app event creation that don't need the system editor UI.
@MainActor
struct EventCreationTests {
    private let store = EKEventStore()

    @Test func draftEventForTodayStartsAtNextFullHourForOneHour() throws {
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 14, minute: 37)))
        let draft = EventEditorPresenter.draftEvent(in: store, on: now, now: now)
        let parts = Calendar.current.dateComponents([.day, .hour, .minute], from: draft.startDate)
        #expect(parts.day == 24 && parts.hour == 15 && parts.minute == 0)
        #expect(draft.endDate.timeIntervalSince(draft.startDate) == 3600)
    }

    @Test func draftEventForAnotherDayStartsAt9AM() throws {
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 14, minute: 37)))
        let friday = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 25)))
        let draft = EventEditorPresenter.draftEvent(in: store, on: friday, now: now)
        let parts = Calendar.current.dateComponents([.day, .hour, .minute], from: draft.startDate)
        #expect(parts.day == 25 && parts.hour == 9 && parts.minute == 0)
    }

    @Test func newEventWithLocationFieldRoutesToThatAddress() {
        let event = makeEvent(title: "Merch visit", location: "3805 SE Hawthorne Blvd\nPortland, OR")
        let mapped = CalendarService.makeEvent(event)
        #expect(mapped.locationSource == .calendar)
        #expect(mapped.destination?.query == "3805 SE Hawthorne Blvd, Portland, OR")

        let waze = NavigationRouter.links(for: mapped.destination!, app: .waze)
        #expect(waze.native?.absoluteString
            == "waze://?q=3805%20SE%20Hawthorne%20Blvd%2C%20Portland%2C%20OR&navigate=yes")
    }

    @Test func newEventWithoutLocationFallsBackToTitleParser() {
        let mapped = CalendarService.makeEvent(makeEvent(title: "Reset – Safeway 555", location: nil))
        #expect(mapped.locationSource == .parsed)
        #expect(mapped.destination?.query == "Safeway 555")

        let google = NavigationRouter.links(for: mapped.destination!, app: .googleMaps)
        #expect(google.native?.absoluteString == "comgooglemaps://?daddr=Safeway%20555&directionsmode=driving")
    }

    @Test func mappedEventKeepsIdentifierForEditing() {
        let event = makeEvent(title: "Merch visit", location: nil)
        let mapped = CalendarService.makeEvent(event)
        #expect(mapped.eventIdentifier == event.eventIdentifier)
        // Unsaved test events have no calendar, so there's nothing to save edits to.
        #expect(!mapped.isEditable)
    }

    @Test func sampleEventsAreNotEditable() {
        let viewModel = makeViewModel(CountingProvider())
        #expect(CalendarEvent.samples.allSatisfy { !viewModel.canEdit($0) })
        #expect(viewModel.occurrenceForEditing(CalendarEvent.samples[0]) == nil)
    }

    @Test func deletingReloadsSchedule() {
        let provider = CountingProvider()
        let viewModel = makeViewModel(provider)
        viewModel.eventEditorDidFinish(.deleted)
        #expect(Set(provider.fetchedDays) == [viewModel.day(at: -1), viewModel.today, viewModel.day(at: 1)])
    }

    @Test func savingReloadsScheduleButCancelingDoesNot() {
        let provider = CountingProvider()
        let viewModel = makeViewModel(provider)

        viewModel.eventEditorDidFinish(.canceled)
        #expect(provider.fetchedDays.isEmpty)

        viewModel.eventEditorDidFinish(.saved)
        #expect(Set(provider.fetchedDays) == [viewModel.day(at: -1), viewModel.today, viewModel.day(at: 1)])
        #expect(viewModel.events(on: viewModel.today) == CalendarEvent.samples)
    }

    @Test func selectingNextDayShowsFridayAndLoadsItOnce() throws {
        let provider = CountingProvider()
        let viewModel = makeViewModel(provider)
        viewModel.reloadEvents()

        viewModel.select(offset: 1)
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: viewModel.today))
        #expect(viewModel.selectedDay == tomorrow)

        // Neighbouring days were preloaded, so showing tomorrow doesn't fetch again.
        provider.fetchedDays = []
        viewModel.loadEventsIfNeeded(for: tomorrow)
        #expect(provider.fetchedDays.isEmpty)

        // A day farther out is fetched the first time its page appears, then cached.
        let nextWeek = viewModel.day(at: 7)
        viewModel.loadEventsIfNeeded(for: nextWeek)
        viewModel.loadEventsIfNeeded(for: nextWeek)
        #expect(provider.fetchedDays == [nextWeek])
    }

    @Test func rollOverResetsToNewToday() throws {
        let viewModel = makeViewModel(CountingProvider())
        viewModel.select(offset: 3)
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))

        #expect(viewModel.rollOverIfNeeded(now: tomorrow))
        #expect(viewModel.dayOffset == 0)
        #expect(viewModel.today == Calendar.current.startOfDay(for: tomorrow))
        #expect(!viewModel.rollOverIfNeeded(now: tomorrow))
    }

    @Test func calendarPromptNamesTheAccountWithCalendarsOff() {
        let prompt = CalendarSetupPrompt(accountsWithCalendarsOff: ["Gmail"], canCreateCalendar: false)
        #expect(prompt.message.contains("turned off for your Gmail account"))
        #expect(prompt.message.contains("Calendar Accounts \u{2192} Gmail, turn on Calendars"))
        #expect(!prompt.message.contains("NavCal can create"))
    }

    @Test func calendarPromptOffersNavCalCalendarWhenPossible() {
        let prompt = CalendarSetupPrompt(accountsWithCalendarsOff: [], canCreateCalendar: true)
        #expect(prompt.message.contains("no calendar that new events can be saved to"))
        #expect(prompt.message.hasSuffix("NavCal can create a \u{201C}NavCal\u{201D} calendar on this iPhone."))
    }

    private func makeViewModel(_ provider: CountingProvider) -> ScheduleViewModel {
        ScheduleViewModel(
            events: provider, location: LocationService(),
            weather: MockWeatherProvider(), router: NavigationRouter(opener: NoopOpener())
        )
    }

    private func makeEvent(title: String, location: String?) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.location = location
        event.startDate = .now
        event.endDate = .now.addingTimeInterval(3600)
        return event
    }
}

@MainActor
private final class CountingProvider: EventProviding {
    var fetchedDays: [Date] = []
    var hasAccess: Bool { true }
    var isAccessDenied: Bool { false }
    var onChange: (() -> Void)?
    var eventStore: EKEventStore? { nil }
    func requestAccess() async throws -> Bool { true }
    func events(on day: Date) -> [CalendarEvent] {
        fetchedDays.append(day)
        return CalendarEvent.samples
    }
}

@MainActor
private struct NoopOpener: URLOpening {
    func canOpenURL(_ url: URL) -> Bool { false }
    func open(_ url: URL) async -> Bool { false }
}
