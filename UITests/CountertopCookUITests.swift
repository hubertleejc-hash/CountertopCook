import XCTest
import UIKit

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
                // The toolbar Save can scroll out of reach on some devices; the form also has one at the bottom.
        let save = element("saveRecipe")
        (save.waitForExistence(timeout: 3) && save.isHittable ? save : element("saveRecipeBottom")).tap()

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

    // MARK: Acceptance test 6: nothing clipped, nothing on the hinge, timers always visible

    /// On iPhone Duo, CI runs this test once per hinge pose and says which in FOLD_POSE:
    /// "closed" (outer display), then "open" and "partial" after moving the hinge with
    /// ci/duo-hinge.sh. Elsewhere FOLD_POSE is empty and the device is rotated instead.
    func testLayoutKeepsTimersVisibleAndCentreLineClear() {
        openCookMode("Pan-Seared Steak")
        // Long timers on purpose: a timer finishing mid-test shows the "Timer done" alert,
        // which covers every button and makes the visibility checks fail.
        element("preset_5").tap()
        element("preset_10").tap()

        switch foldPose {
        case "open", "partial":
            checkUnfolded(foldPose!)
        case "closed":
            requireFoldState(["closed", "none"])
            checkLayout("closed-step1")
            element("nextStep").tap()
            checkLayout("closed-step2")
            print("FOLD: closed Duo checked in portrait; unfolded layout is checked in the open and partial runs")
        default:
            checkLayout("portrait-step1")
            element("nextStep").tap()
            checkLayout("portrait-step2")

            XCUIDevice.shared.orientation = .landscapeLeft
            let window = app.windows.firstMatch
            let rotated = NSPredicate { _, _ in window.frame.width > window.frame.height }
            let didRotate = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: rotated, object: nil)], timeout: 10)
            XCTAssertEqual(didRotate, .completed, "Device did not rotate to landscape: \(window.frame)")
            sleep(1)
            checkLayout("landscape-step2")
            element("nextStep").tap()
            checkLayout("landscape-step3")
        }
    }

    /// Unfolded iPhone Duo: the app must report the hinge as open, and the split must sit on
    /// either side of the hinge's reserved region, the recipe leading and the timers trailing.
    private func checkUnfolded(_ pose: String) {
        requireFoldState([pose == "open" ? "fullyOpen" : "partiallyOpen"])
        let hinge = element("hingeGap")
        XCTAssertTrue(hinge.waitForExistence(timeout: 5),
                      "No hinge gap in the \(pose) pose: the app found no division reserved region")
        sleep(1)
        let window = app.windows.firstMatch.frame
        print("FOLD: pose=\(pose) foldState=\(element("foldState").label) window=\(window) hinge=\(hinge.frame) region=\(hinge.value ?? "")")
        let vertical = hinge.frame.height >= hinge.frame.width
        if pose == "open" {
            XCTAssertTrue(vertical, "Fully open, the hinge should run top to bottom for a left/right split: \(hinge.frame) in \(window)")
        }
        checkFoldLayout("unfolded-\(pose)-step1", hinge: hinge.frame)
        element("nextStep").tap()
        checkFoldLayout("unfolded-\(pose)-step2", hinge: hinge.frame)
    }

    private func checkFoldLayout(_ name: String, hinge: CGRect) {
        checkVisible(name)
        let window = app.windows.firstMatch.frame
        let vertical = hinge.height >= hinge.width
        let next = element("nextStep").exists ? "nextStep" : "finishCooking"
        let recipeIDs = ["exitCook", "stepProgressLabel", "stepText", "servingsPlus", "backStep", next]
        let timerIDs = ["timersHeader", "preset_5", "timerCountdown_5 min", "timerCountdown_10 min"]
        // Recipe on the leading (or top) side of the hinge, timers on the other side.
        for id in recipeIDs {
            let frame = element(id).frame
            if vertical {
                XCTAssertLessThanOrEqual(frame.maxX, hinge.minX + 1, "\(id) is not left of the hinge in \(name): \(frame) vs \(hinge)")
            } else {
                XCTAssertLessThanOrEqual(frame.maxY, hinge.minY + 1, "\(id) is not above the hinge in \(name): \(frame) vs \(hinge)")
            }
        }
        for id in timerIDs {
            let frame = element(id).frame
            if vertical {
                XCTAssertGreaterThanOrEqual(frame.minX, hinge.maxX - 1, "\(id) is not right of the hinge in \(name): \(frame) vs \(hinge)")
            } else {
                XCTAssertGreaterThanOrEqual(frame.minY, hinge.maxY - 1, "\(id) is not below the hinge in \(name): \(frame) vs \(hinge)")
            }
        }
        // Two halves of about the same size.
        let first = vertical ? hinge.minX - window.minX : hinge.minY - window.minY
        let second = vertical ? window.maxX - hinge.maxX : window.maxY - hinge.maxY
        XCTAssertEqual(first, second, accuracy: (vertical ? window.width : window.height) * 0.1,
                       "The split around the hinge is not 50/50 in \(name): \(hinge) in \(window)")
        checkEqualCards(name, sideBySide: vertical)
        // Nothing tappable on the hinge.
        for button in app.buttons.allElementsBoundByIndex where button.exists && button.isHittable {
            XCTAssertFalse(button.frame.intersects(hinge),
                           "Button '\(button.label)' sits on the hinge in \(name): \(button.frame) vs \(hinge)")
        }
    }

    /// Waits for Cook Mode's hinge probe (UIHingeInteraction) to report one of `expected`, and
    /// fails clearly if it doesn't. Closed, the API may report the hinge closed or no hinge.
    private func requireFoldState(_ expected: Set<String>) {
        let state = element("foldState")
        XCTAssertTrue(state.waitForExistence(timeout: 5),
                      "Cook Mode has no foldState probe: the app was not built with the iOS 27.1 fold APIs")
        let reached = NSPredicate { _, _ in expected.contains(state.label) }
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: reached, object: nil)], timeout: 20)
        print("FOLD: expected \(expected.sorted().joined(separator: " or ")), app reports \(state.label)")
        XCTAssertEqual(result, .completed, "Hinge state \(expected.sorted().joined(separator: " or ")) not reached: the app reports '\(state.label)'")
    }

    // MARK: Helpers

    private var foldPose: String? {
        let pose = ProcessInfo.processInfo.environment["FOLD_POSE"] ?? ""
        return pose.isEmpty ? nil : pose
    }

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
        checkVisible(name)
        let window = app.windows.firstMatch.frame
        // The physical centre line (where a fold or hinge sits) must have no tappable control on it.
        let wide = window.width > window.height && window.width >= 560
        let centreLine = wide
            ? CGRect(x: window.midX - 10, y: window.minY, width: 20, height: window.height)
            : CGRect(x: window.minX, y: window.midY - 10, width: window.width, height: 20)
        for button in app.buttons.allElementsBoundByIndex where button.exists && button.isHittable {
            XCTAssertFalse(button.frame.intersects(centreLine),
                           "Button '\(button.label)' sits on the centre line in \(name): \(button.frame)")
        }
        if wide { checkEqualCards(name, sideBySide: true) }
    }

    /// Side by side, the recipe and timers cards must be the same width (top and bottom, the
    /// same height), whatever the status bar or camera takes from one edge.
    private func checkEqualCards(_ name: String, sideBySide: Bool) {
        let recipe = element("recipeCard").frame, timers = element("timersCard").frame
        XCTAssertFalse(recipe.isEmpty || timers.isEmpty, "Cards not found in \(name)")
        let sizes = sideBySide ? (recipe.width, timers.width) : (recipe.height, timers.height)
        print("CARDS: \(name) recipe=\(recipe) timers=\(timers)")
        XCTAssertEqual(sizes.0, sizes.1, accuracy: 2,
                       "Recipe and timers cards differ in size in \(name): \(recipe) vs \(timers)")
    }

    /// Takes a screenshot and checks every Cook Mode control and both timers are on screen,
    /// unclipped, tappable, and clear of the status bar.
    private func checkVisible(_ name: String) {
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
        // Only trust the reported frame when it looks like a normal top bar: on iPhone Duo it
        // comes back as a box that doesn't match where the bar is drawn.
        let topBar = statusBar.exists && statusBar.frame.height < 80 && statusBar.frame.width >= window.width - 1
        if topBar {
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
    }

    private func snapshot(_ name: String) {
        // An unfolded Duo shows the app on its inner display, while `XCUIScreen.main` can still
        // be the outer one, now off and black. Keep the screen that shows something.
        let shots = XCUIScreen.screens.map { $0.screenshot() }
        let shot = shots.first(where: { !isBlank($0.image) }) ?? XCUIScreen.main.screenshot()
        XCTAssertFalse(isBlank(shot.image),
                       "Screenshot \(name) is blank on all \(shots.count) screen(s); the app isn't visible")
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

    /// True when the image is a single flat colour (a screen that's off renders solid black).
    private func isBlank(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return true }
        var lo: UInt8 = 255, hi: UInt8 = 0
        for (i, value) in pixels.enumerated() where i % 4 != 3 {
            lo = min(lo, value); hi = max(hi, value)
        }
        return hi - lo < 8
    }
}
