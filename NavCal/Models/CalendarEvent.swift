import SwiftUI

/// A calendar event reduced to what the dashboard needs.
struct CalendarEvent: Identifiable, Hashable, Sendable {
    /// How the event's destination was determined.
    enum LocationSource: Hashable, Sendable {
        /// The event's own `location` field.
        case calendar
        /// Inferred from the title or notes by `LocationParser`.
        case parsed
    }

    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let destination: Destination?
    let locationSource: LocationSource?
    let calendarColor: Color?

    func status(at now: Date) -> Status {
        if endDate <= now { return .finished }
        if startDate <= now { return .inProgress }
        return .upcoming
    }

    enum Status: Sendable {
        case finished, inProgress, upcoming
    }
}

extension CalendarEvent {
    static let samples: [CalendarEvent] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(byAdding: DateComponents(hour: hour, minute: minute), to: today)!
        }
        return [
            CalendarEvent(id: "1", title: "Reset – Safeway 555", startDate: at(7), endDate: at(9, 30),
                          isAllDay: false, destination: Destination(query: "Safeway 555"),
                          locationSource: .parsed, calendarColor: .green),
            CalendarEvent(id: "2", title: "Merch visit", startDate: at(10), endDate: at(12),
                          isAllDay: false,
                          destination: Destination(query: "Fred Meyer, 3805 SE Hawthorne Blvd, Portland, OR"),
                          locationSource: .calendar, calendarColor: .blue),
            CalendarEvent(id: "3", title: "Team call", startDate: at(13), endDate: at(13, 30),
                          isAllDay: false, destination: nil, locationSource: nil, calendarColor: .orange),
        ]
    }()
}
