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
        XCTAssertTrue(scrollTo(app.staticTexts[title], in: app), "New event did not appear after saving")

        // 3. The location was parsed from the title, so navigation is enabled.
        XCTAssertTrue(app.staticTexts[store].exists, "Expected parsed destination \(store)")

        // Use this card's own Waze button, scrolling it into view if the day is busy.
        let newCard = app.descendants(matching: .any).matching(identifier: "event-card")
            .containing(.staticText, identifier: title).firstMatch
        let waze = newCard.buttons["Navigate with Waze"]
        XCTAssertTrue(scrollTo(waze, in: app), "New event's Waze button never came on screen")
        XCTAssertTrue(waze.isEnabled)

        // 4. Waze isn't installed in the simulator, so the web fallback opens in Safari.
        waze.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10), "Waze link did not open")
    }

    /// Create an event, rename it from its card's edit button, then delete it from the editor.
    @MainActor
    func testEditThenDeleteEvent() {
        let app = XCUIApplication()
        app.launch()

        let original = "Edit me \(Int.random(in: 100...999))"
        let renamed = "\(original) renamed"

        let plus = app.buttons["New Event"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10), "+ button missing — is calendar access granted?")
        plus.tap()
        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Event editor did not appear")
        titleField.tap()
        titleField.typeText(original)
        saveButton(in: app).tap()
        XCTAssertTrue(scrollTo(app.staticTexts[original], in: app), "New event did not appear")

        // 1. The card's pencil opens the editor on the existing event.
        let card = app.descendants(matching: .any).matching(identifier: "event-card")
            .containing(.staticText, identifier: original).firstMatch
        let edit = card.buttons["Edit Event"]
        XCTAssertTrue(scrollTo(edit, in: app), "Edit button never came on screen")
        edit.tap()

        let editTitle = app.textFields["Title"]
        XCTAssertTrue(editTitle.waitForExistence(timeout: 5), "Editor did not open for existing event")
        XCTAssertEqual(editTitle.value as? String, original)
        editTitle.tap()
        editTitle.typeText(" renamed")
        attachScreenshot(named: "Editing")
        saveButton(in: app).tap()

        // 2. The card shows the new title right away.
        XCTAssertTrue(scrollTo(app.staticTexts[renamed], in: app), "Edited title did not appear")
        XCTAssertFalse(app.staticTexts[original].exists)

        // 3. Delete it from the editor so runs don't pile up in the simulator calendar.
        let renamedCard = app.descendants(matching: .any).matching(identifier: "event-card")
            .containing(.staticText, identifier: renamed).firstMatch
        let editAgain = renamedCard.buttons["Edit Event"]
        XCTAssertTrue(scrollTo(editAgain, in: app))
        editAgain.tap()
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 5))
        // The editor's delete control is a table cell at the bottom, not a button.
        let delete = app.cells["delete-event-cell"]
        XCTAssertTrue(scrollTo(delete, in: app), "Delete Event row never came on screen")
        // A tap while the list is still decelerating only stops the scroll.
        sleep(1)
        delete.tap()
        let confirm = app.sheets.buttons["delete-alert-button"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete confirmation did not appear")
        confirm.tap()
        XCTAssertTrue(app.staticTexts[renamed].waitForNonExistence(timeout: 5), "Deleted event still listed")
    }

    /// Swipes up until `element` is on screen. Cards sit in a lazy stack, so ones far down a busy
    /// day (e.g. left over from earlier runs) don't exist in the hierarchy until scrolled to.
    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 12) -> Bool {
        if element.waitForExistence(timeout: 3), element.isHittable { return true }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.exists, element.isHittable { return true }
        }
        return false
    }

    /// Save button: id "add-button" up to iOS 26; no id and label "Done" (or "Add") on iOS 27.
    @MainActor
    private func saveButton(in app: XCUIApplication) -> XCUIElement {
        let save = app.buttons.matching(
            NSPredicate(format: "identifier == 'add-button' OR label == 'Done' OR label == 'Add'")
        ).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Save button not found in editor")
        return save
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
