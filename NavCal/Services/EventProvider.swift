import EventKit
import SwiftUI
import UIKit

/// Source of today's events. `CalendarService` is the real implementation;
/// `SampleEventProvider` backs previews and the `-NavCalDemo` launch argument.
@MainActor
protocol EventProviding: AnyObject {
    var hasAccess: Bool { get }
    var isAccessDenied: Bool { get }
    func requestAccess() async throws -> Bool
    func events(on day: Date) -> [CalendarEvent]
    /// Called whenever the underlying calendar database changes.
    var onChange: (() -> Void)? { get set }
    /// Store used to create new events; nil when the provider isn't backed by EventKit.
    var eventStore: EKEventStore? { get }
}

/// Reads events from the device calendars via EventKit.
@MainActor
final class CalendarService: EventProviding {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    var onChange: (() -> Void)?
    var eventStore: EKEventStore? { store }

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Accounts switched on in Settings don't show up until sources are refreshed.
                self?.store.refreshSourcesIfNecessary()
                self?.onChange?()
            }
        }
    }

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var isAccessDenied: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted, .writeOnly: true
        default: false
        }
    }

    func requestAccess() async throws -> Bool {
        if hasAccess { return true }
        return try await store.requestFullAccessToEvents()
    }

    func events(on day: Date) -> [CalendarEvent] {
        guard hasAccess else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { lhs, rhs in
                // Timed events first in chronological order; all-day events last.
                if lhs.isAllDay != rhs.isAllDay { return !lhs.isAllDay }
                return lhs.compareStartDate(with: rhs) == .orderedAscending
            }
            .map(Self.makeEvent)
    }

    static func makeEvent(_ event: EKEvent) -> CalendarEvent {
        let rawLocation = event.location.map(LocationParser.normalize) ?? ""

        let destination: Destination?
        let source: CalendarEvent.LocationSource?
        if !rawLocation.isEmpty {
            destination = Destination(query: rawLocation, location: event.structuredLocation?.geoLocation)
            source = .calendar
        } else if let parsed = LocationParser.destination(in: [event.title, event.notes]) {
            destination = Destination(query: parsed)
            source = .parsed
        } else {
            destination = nil
            source = nil
        }

        return CalendarEvent(
            // Recurring occurrences share an identifier, so qualify it with the start date.
            id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
            title: event.title?.isEmpty == false ? event.title : "Untitled event",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            destination: destination,
            locationSource: source,
            calendarColor: event.calendar.map { Color(cgColor: $0.cgColor) }
        )
    }
}

/// Fixed sample schedule for SwiftUI previews and simulator demos.
@MainActor
final class SampleEventProvider: EventProviding {
    var hasAccess: Bool { true }
    var isAccessDenied: Bool { false }
    var onChange: (() -> Void)?
    var eventStore: EKEventStore? { nil }
    func requestAccess() async throws -> Bool { true }
    func events(on day: Date) -> [CalendarEvent] {
        Calendar.current.isDateInToday(day) ? CalendarEvent.samples : []
    }
}

extension EKEventStore {
    /// Event calendars the app can add events to (excludes holidays, birthdays, subscriptions).
    var writableEventCalendars: [EKCalendar] {
        calendars(for: .event).filter(\.allowsContentModifications)
    }

    /// Where new events go: the user's default calendar, else the first writable one.
    var calendarForNewEvents: EKCalendar? {
        defaultCalendarForNewEvents ?? writableEventCalendars.first
    }

    /// Synced accounts whose calendars are switched off on this device (e.g. Gmail with Calendars off).
    var accountsWithCalendarsOff: [String] {
        sources
            .filter { [.calDAV, .exchange].contains($0.sourceType) && $0.calendars(for: .event).isEmpty }
            .map(\.title)
    }

    /// Accounts that accept new calendars: "On My iPhone" and iCloud.
    /// Google and most other synced accounts refuse (EKErrorDomain code 17).
    private var calendarCreatingSources: [EKSource] {
        sources.filter { $0.sourceType == .local || ($0.sourceType == .calDAV && $0.title == "iCloud") }
            .sorted { $0.sourceType == .local && $1.sourceType != .local }
    }

    var canCreateCalendar: Bool { !calendarCreatingSources.isEmpty }

    enum CalendarCreationError: LocalizedError {
        case noAccount

        var errorDescription: String? {
            "This iPhone has no calendar account that NavCal can add a calendar to."
        }
    }

    /// Creates a "NavCal" calendar on this iPhone, or in iCloud if there's no local account.
    @discardableResult
    func createNavCalCalendar() throws -> EKCalendar {
        var lastError: Error = CalendarCreationError.noAccount
        for source in calendarCreatingSources {
            let calendar = EKCalendar(for: .event, eventStore: self)
            calendar.title = "NavCal"
            calendar.source = source
            calendar.cgColor = UIColor.systemBlue.cgColor
            do {
                try saveCalendar(calendar, commit: true)
                return calendar
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

/// What to tell the user when there's no calendar that new events can be saved to.
struct CalendarSetupPrompt: Equatable {
    /// Synced accounts with Calendars switched off, e.g. ["Gmail"].
    let accountsWithCalendarsOff: [String]
    /// Whether NavCal can create its own calendar on this device.
    let canCreateCalendar: Bool

    init(accountsWithCalendarsOff: [String], canCreateCalendar: Bool) {
        self.accountsWithCalendarsOff = accountsWithCalendarsOff
        self.canCreateCalendar = canCreateCalendar
    }

    init(store: EKEventStore) {
        self.init(accountsWithCalendarsOff: store.accountsWithCalendarsOff, canCreateCalendar: store.canCreateCalendar)
    }

    var message: String {
        let path = "Settings \u{2192} Apps \u{2192} Calendar \u{2192} Calendar Accounts"
        var text: String
        if let account = accountsWithCalendarsOff.first {
            let names = ListFormatter.localizedString(byJoining: accountsWithCalendarsOff)
            text = "Calendars are turned off for your \(names) account on this iPhone, so there\u{2019}s nowhere to save new events. "
                + "Go to \(path) \u{2192} \(account), turn on Calendars, then tap + again."
        } else {
            text = "This iPhone has no calendar that new events can be saved to. "
                + "Turn on Calendars for iCloud or another account in \(path), then tap + again."
        }
        if canCreateCalendar {
            text += " Or NavCal can create a \u{201C}NavCal\u{201D} calendar on this iPhone."
        }
        return text
    }
}
