# NavCal

Today's calendar events as cards, each with one-tap navigation to **Waze**, **Google Maps** or **Apple Maps**. Built for gig workers who hop between stores and stops.

## Requirements

- Xcode 16+ (tested with Xcode 27 / Swift 6), iOS 17+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) only if you change `project.yml` (`brew install xcodegen && xcodegen generate`)

## Run

1. Open `NavCal.xcodeproj`, select the **NavCal** scheme, and run.
2. Tap **+** in the top bar to add an event with the standard iOS editor. It appears in the list as soon as you save. To see a sample schedule instead, add `-NavCalDemo` under *Edit Scheme → Run → Arguments*. Demo mode hides **+**.
3. To test the weather header, set a location in the simulator (*Features → Location*).
4. Run tests with ⌘U. The unit tests cover the location parser, URL construction and event creation. The UI test (`NavCalUITests`) creates an event through **+** and taps Waze. It needs calendar access granted first: `xcrun simctl privacy booted grant calendar com.navcal.NavCal`. The manual QA procedure is in [docs/QA-event-creation.md](docs/QA-event-creation.md).

## Project layout

```
NavCal/
├── App/NavCalApp.swift              Entry point; wires services into the view model
├── Models/
│   ├── CalendarEvent.swift          Event model + sample data
│   ├── Destination.swift            Query string + optional coordinates
│   ├── NavigationApp.swift          Waze / Google Maps / Apple Maps metadata
│   └── WeatherReport.swift          Current conditions + daily forecast
├── Services/
│   ├── EventProvider.swift          EventKit CalendarService + SampleEventProvider
│   ├── LocationParser.swift         Fallback destination extraction from title/notes
│   ├── LocationService.swift        One-shot CoreLocation fix
│   ├── NavigationRouter.swift       Deep links, percent-encoding, web fallback
│   ├── OpenMeteoProvider.swift      Free forecast source used when WeatherKit is unavailable
│   └── WeatherProvider.swift        WeatherKit, mock, and fallback providers
├── ViewModels/ScheduleViewModel.swift
├── Views/                           ScheduleView, EventCardView, EventEditorPresenter (EKEventEditViewController),
│                                    WeatherHeaderView, NavigationButton
└── Resources/                       Info.plist, entitlements, assets
```

## How it works

**Calendar.** On launch the app requests full calendar access (`requestFullAccessToEvents`). It then loads the day's events: timed events in chronological order, all-day events last. Swipe left to see the next day and right to see the previous one, up to a year either way. When you're not on today, a **Today** button in the top bar brings you back. Weather and the **NEXT** badge appear only on today's page. The **+** editor defaults to the day you're viewing: the next full hour for today, 9 AM for any other day. The list reloads when the calendar database changes and when the app returns to the foreground. Cards are labeled **NOW**, **NEXT** and **DONE** based on the current time.

**Finding a destination.** The app tries these in order:
1. The event's `location` field. If the calendar also stores coordinates (`structuredLocation.geoLocation`), the app routes to those.
2. A street address in the title or notes, found by `NSDataDetector`.
3. A store name followed by a store number, found by regex: `Safeway 555`, `Reset – Fred Meyer 658`, `Visit Safeway #1234`, and `WinCo Foods Store 12` all work. Leading task words ("Reset", "Merch", "Pickup at", …) are removed. Matches like "Shift 12", "Route 66" and "10:30" are ignored.

Cards whose destination came from the parser show "Detected from event title". Cards with no destination have their buttons disabled.

**Navigation.** `NavigationRouter` builds each link and URL-encodes every parameter value. Only the RFC 3986 unreserved characters (letters, digits, `-`, `.`, `_`, `~`) are left as-is, so `&`, `#`, `+` and `,` inside an address can't break the query string.

| App | Native | Fallback |
|---|---|---|
| Waze | `waze://?q=…&navigate=yes` (or `ll=lat,lon`) | `https://waze.com/ul?q=…&navigate=yes` |
| Google Maps | `comgooglemaps://?daddr=…&directionsmode=driving` | `https://www.google.com/maps/dir/?api=1&destination=…` |
| Apple Maps | — | `http://maps.apple.com/?daddr=…&dirflg=d` (iOS opens Maps directly) |

**Weather.** Each day's page has its own weather banner. Today's page shows current conditions (night icons after dark) plus today's high, low and chance of rain. Future pages show that day's forecast, up to 16 days ahead; past days show no banner. The app uses Apple WeatherKit when it's set up (see below), otherwise [Open-Meteo](https://open-meteo.com), which is free and needs no account. Only a location rounded to about 1 km is sent. Open-Meteo's free tier is for non-commercial use, so a commercial App Store release needs WeatherKit or a paid Open-Meteo plan. Weather refreshes when the app comes back to the front after 30 minutes. `-NavCalDemo` uses sample weather marked **Sample**.

## Info.plist keys

These are already in `NavCal/Resources/Info.plist`:

| Key | Purpose |
|---|---|
| `NSCalendarsFullAccessUsageDescription` | Required on iOS 17+ for `requestFullAccessToEvents()`. Without it, the app crashes when requesting access. |
| `NSCalendarsUsageDescription` | Legacy calendar key for earlier iOS versions |
| `NSLocationWhenInUseUsageDescription` | Location for the weather header |
| `LSApplicationQueriesSchemes` = `waze`, `comgooglemaps` | Lets `canOpenURL` check whether those apps are installed. Without it, the check always returns false and the app always uses the web fallback. |

## Enabling live WeatherKit

WeatherKit requires a paid Apple Developer account.

1. In the developer portal, open your App ID and enable **WeatherKit** under *Capabilities* and *App Services*. It can take about 30 minutes to become active.
2. In `project.yml`, uncomment `DEVELOPMENT_TEAM` (set your team ID) and `CODE_SIGN_ENTITLEMENTS`, then run `xcodegen generate`. Alternatively, add the WeatherKit capability in Xcode's *Signing & Capabilities* tab.
3. Run on a device. The banner's credit changes from "Open-Meteo" to the required Apple Weather link.
