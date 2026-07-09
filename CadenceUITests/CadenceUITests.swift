import XCTest

// End-to-end smoke test: onboarding → complete a daily log → the dashboard
// reflects it. UI tests are XCTest by necessity (XCUIApplication has no Swift
// Testing equivalent); everything else in the project uses Swift Testing.
//
// The app is launched with --uitest, which gives it an in-memory store, a
// fresh onboarding state, and suppresses all permission prompts (see
// AppLaunch.isUITesting) — so this test is deterministic and never blocked
// by system dialogs.
final class CadenceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardThenLogADay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()

        // Onboarding: welcome → skip both permission pages → finish.
        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10), "Onboarding should start at the welcome page")
        getStarted.tap()

        let skipNotifications = app.buttons["Skip"]
        XCTAssertTrue(skipNotifications.waitForExistence(timeout: 15))
        skipNotifications.tap()

        let skipHealthKit = app.buttons["Skip"]
        XCTAssertTrue(skipHealthKit.waitForExistence(timeout: 15))
        skipHealthKit.tap()

        let openCadence = app.buttons["Open Cadence"]
        XCTAssertTrue(openCadence.waitForExistence(timeout: 15))
        openCadence.tap()

        // Dashboard: open today's log.
        let todayCard = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Today's Log")
        ).firstMatch
        XCTAssertTrue(todayCard.waitForExistence(timeout: 10), "Dashboard should show the Today's Log card")
        todayCard.tap()

        // Log flow: pick a mood, then step through to the note page.
        let happyMood = app.buttons["Happy, 4 of 5"]
        XCTAssertTrue(happyMood.waitForExistence(timeout: 15), "Mood step should show the emoji scale")
        happyMood.tap()

        let next = app.buttons["Next"]
        for _ in 0..<7 {   // mood → metrics → basics → symptoms → factors → peaksAndValleys → intentions → note
            XCTAssertTrue(next.waitForExistence(timeout: 15))
            next.tap()
        }

        let finish = app.buttons["Finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 15), "Note step should offer Finish")
        finish.tap()

        // Done step confirms the save, then close the sheet.
        XCTAssertTrue(app.staticTexts["Log complete!"].waitForExistence(timeout: 15))
        app.buttons["Close"].tap()

        // Dashboard reflects the completed log.
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 10),
                      "Dashboard should show today's log as completed")
    }
}
