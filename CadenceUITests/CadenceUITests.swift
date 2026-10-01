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

        // What-you-track page: keep the default symptoms.
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 15), "Onboarding should ask what to track")
        continueButton.tap()

        let skipNotifications = app.buttons["Skip"]
        XCTAssertTrue(skipNotifications.waitForExistence(timeout: 15))
        skipNotifications.tap()

        let skipHealthKit = app.buttons["Skip"]
        XCTAssertTrue(skipHealthKit.waitForExistence(timeout: 15))
        skipHealthKit.tap()

        // The last page opens the first log directly.
        let logToday = app.buttons["Log how today feels"]
        XCTAssertTrue(logToday.waitForExistence(timeout: 15))
        logToday.tap()

        // Log flow: pick a mood, then step through to the note page.
        let happyMood = app.buttons["Happy, 4 of 5"]
        XCTAssertTrue(happyMood.waitForExistence(timeout: 15), "Mood step should show the emoji scale")
        happyMood.tap()

        let next = app.buttons["Next"]
        for _ in 0..<3 {   // mood → metrics → basics → symptoms
            XCTAssertTrue(next.waitForExistence(timeout: 15))
            next.tap()
        }

        // Symptoms step: hold-to-rate must produce the severity slider (this
        // regressed silently when the chip was a Button — Buttons cancel touch
        // tracking during a hold, so the long press never fired on device).
        let headache = app.buttons["Headache"]
        XCTAssertTrue(headache.waitForExistence(timeout: 15), "Symptoms step should show the Headache chip")
        headache.press(forDuration: 0.8)
        XCTAssertTrue(app.staticTexts["Severity: 5"].waitForExistence(timeout: 5),
                      "Holding a symptom chip should reveal the severity slider")

        for _ in 0..<2 {   // symptoms → factors → reflection
            XCTAssertTrue(next.waitForExistence(timeout: 15))
            next.tap()
        }

        let finish = app.buttons["Finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 15), "Reflection step should offer Finish")
        finish.tap()

        // Done step confirms the save, then close the sheet.
        XCTAssertTrue(app.staticTexts["Log complete!"].waitForExistence(timeout: 15))
        app.buttons["Close"].tap()

        // Dashboard reflects the completed log.
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 10),
                      "Dashboard should show today's log as completed")
    }
}
