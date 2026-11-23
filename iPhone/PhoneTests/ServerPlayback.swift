import XCTest

final class ServerPlayback: XCTestCase {
    func testDiscoveryAndFavorites() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.buttons["Set up your own server"].tap()
        XCTAssertTrue(app.navigationBars["Set up your server"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Open installation instructions"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        let sample = app.buttons["Explore sample library"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        sample.tap()
        let appleTV = app.buttons["Noxa Player on Apple TV"]
        XCTAssertTrue(appleTV.waitForExistence(timeout: 8))
        appleTV.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Siri Remote'")).firstMatch.exists)
        app.buttons["Server setup"].tap()
        XCTAssertTrue(app.navigationBars["Set up your server"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Open installation instructions"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["What to Watch"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Search"].tap()
        let field = app.textFields["Movies, shows, and episodes"]
        field.tap()
        field.typeText("Horizon")
        app.buttons["Horizon"].firstMatch.tap()
        let add = app.buttons["Add to Favorites"]
        let remove = app.buttons["Remove from Favorites"]
        if remove.waitForExistence(timeout: 1) { remove.tap() }
        add.tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        app.tabBars.buttons["Retro TV"].tap()
        app.buttons["Guide"].tap()
        let personal = app.buttons["station-For You"]
        XCTAssertTrue(personal.waitForExistence(timeout: 10))
        personal.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'For You'")).firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Favorites"].tap()
        app.buttons["Horizon"].firstMatch.tap()
        remove.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No favorites yet"].waitForExistence(timeout: 6))
    }

    func testHomeAndControlVisibility() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let sample = app.buttons["Explore sample library"]
        if sample.waitForExistence(timeout: 4) { sample.tap() }
        let horizon = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Horizon'")).firstMatch
        XCTAssertTrue(horizon.waitForExistence(timeout: 10))
        capture("Library home")
        horizon.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Retro TV"].tap()
        let guide = app.buttons["Guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 8))
        let video = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        for delay in [5, 10] {
            video.doubleTap()
            XCTAssertFalse(guide.exists)
            video.doubleTap()
            XCTAssertTrue(guide.waitForExistence(timeout: 3))
            app.buttons["Control visibility"].tap()
            app.buttons["Hide after \(delay) seconds"].tap()
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: guide)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: Double(delay + 4)), .completed)
            video.tap()
            XCTAssertTrue(guide.waitForExistence(timeout: 3))
        }
        app.buttons["Control visibility"].tap()
        app.buttons["Always on"].tap()
        sleep(11)
        XCTAssertTrue(guide.isHittable)
    }

    func testAirPlayRemoteControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments.append("-testAirPlayRemote")
        app.launch()
        let sample = app.buttons["Explore sample library"]
        if sample.waitForExistence(timeout: 4) { sample.tap() }
        app.tabBars.buttons["Retro TV"].tap()
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        let first = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'CH 02'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        next.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'CH 03'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Previous"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        app.buttons["Start Over"].tap()
        app.buttons["Back to Live"].tap()
        app.buttons["Guide"].tap()
        XCTAssertTrue(app.navigationBars["Channel Guide"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Up next'")).firstMatch.exists)
    }

    func testRetroTVRotation() {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }
        let app = XCUIApplication()
        app.launch()
        let sample = app.buttons["Explore sample library"]
        if sample.waitForExistence(timeout: 4) { sample.tap() }
        app.tabBars.buttons["Retro TV"].tap()
        let guide = app.buttons["Guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 10))
        let firstChannel = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'CH 02'")).firstMatch
        XCTAssertTrue(firstChannel.waitForExistence(timeout: 10))
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
        upper.press(forDuration: 0.1, thenDragTo: lower)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'CH 03'")).firstMatch.waitForExistence(timeout: 4))
        lower.press(forDuration: 0.1, thenDragTo: upper)
        XCTAssertTrue(firstChannel.waitForExistence(timeout: 4))
        for orientation: UIDeviceOrientation in [.landscapeLeft, .landscapeRight] {
            device.orientation = orientation
            XCTAssertGreaterThan(app.frame.width, app.frame.height)
            XCTAssertFalse(app.tabBars.firstMatch.isHittable)
            XCTAssertFalse(app.scrollViews.firstMatch.exists)
            let initialFrame = guide.frame
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
            XCTAssertEqual(guide.frame, initialFrame)
            start.tap()
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: guide)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
            start.tap()
            XCTAssertTrue(guide.waitForExistence(timeout: 3))
            guide.tap()
            app.buttons["Done"].tap()
            XCTAssertTrue(app.buttons["Start Over"].isHittable)
        }
        device.orientation = .portrait
        let library = app.tabBars.buttons["Library"]
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: library)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 8), .completed)
    }

    func testLibraryAndRetroTV() throws {
        let env = ProcessInfo.processInfo.environment
        guard let user = env["NOXA_TEST_USER"], let password = env["NOXA_TEST_PASSWORD"] else {
            throw XCTSkip("Requires a temporary server viewer account")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let movies = app.buttons["Movies"]
        if !movies.exists {
            let login = app.textFields["Username"]
            XCTAssertTrue(login.waitForExistence(timeout: 20))
            login.tap(); login.typeText(user)
            let secure = app.secureTextFields["Password"]
            secure.tap(); secure.typeText(password + "\n")
            app.buttons["Sign in"].tap()
        }
        XCTAssertTrue(movies.waitForExistence(timeout: 25))
        movies.tap()
        XCTAssertTrue(app.scrollViews.buttons.firstMatch.waitForExistence(timeout: 20))
        app.tabBars.buttons["Retro TV"].tap()
        let guide = app.buttons["Guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 20))
        let classic = app.buttons["station-Classic Westerns"]
        let ready = NSPredicate(format: "enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: ready, object: guide)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 40), .completed)
        guide.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(classic.waitForExistence(timeout: 120), app.debugDescription)
        while !classic.isHittable {
            let before = classic.frame
            app.swipeUp()
            if classic.frame == before { break }
        }
        XCTAssertTrue(classic.label.contains("Up next"))
        classic.tap()
        XCTAssertTrue(app.staticTexts["Classic Westerns"].waitForExistence(timeout: 10))
        sleep(6); capture("Live playback")
        app.buttons["Next"].tap()
        XCTAssertFalse(app.staticTexts["Classic Westerns"].exists)
        app.buttons["Previous"].tap()
        XCTAssertTrue(app.staticTexts["Classic Westerns"].waitForExistence(timeout: 10))
        app.buttons["Start Over"].tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        sleep(7); capture("Start Over A"); sleep(4); capture("Start Over B")
        done.tap()
        XCTAssertTrue(guide.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Classic Westerns"].exists)
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
