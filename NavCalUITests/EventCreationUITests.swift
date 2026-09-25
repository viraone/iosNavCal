import XCTest

/// End-to-end: create an event with the in-app "+" editor, see it appear, then launch Waze.
///
/// Calendar access must already be granted, e.g.:
///   xcrun simctl privacy booted grant calendar com.navcal.NavCal
final class EventCreationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateEventThenNavigateWithWaze() {
        let app = XCUIApplication()
        app.launch()

        // Random store number keeps runs distinguishable in the simulator calendar.
        let store = "Safeway \(Int.random(in: 100...999))"
        let title = "Reset \(store)"

        // 1. Open the system event editor from the toolbar.
        let plus = app.buttons["New Event"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10), "+ button missing — is calendar access granted?")
        plus.tap()

        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Event editor did not appear")
        titleField.tap()
        titleField.typeText(title)
        // Save button: id "add-button" up to iOS 26; no id and label "Done" (or "Add") on iOS 27.
        let save = app.buttons.matching(
            NSPredicate(format: "identifier == 'add-button' OR label == 'Done' OR label == 'Add'")
        ).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Save button not found in editor")
        save.tap()

        // 2. The sheet closes and the new event is listed without pulling to refresh.
        let card = app.staticTexts[title]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "New event did not appear after saving")

        // 3. The location was parsed from the title, so navigation is enabled.
        XCTAssertTrue(app.staticTexts[store].exists, "Expected parsed destination \(store)")

        // Use this card's own Waze button, scrolling it into view if the day is busy.
        let newCard = app.descendants(matching: .any).matching(identifier: "event-card")
            .containing(.staticText, identifier: title).firstMatch
        let waze = newCard.buttons["Navigate with Waze"]
        var scrolls = 0
        while !waze.isHittable && scrolls < 8 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(waze.isHittable, "New event's Waze button never came on screen")
        XCTAssertTrue(waze.isEnabled)

        // 4. Waze isn't installed in the simulator, so the web fallback opens in Safari.
        waze.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10), "Waze link did not open")
    }

    @MainActor
    func testSwipeLeftShowsNextDayAndTodayReturns() throws {
        let app = XCUIApplication()
        app.launch()

        let calendar = Calendar.current
        let format = Date.FormatStyle.dateTime.weekday(.wide).month(.abbreviated).day()
        let todayTitle = Date.now.formatted(format)
        let tomorrowTitle = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: .now)).formatted(format)
        let yesterdayTitle = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: .now)).formatted(format)

        // Starts on today, with the weather header that only today's page has.
        XCTAssertTrue(app.navigationBars[todayTitle].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["weather-header"].firstMatch.isHittable)
        XCTAssertFalse(app.buttons["Today"].exists)

        attachScreenshot(named: "Today")

        // Swipe left -> tomorrow, which shows its own forecast banner.
        app.swipeLeft()
        XCTAssertTrue(app.navigationBars[tomorrowTitle].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["weather-header"].firstMatch.waitForExistence(timeout: 5))
        attachScreenshot(named: "Tomorrow")
        XCTAssertTrue(app.buttons["Today"].exists)

        // "Today" jumps back.
        app.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars[todayTitle].waitForExistence(timeout: 5))

        // Swipe right -> yesterday.
        app.swipeRight()
        XCTAssertTrue(app.navigationBars[yesterdayTitle].waitForExistence(timeout: 5))
    }

    /// Keeps a screenshot in the test results for visual review.
    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
