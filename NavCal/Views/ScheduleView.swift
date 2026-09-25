import SwiftUI

/// The app's single screen: one swipeable page per day, each listing that day's event cards.
/// Swipe left for the next day, right for the previous one. Tap a card to edit its event.
struct ScheduleView: View {
    /// How far the pager reaches either side of today.
    static let dayRange = -365...365

    @Bindable var viewModel: ScheduleViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var eventEditor = EventEditorPresenter()
    @State private var calendarSetupPrompt: CalendarSetupPrompt?
    @State private var calendarSetupError: String?
    @State private var page: Int? = 0

    var body: some View {
        NavigationStack {
            content
                .background { PageBackground() }
                .navigationTitle(viewModel.selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .toolbar {
                    if case .granted = viewModel.accessState {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                viewModel.navigateHome()
                            } label: {
                                Image(systemName: "house.fill")
                            }
                            .accessibilityLabel("Navigate Home")
                        }
                    }
                    if viewModel.dayOffset != 0 {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Today") {
                                withAnimation { page = 0 }
                            }
                        }
                    }
                    if viewModel.eventStoreForEditing != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                createEvent()
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("New Event")
                        }
                    }
                }
        }
        .task { await viewModel.start() }
        .onChange(of: page) { _, newPage in
            viewModel.select(offset: newPage ?? 0)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if viewModel.rollOverIfNeeded() {
                page = 0
            } else {
                viewModel.reloadEvents()
            }
            Task { await viewModel.refreshWeatherIfStale() }
        }
        .sensoryFeedback(.selection, trigger: viewModel.dayOffset)
        .alert(
            "No Calendar to Save To",
            isPresented: Binding(
                get: { calendarSetupPrompt != nil },
                set: { if !$0 { calendarSetupPrompt = nil } }
            ),
            presenting: calendarSetupPrompt
        ) { prompt in
            if prompt.canCreateCalendar {
                Button("Create NavCal Calendar") { createNavCalCalendarThenEvent() }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { prompt in
            Text(prompt.message)
        }
        .alert(
            "Couldn't Create a Calendar",
            isPresented: Binding(
                get: { calendarSetupError != nil },
                set: { if !$0 { calendarSetupError = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: {
                Text("\(calendarSetupError ?? "") Turn on Calendars for iCloud or another account in Settings \u{2192} Apps \u{2192} Calendar \u{2192} Calendar Accounts, then tap + again.")
            }
        )
        .alert(
            "Navigation Unavailable",
            isPresented: Binding(
                get: { viewModel.navigationError != nil },
                set: { if !$0 { viewModel.navigationError = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(viewModel.navigationError ?? "") }
        )
    }

    private func createEvent() {
        guard let store = viewModel.eventStoreForEditing else { return }
        // Pick up accounts or calendars switched on in Settings since the store was created.
        store.refreshSourcesIfNecessary()
        // The system editor cancels itself immediately when there's nowhere to save,
        // so offer to create a calendar first.
        guard !store.writableEventCalendars.isEmpty else {
            calendarSetupPrompt = CalendarSetupPrompt(store: store)
            return
        }
        eventEditor.present(store: store, day: viewModel.selectedDay) { action in
            viewModel.eventEditorDidFinish(action)
        }
    }

    private func edit(_ event: CalendarEvent) {
        guard let store = viewModel.eventStoreForEditing else { return }
        guard let occurrence = viewModel.occurrenceForEditing(event) else {
            // Deleted or moved elsewhere since the page loaded.
            viewModel.reloadEvents()
            return
        }
        eventEditor.present(store: store, event: occurrence) { action in
            viewModel.eventEditorDidFinish(action)
        }
    }

    private func createNavCalCalendarThenEvent() {
        guard let store = viewModel.eventStoreForEditing else { return }
        do {
            try store.createNavCalCalendar()
            createEvent()
        } catch {
            calendarSetupError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.accessState {
        case .loading:
            ProgressView("Loading your schedule…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .denied:
            ContentUnavailableView {
                Label("Calendar Access Needed", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("Allow full calendar access in Settings so NavCal can show your events.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
            }

        case .failed(let message):
            ContentUnavailableView("Couldn't Load Calendar", systemImage: "exclamationmark.triangle",
                                   description: Text(message))

        case .granted:
            pager
        }
    }

    private var pager: some View {
        // Re-render every minute so "Now"/"Next"/"Done" badges stay current.
        TimelineView(.everyMinute) { context in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Self.dayRange, id: \.self) { offset in
                        DayPageView(
                            viewModel: viewModel,
                            day: viewModel.day(at: offset),
                            isToday: offset == 0,
                            now: context.date,
                            onEdit: edit
                        )
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .scrollIndicators(.hidden)
        }
    }
}

/// One day's page: that day's weather and event cards.
private struct DayPageView: View {
    let viewModel: ScheduleViewModel
    let day: Date
    let isToday: Bool
    let now: Date
    let onEdit: (CalendarEvent) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let weather = viewModel.weather(for: day) {
                    WeatherHeaderView(weather: weather)
                }
                events
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .refreshable { await viewModel.refresh() }
        .task(id: day) { viewModel.loadEventsIfNeeded(for: day) }
    }

    @ViewBuilder
    private var events: some View {
        if let events = viewModel.events(on: day) {
            if events.isEmpty {
                ContentUnavailableView(
                    "Nothing Scheduled", systemImage: "calendar",
                    description: Text(isToday
                        ? "You have no events today. Pull down to refresh."
                        : "No events on \(day.formatted(.dateTime.weekday(.wide))).")
                )
            } else {
                // "Next" only means something on today's page.
                let nextID = isToday
                    ? events.first { !$0.isAllDay && $0.status(at: now) == .upcoming }?.id
                    : nil
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Schedule").font(.title3.bold())
                        Spacer()
                        Text(events.count == 1 ? "1 event" : "\(events.count) events")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    LazyVStack(spacing: 0) {
                        ForEach(events) { event in
                            EventRowView(
                                event: event, now: now, isNext: event.id == nextID,
                                isLast: event.id == events.last?.id,
                                onEdit: viewModel.canEdit(event) ? { onEdit(event) } : nil
                            ) { app in
                                viewModel.navigate(to: event, with: app)
                            }
                        }
                    }
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        }
    }
}

/// Grouped background with a soft glow of the app icon's blues behind the top of the page.
private struct PageBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.23, blue: 0.54).opacity(0.45),
                         Color(red: 0.05, green: 0.65, blue: 0.91).opacity(0.12),
                         .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 420)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ScheduleView(viewModel: ScheduleViewModel(
        events: SampleEventProvider(),
        location: LocationService(),
        weather: MockWeatherProvider(),
        router: NavigationRouter()
    ))
}
