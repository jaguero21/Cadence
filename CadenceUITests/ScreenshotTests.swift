import XCTest

// App Store screenshot capture. Opt-in only — skipped unless the runner sets
// CADENCE_SCREENSHOTS=1 (pass TEST_RUNNER_CADENCE_SCREENSHOTS=1 to
// xcodebuild), so it never runs in CI or a normal ⌘U.
//
// Launches with --uitest (in-memory store, no permission prompts), seeds the
// DEBUG sample data from Settings, logs today, then walks the main screens
// attaching a screenshot of each. Export them from the .xcresult with
// `xcrun xcresulttool export attachments`.
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CADENCE_SCREENSHOTS"] == "1",
                          "Screenshot capture is opt-in")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest", "-AppleInterfaceStyle", "Light"]
        app.launch()
    }

    @MainActor
    func testCaptureScreenshots() throws {
        finishOnboarding()
        seedSampleData()

        // Today's log, captured along the way.
        let todayCard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Today's Log")).firstMatch
        XCTAssertTrue(todayCard.waitForExistence(timeout: 10))
        todayCard.tap()
        tap(app.buttons["Happy, 4 of 5"])
        snap("02-log-mood")
        tap(app.buttons["Next"])            // → body metrics
        snap("03-log-body-metrics")
        tap(app.buttons["Next"])            // → basics
        tap(app.buttons["Next"])            // → symptoms
        tap(app.buttons["Headache"])        // selects it and opens the severity slider
        snap("04-log-symptoms")
        tap(app.buttons["Next"])            // → triggers
        tap(app.buttons["Next"])            // → reflection
        tap(app.buttons["Finish"])
        XCTAssertTrue(app.staticTexts["Log complete!"].waitForExistence(timeout: 15))
        tap(app.buttons["Close"])

        sleep(1)
        snap("01-dashboard")

        tap(tab("Insights"))
        sleep(2)
        snap("05-insights")

        tap(tab("History"))
        sleep(1)
        // Early in a month the current page is nearly empty; show a full one.
        if Calendar.current.component(.day, from: .now) < 20 {
            tap(app.buttons["Previous month"])
            sleep(1)
        }
        snap("06-history")
        let loggedDay = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", logged, ")).element(boundBy: 2)
        tap(loggedDay)
        sleep(1)
        snap("07-day-detail")
        tap(app.buttons["Done"])

        tap(tab("Review"))
        sleep(1)
        tap(app.buttons["Start this week's review"].firstMatch)
        sleep(1)
        snap("08-weekly-review")
    }

    // MARK: - Steps

    private func finishOnboarding() {
        tap(app.buttons["Get Started"])
        tap(app.buttons["Skip"])
        tap(app.buttons["Skip"])
        tap(app.buttons["Open Cadence"])
    }

    private func seedSampleData() {
        tap(app.buttons["Settings"])
        for label in ["Seed 7 days of sample data",
                      "Seed 30 more days (deeper history)",
                      "Seed 90 more days (a full quarter)"] {
            let button = app.buttons[label]
            var swipes = 0
            while !button.isHittable && swipes < 12 {
                app.swipeUp()
                swipes += 1
            }
            tap(button)
            tap(app.alerts.buttons["OK"])
        }
        // Back to the dashboard.
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    // MARK: - Helpers

    // Tab items are buttons on iPhone (bottom bar) and iPad (top bar/sidebar).
    // The tab bar is minimizable (iOS 26): after scrolling it collapses to a
    // single button whose value is "Collapsed". Tapping that expands it again.
    private func tab(_ name: String) -> XCUIElement {
        let item = app.tabBars.buttons[name]
        if item.waitForExistence(timeout: 2) { return item }
        let collapsed = app.tabBars.buttons.matching(NSPredicate(format: "value == %@", "Collapsed")).firstMatch
        if collapsed.exists {
            collapsed.tap()
            return item
        }
        // iPad's top tab bar / sidebar isn't exposed as a TabBar; match the
        // item by its label wherever it lives.
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)",
                                  name, XCUIElement.ElementType.button.rawValue,
                                  XCUIElement.ElementType.tab.rawValue))
            .firstMatch
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "Missing \(element)", file: file, line: line)
        element.tap()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
