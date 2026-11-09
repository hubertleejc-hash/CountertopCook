import XCTest

/// End-to-end checks for the v1 acceptance tests. Each launch uses a fresh in-memory store
/// seeded with the three starter recipes (see `-uitesting` in the app).
final class CountertopCookUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: Acceptance test 3: add a recipe, cook through every step, finish

    func testAddRecipeCookThroughAllStepsAndFinish() {
        element("addRecipe").tap()
        type("Test Toast", into: "recipeTitle")
        type("1 1/2", into: "ingredientAmount_0")
        type("slice", into: "ingredientUnit_0")
        type("bread", into: "ingredientName_0")
        type("Toast the bread.", into: "stepText_0")
        hideKeyboard()
        element("addStep").tap()
        type("Butter it.", into: "stepText_1")
        hideKeyboard()
        element("addStep").tap()
        type("Eat while warm.", into: "stepText_2")
        hideKeyboard()
        snapshot("editor-before-save")
        // iOS 27.1 on iPhone Duo can drop the toolbar item's identifier; fall back to its label.
        let save = element("saveRecipe")
        (save.waitForExistence(timeout: 3) ? save : app.buttons["Save"].firstMatch).tap()

        openCookMode("Test Toast")
        XCTAssertEqual(element("stepProgressLabel").label, "Step 1 of 3")
        XCTAssertTrue(element("ingredient_0").label.contains("1 1/2 slice bread"))
        for step in 2...3 {
            element("nextStep").tap()
            XCTAssertEqual(element("stepProgressLabel").label, "Step \(step) of 3")
        }
        XCTAssertFalse(element("nextStep").exists, "Next should become Finish on the last step")
        element("finishCooking").tap()
        XCTAssertTrue(element("doneCooking").waitForExistence(timeout: 3))
        snapshot("finished")
        element("doneCooking").tap()
        XCTAssertTrue(element("startCooking").waitForExistence(timeout: 5), "Should return to the recipe")
    }

    // MARK: Acceptance test 4: two timers keep counting while changing steps

    func testTwoTimersKeepCountingAcrossSteps() {
        openCookMode("Pan-Seared Steak")
        element("preset_5").tap()
        element("preset_10").tap()

        let five = element("timerCountdown_5 min")
        let ten = element("timerCountdown_10 min")
        XCTAssertTrue(five.waitForExistence(timeout: 3))
        XCTAssertTrue(ten.waitForExistence(timeout: 3))
        let fiveStart = seconds(five.label)
        let tenStart = seconds(ten.label)

        element("nextStep").tap()
        element("nextStep").tap()
        XCTAssertEqual(element("stepProgressLabel").label, "Step 3 of 6")
        sleep(3)

        XCTAssertTrue(five.exists && ten.exists, "Timers must survive step changes")
        XCTAssertTrue(five.isHittable, "Timers must stay on screen")
        XCTAssertLessThan(seconds(five.label), fiveStart)
        XCTAssertLessThan(seconds(ten.label), tenStart)
        XCTAssertGreaterThan(seconds(ten.label), seconds(five.label))

        // A step timer runs alongside the other two.
        element("startStepTimer").tap()
        XCTAssertTrue(element("timerCountdown_Step 3").waitForExistence(timeout: 3))
        element("backStep").tap()
        XCTAssertTrue(element("timerCountdown_Step 3").exists)

        // Pause freezes a timer; +1 min adds time.
        element("timerPause_5 min").tap()
        sleep(1)
        let paused = seconds(five.label)
        sleep(2)
        XCTAssertEqual(seconds(five.label), paused)
        element("timerAddMinute_5 min").tap()
        sleep(1)
        XCTAssertEqual(seconds(five.label), paused + 60)
        element("timerCancel_5 min").tap()
        XCTAssertFalse(five.waitForExistence(timeout: 1))
        snapshot("timers")
    }

    // MARK: Acceptance test 5: 2 → 3 servings rescales ingredients

    func testServingsRescaleIngredients() {
        openCookMode("Garlic Butter Pasta")
        XCTAssertTrue(element("ingredient_0").label.contains("200 g spaghetti"), element("ingredient_0").label)
        XCTAssertTrue(element("ingredient_1").label.contains("1 1/2 cup grated parmesan"), element("ingredient_1").label)

        element("servingsPlus").tap()
        XCTAssertTrue(element("servingsLabel").label.hasPrefix("3"), element("servingsLabel").label)
        XCTAssertTrue(element("ingredient_0").label.contains("300 g spaghetti"), element("ingredient_0").label)
        XCTAssertTrue(element("ingredient_1").label.contains("2 1/4 cup grated parmesan"), element("ingredient_1").label)
        XCTAssertTrue(element("ingredient_5").label.contains("salt, to taste"), element("ingredient_5").label)

        element("ingredient_0").tap()
        XCTAssertEqual(element("ingredient_0").value as? String, "checked")
        snapshot("servings")
    }

    // MARK: Acceptance test 6: nothing clipped, centre line clear, timers always visible

    func testLayoutKeepsTimersVisibleAndCentreLineClear() {
        openCookMode("Pan-Seared Steak")
        // Long timers on purpose: a timer finishing mid-test shows the "Timer done" alert,
        // which covers every button and makes the visibility checks fail.
        element("preset_5").tap()
        element("preset_10").tap()
        checkLayout("portrait-step1")
        element("nextStep").tap()
        checkLayout("portrait-step2")

        XCUIDevice.shared.orientation = .landscapeLeft
        let window = app.windows.firstMatch
        let rotated = NSPredicate { _, _ in window.frame.width > window.frame.height }
        wait(for: [XCTNSPredicateExpectation(predicate: rotated, object: nil)], timeout: 10)
        sleep(1)
        checkLayout("landscape-step2")
        element("nextStep").tap()
        checkLayout("landscape-step3")
    }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func type(_ text: String, into id: String) {
        let field = element(id)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing field \(id)")
        field.tap()
        field.typeText(text)
    }

    private func hideKeyboard() {
        let done = element("keyboardDone")
        if done.exists && done.isHittable { done.tap() }
    }

    private func openCookMode(_ title: String) {
        let row = element("recipeRow_\(title)")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Missing recipe \(title)")
        row.tap()
        let start = element("startCooking")
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(element("stepText").waitForExistence(timeout: 5))
    }

    private func seconds(_ countdown: String) -> Int {
        countdown.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    private func checkLayout(_ name: String) {
        snapshot(name)
        let window = app.windows.firstMatch.frame
        let next = element("nextStep").exists ? "nextStep" : "finishCooking"
        let mustBeVisible = ["exitCook", "stepProgressLabel", "stepText", "servingsPlus", "backStep", next,
                             "timersHeader", "preset_5", "timerCountdown_5 min", "timerCountdown_10 min"]
        for id in mustBeVisible {
            let item = element(id)
            XCTAssertTrue(item.waitForExistence(timeout: 3), "\(id) missing in \(name)")
            XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(item.frame), "\(id) clipped in \(name): \(item.frame)")
            if item.elementType == .button {
                XCTAssertTrue(item.isHittable, "\(id) not tappable in \(name)")
            }
        }
        // Controls must stay clear of the status bar. Use its real frame: on iPhone Duo it runs
        // down the side instead of across the top.
        let statusBar = XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars.firstMatch
        let headerIDs = ["exitCook", "servingsPlus", "servingsMinus"]
        if statusBar.exists, !statusBar.frame.isEmpty {
            for id in headerIDs {
                XCTAssertFalse(element(id).frame.intersects(statusBar.frame),
                               "\(id) under the status bar in \(name): \(element(id).frame) vs \(statusBar.frame)")
            }
        } else if window.height > window.width * 1.5 {
            // Tall phone in portrait with no status bar element exposed: assume it's across the top.
            for id in headerIDs {
                XCTAssertGreaterThanOrEqual(element(id).frame.minY, window.minY + 44, "\(id) under the status bar in \(name)")
            }
        }

        // The physical centre line (where a fold or hinge sits) must have no tappable control on it.
        let wide = window.width > window.height && window.width >= 560
        let centreLine = wide
            ? CGRect(x: window.midX - 10, y: window.minY, width: 20, height: window.height)
            : CGRect(x: window.minX, y: window.midY - 10, width: window.width, height: 20)
        for button in app.buttons.allElementsBoundByIndex where button.exists && button.isHittable {
            XCTAssertFalse(button.frame.intersects(centreLine),
                           "Button '\(button.label)' sits on the centre line in \(name): \(button.frame)")
        }
    }

    private func snapshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let env = ProcessInfo.processInfo.environment
        if let dir = env["SCREENSHOT_DIR"] {
            let device = (env["SIMULATOR_DEVICE_NAME"] ?? "device").replacingOccurrences(of: " ", with: "_")
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(device)-\(name).png")
            try? shot.pngRepresentation.write(to: url)
        }
    }
}
