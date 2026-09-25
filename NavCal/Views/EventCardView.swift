import SwiftUI

/// One event: title, time range, destination and one-tap navigation buttons.
struct EventCardView: View {
    let event: CalendarEvent
    let now: Date
    let isNext: Bool
    let onNavigate: (NavigationApp) -> Void

    private var status: CalendarEvent.Status { event.status(at: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(event.calendarColor ?? .accentColor)
                    .frame(width: 10, height: 10)
                Text(event.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                badge
            }

            Label(timeRange, systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            locationRow

            HStack(spacing: 8) {
                ForEach(NavigationApp.allCases) { app in
                    NavigationButton(app: app) { onNavigate(app) }
                }
            }
            .disabled(event.destination == nil)
            .opacity(event.destination == nil ? 0.4 : 1)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if status == .inProgress {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .opacity(status == .finished ? 0.6 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("event-card")
    }

    private var timeRange: String {
        if event.isAllDay { return "All day" }
        return (event.startDate..<event.endDate).formatted(.interval.hour().minute())
    }

    @ViewBuilder
    private var badge: some View {
        if status == .inProgress, !event.isAllDay {
            BadgeView(text: "NOW", color: .accentColor)
        } else if isNext {
            BadgeView(text: "NEXT", color: .orange)
        } else if status == .finished {
            BadgeView(text: "DONE", color: .secondary)
        }
    }

    @ViewBuilder
    private var locationRow: some View {
        if let destination = event.destination {
            VStack(alignment: .leading, spacing: 2) {
                Label(destination.query, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .textSelection(.enabled)
                if event.locationSource == .parsed {
                    Text("Detected from event title")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                }
            }
        } else {
            Label("No location", systemImage: "mappin.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

#Preview {
    VStack {
        ForEach(CalendarEvent.samples) { event in
            EventCardView(event: event, now: .now, isNext: false) { _ in }
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
