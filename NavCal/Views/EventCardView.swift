import SwiftUI

/// One stop on a day's timeline: a rail marker on the left, the event card on the right.
struct EventRowView: View {
    let event: CalendarEvent
    let now: Date
    let isNext: Bool
    /// The last row doesn't draw the rail line down to the next one.
    let isLast: Bool
    var onEdit: (() -> Void)? = nil
    let onNavigate: (NavigationApp) -> Void

    private static let railWidth: CGFloat = 18

    var body: some View {
        EventCardView(event: event, now: now, isNext: isNext, onEdit: onEdit, onNavigate: onNavigate)
            .padding(.leading, Self.railWidth + 10)
            .padding(.bottom, isLast ? 0 : 14)
            .overlay(alignment: .topLeading) { rail }
    }

    private var rail: some View {
        VStack(spacing: 6) {
            TimelineMarker(status: event.status(at: now), isNext: isNext, color: event.calendarColor ?? .accentColor)
                .frame(width: Self.railWidth, height: Self.railWidth)
                .padding(.top, 22)
            if !isLast {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: Self.railWidth)
        .accessibilityHidden(true)
    }
}

/// The dot on the timeline rail: pulsing while the event is on, a check once it's over.
private struct TimelineMarker: View {
    let status: CalendarEvent.Status
    let isNext: Bool
    let color: Color

    var body: some View {
        switch status {
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        case .inProgress:
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.25))
                    .phaseAnimator([1.0, 1.6]) { circle, scale in
                        circle.scaleEffect(scale).opacity(2 - scale)
                    } animation: { _ in .easeInOut(duration: 1.2) }
                Circle().fill(Color.accentColor).frame(width: 10, height: 10)
            }
        case .upcoming:
            Circle()
                .strokeBorder(color, lineWidth: 3)
                .background(Circle().fill(isNext ? color : .clear).padding(3))
                .frame(width: 14, height: 14)
        }
    }
}

/// One event: time, title, destination and one-tap navigation buttons.
/// When `onEdit` is set, the pencil button or a tap anywhere outside the navigation buttons
/// edits the event.
struct EventCardView: View {
    let event: CalendarEvent
    let now: Date
    let isNext: Bool
    var onEdit: (() -> Void)? = nil
    let onNavigate: (NavigationApp) -> Void

    private var status: CalendarEvent.Status { event.status(at: now) }
    private var tint: Color { event.calendarColor ?? .accentColor }
    /// The next or current stop gets the solid navigation buttons.
    private var isFeatured: Bool { isNext || (status == .inProgress && !event.isAllDay) }
    private static let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                timeBlock
                Spacer(minLength: 4)
                badge
                editButton
            }

            Text(event.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            locationRow

            actions
        }
        .padding(16)
        .background {
            Self.shape
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    // A wash of the calendar's color from the top corner.
                    Self.shape.fill(LinearGradient(
                        colors: [tint.opacity(0.16), .clear],
                        startPoint: .topLeading, endPoint: UnitPoint(x: 0.6, y: 0.6)
                    ))
                }
                .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        }
        .overlay {
            if status == .inProgress {
                Self.shape.strokeBorder(
                    LinearGradient(colors: [.accentColor, .accentColor.opacity(0.3)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5
                )
            } else {
                Self.shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .opacity(status == .finished ? 0.55 : 1)
        .contentShape(Self.shape)
        .onTapGesture { onEdit?() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("event-card")
    }

    // MARK: - Time

    @ViewBuilder
    private var timeBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            if event.isAllDay {
                Text("All day")
                    .font(.system(.title2, design: .rounded, weight: .bold))
            } else {
                Text(startText)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text(untilText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .minimumScaleFactor(0.8)
        .lineLimit(1)
    }

    private var spansDays: Bool {
        !Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate.addingTimeInterval(-1))
    }

    private var startText: String {
        spansDays
            ? event.startDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            : event.startDate.formatted(date: .omitted, time: .shortened)
    }

    /// "until 1:00 PM · 1h"
    private var untilText: String {
        let end = spansDays
            ? event.endDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            : event.endDate.formatted(date: .omitted, time: .shortened)
        return "until \(end) · \(Self.shortDuration(event.endDate.timeIntervalSince(event.startDate)))"
    }

    /// "1h 20m", rounded up to the minute.
    private static func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded(.up)))
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    @ViewBuilder
    private var badge: some View {
        if status == .inProgress, !event.isAllDay {
            BadgeView(text: "Now · \(Self.shortDuration(event.endDate.timeIntervalSince(now))) left",
                      color: .accentColor)
        } else if isNext {
            BadgeView(text: "In \(Self.shortDuration(event.startDate.timeIntervalSince(now)))", color: .orange)
        } else if status == .finished {
            BadgeView(text: "Done", color: .secondary)
        }
    }

    @ViewBuilder
    private var editButton: some View {
        if let onEdit {
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit Event")
        }
    }

    // MARK: - Location and actions

    @ViewBuilder
    private var locationRow: some View {
        if let destination = event.destination {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.query)
                        .font(.subheadline)
                        .textSelection(.enabled)
                    if event.locationSource == .parsed {
                        Label("Detected from event title", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 5)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if event.destination != nil {
            HStack(spacing: 8) {
                ForEach(NavigationApp.allCases) { app in
                    NavigationButton(app: app, isProminent: isFeatured) { onNavigate(app) }
                }
            }
        } else if let onEdit {
            Button(action: onEdit) {
                Label("Add a location", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(Color.accentColor)
                    .background {
                        Capsule().strokeBorder(Color.accentColor.opacity(0.5),
                                               style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
            }
            .buttonStyle(.borderless)
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
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
            .fixedSize()
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 0) {
            ForEach(Array(CalendarEvent.samples.enumerated()), id: \.element.id) { index, event in
                EventRowView(event: event, now: .now, isNext: index == 1,
                             isLast: index == CalendarEvent.samples.count - 1, onEdit: {}) { _ in }
            }
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
