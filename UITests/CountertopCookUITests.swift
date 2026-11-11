import XCTest
import UIKit

/// End-to-end checks for the v1 acceptance tests. Each launch uses a fresh in-memory store
/// seeded with the ten starter recipes (see `-uitesting` in the app).
///
/// On a closed iPhone Duo, Cook Mode shows one thing at a time (Step, Timers or Convert) under
/// a pinned timer chip, so the tests switch focus with `showTimers()` / `showStep()`; on every
/// other layout those do nothing.
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
        // Typing a recipe in is the fallback, under the + menu.
        let menu = element("addMenu")
        (menu.waitForExistence(timeout: 5) ? menu : app.buttons["Add Recipe"].firstMatch).tap()
        let manual = element("addRecipe")
        (manual.waitForExistence(timeout: 3) ? manual : app.buttons["Type it in by hand"].firstMatch).tap()
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

    // MARK: Recipe sources: ten starters on first launch, deletable

    func testTenStarterRecipesAndDelete() {
        let starters = ["Pan-Seared Steak", "Garlic Butter Pasta", "Simple No-Knead Bread",
                        "Fluffy Scrambled Eggs", "Easy Tomato Soup", "Chicken and Veg Stir-Fry",
                        "Weekend Pancakes", "Sheet-Pan Roast Vegetables", "One-Pot Bean Chili",
                        "Lemon Herb Chicken Thighs"]
        for title in starters { findRow(title) }
        snapshot("library-starters")

        let victim = findRow("One-Pot Bean Chili")
        victim.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "No Delete button after swiping the row")
        delete.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: victim)
        wait(for: [gone], timeout: 5)
        findRow("Lemon Herb Chicken Thighs")
    }

    // MARK: Recipe sources: import from a link (pages served by CI from ci/fixtures)

    func testImportFromLink() throws {
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment["IMPORT_FIXTURE_URL"],
                                 "IMPORT_FIXTURE_URL is not set: ci/run-ui-tests.sh serves ci/fixtures for this test")
        scrollLibraryToTop()
        type("\(base)/recipe.html", into: "importLink")
        element("importButton").tap()

        // Every import stops at the review screen first; nothing is saved yet.
        XCTAssertTrue(element("reviewNotice").waitForExistence(timeout: 30), "No review screen after import: \(errorText())")
        XCTAssertTrue(app.navigationBars["Review Import"].exists, "Review screen has the wrong title")
        XCTAssertEqual(element("reviewSource").label, "Source: Test Kitchen")
        XCTAssertEqual(element("recipeTitle").value as? String, "Weeknight Lemon Rice")
        // The page gives servings and a total time, so nothing is listed as missing.
        XCTAssertFalse(element("reviewMissing").exists, "Review says something is missing: \(element("reviewMissing").label)")
        XCTAssertFalse(text(containing: "MUST NOT BE IMPORTED").exists, "Story or description text was imported")
        XCTAssertFalse(element("recipeRow_Weeknight Lemon Rice").exists, "Saved before the review was confirmed")
        snapshot("import-review")
        saveForm()

        // The saved recipe opens with its source.
        let source = element("recipeSource")
        XCTAssertTrue(source.waitForExistence(timeout: 10), "Saving the review didn't open the recipe")
        XCTAssertEqual(source.label, "Source: Test Kitchen")
        XCTAssertTrue(app.navigationBars["Weeknight Lemon Rice"].exists, "Wrong title")
        XCTAssertFalse(text(containing: "MUST NOT BE IMPORTED").exists, "Story or description text was imported")
        snapshot("imported-recipe")

        element("startCooking").tap()
        XCTAssertTrue(element("stepText").waitForExistence(timeout: 5))
        waitForCookModeToSettle()
        XCTAssertEqual(element("stepText").label, "Rinse the rice until the water runs clear.")
        XCTAssertEqual(element("stepProgressLabel").label, "Step 1 of 4")
        XCTAssertTrue(element("ingredient_0").label.contains("1 1/2 cup long-grain rice"), element("ingredient_0").label)
        XCTAssertTrue(element("ingredient_3").label.contains("500 ml vegetable stock"), element("ingredient_3").label)
        // Auto-timers: step 1 states no time, so it has no timer. Steps 2 and 3 say "for 2
        // minutes" and "for 15 minutes", so each has its own Start button, and the two timers
        // run together, named by step.
        XCTAssertFalse(element("startStepTimer").exists, "Step 1 has no time in it but got a timer")
        element("nextStep").tap()
        XCTAssertEqual(element("startStepTimer").label, "Start 2 min timer")
        element("startStepTimer").tap()
        XCTAssertTrue(element("timerCountdown_Step 2").waitForExistence(timeout: 3), "Step 2's timer didn't start")
        element("nextStep").tap()
        XCTAssertEqual(element("startStepTimer").label, "Start 15 min timer")
        element("startStepTimer").tap()
        XCTAssertTrue(element("timerCountdown_Step 3").waitForExistence(timeout: 3), "Step 3's timer didn't start")
        XCTAssertTrue(element("timerCountdown_Step 2").exists, "Step 2's timer stopped when step 3's started")
        XCTAssertGreaterThan(seconds(element("timerCountdown_Step 3").label), seconds(element("timerCountdown_Step 2").label))
        snapshot("auto-timers")
        element("nextStep").tap()
        XCTAssertFalse(element("startStepTimer").exists, "Step 4 has no time in it but got a timer")
        element("exitCook").tap()
        XCTAssertTrue(element("startCooking").waitForExistence(timeout: 5))
        goBackToLibrary()

        // A page with no recipe card: a clear error, no review screen, and nothing is added.
        scrollLibraryToTop()
        type("\(base)/no-recipe.html", into: "importLink")
        element("importButton").tap()
        let error = element("importError")
        XCTAssertTrue(error.waitForExistence(timeout: 30), "No error for a page without recipe data")
        XCTAssertTrue(error.label.contains("No recipe data found"), error.label)
        XCTAssertFalse(element("reviewNotice").exists, "A page with no recipe still opened the review screen")
        XCTAssertFalse(element("recipeRow_Just a story").exists)
        snapshot("import-error")
    }

    // MARK: Import from pasted text: review screen, nothing invented, auto-timers

    func testPastedTextIsReviewedBeforeSaving() {
        scrollLibraryToTop()
        element("pasteTextButton").tap()
        let editor = element("pasteTextEditor")
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Paste screen didn't open")
        editor.tap()
        editor.typeText("Test Soup\nServes 2\nIngredients\n2 cups stock\n1 onion\nsalt\nMethod\nSimmer the stock for 10 minutes.\nServe hot.")
        hideKeyboard()
        scrollTo("pasteTextRead").tap()

        // The review screen shows what was read and says what the text didn't give.
        XCTAssertTrue(element("reviewNotice").waitForExistence(timeout: 5), "No review screen for pasted text")
        XCTAssertEqual(element("recipeTitle").value as? String, "Test Soup")
        XCTAssertEqual(element("reviewSource").label, "Source: Pasted text")
        // The text has no total time, so none is made up.
        XCTAssertTrue(element("reviewMissing").label.contains("total time"), element("reviewMissing").label)
        XCTAssertFalse(element("reviewMissing").label.contains("servings"), "Servings were in the text")
        XCTAssertTrue(text(containing: "Total time: not given").exists, "A total time was invented")
        snapshot("paste-review")
        scrollTo("ingredientName_0")
        XCTAssertEqual(element("ingredientAmount_0").value as? String, "2")
        XCTAssertEqual(element("ingredientUnit_0").value as? String, "cup")
        XCTAssertEqual(element("ingredientName_0").value as? String, "stock")
        saveForm()

        XCTAssertTrue(element("startCooking").waitForExistence(timeout: 10), "Saving the review didn't open the recipe")
        XCTAssertEqual(element("recipeSource").label, "Source: Pasted text")
        element("startCooking").tap()
        XCTAssertTrue(element("stepText").waitForExistence(timeout: 5))
        waitForCookModeToSettle()
        XCTAssertEqual(element("stepProgressLabel").label, "Step 1 of 2")
        XCTAssertEqual(element("stepText").label, "Simmer the stock for 10 minutes.")
        XCTAssertTrue(element("ingredient_0").label.contains("2 cup stock"), element("ingredient_0").label)
        // "salt" had no amount in the text, so it has none here.
        XCTAssertEqual(element("ingredient_2").label, "salt")
        XCTAssertEqual(element("startStepTimer").label, "Start 10 min timer")
        element("nextStep").tap()
        XCTAssertFalse(element("startStepTimer").exists, "\"Serve hot.\" has no time in it but got a timer")
    }

    // MARK: To-buy list: tick what you have, combine across recipes, check off

    func testToBuyListCombinesRecipesAndChecksOff() {
        // Steak: everything except the kosher salt (already in the kitchen).
        findRow("Pan-Seared Steak").tap()
        scrollTo("addToBuy").tap()
        let salt = scrollTo("have_5")
        XCTAssertTrue(salt.label.contains("kosher salt"), salt.label)
        salt.tap()
        XCTAssertEqual(salt.value as? String, "have it")
        XCTAssertEqual(scrollTo("confirmToBuy").label, "Add 6 items to the list")
        snapshot("to-buy-picker")
        element("confirmToBuy").tap()
        XCTAssertTrue(element("startCooking").waitForExistence(timeout: 5))
        goBackToLibrary()

        // Pasta: everything.
        findRow("Garlic Butter Pasta").tap()
        scrollTo("addToBuy").tap()
        XCTAssertEqual(scrollTo("confirmToBuy").label, "Add 6 items to the list")
        element("confirmToBuy").tap()
        XCTAssertTrue(element("startCooking").waitForExistence(timeout: 5))
        goBackToLibrary()

        element("openToBuy").tap()
        // 6 + 6 ingredients, but butter and garlic are in both recipes: one line each, amounts added.
        let count = element("toBuyCount")
        XCTAssertTrue(count.waitForExistence(timeout: 5), "To-buy list didn't open")
        XCTAssertEqual(count.label, "To buy · 10 items")
        let butter = scrollTo("toBuy_butter")
        XCTAssertEqual(butter.label, "5 tbsp butter")
        XCTAssertEqual(butter.value as? String, "to buy")
        XCTAssertEqual(scrollTo("toBuy_garlic").label, "7 cloves garlic")
        snapshot("to-buy")
        // Shopping: check butter off. It leaves "To buy" and moves down to "Bought".
        butter.tap()
        let nine = expectation(for: NSPredicate(format: "label == 'To buy · 9 items'"), evaluatedWith: count)
        wait(for: [nine], timeout: 5)
        XCTAssertEqual(scrollTo("toBuy_spaghetti").label, "200 g spaghetti")
        // Ticked as already in the kitchen, so never on the list.
        XCTAssertFalse(element("toBuy_kosher salt").exists, "An item ticked as 'have it' is on the to-buy list")
        let bought = scrollTo("toBuy_butter")
        XCTAssertEqual(bought.value as? String, "bought")
        XCTAssertTrue(scrollTo("clearBought").exists)
        snapshot("to-buy-bought")
    }

    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private func errorText() -> String {
        let error = element("importError")
        return error.exists ? error.label : "no error shown"
    }

    // MARK: Acceptance test 4: two timers keep counting while changing steps

    func testTwoTimersKeepCountingAcrossSteps() {
        openCookMode("Pan-Seared Steak")
        showTimers()
        element("preset_5").tap()
        element("preset_10").tap()

        let five = element("timerCountdown_5 min")
        let ten = element("timerCountdown_10 min")
        XCTAssertTrue(five.waitForExistence(timeout: 3))
        XCTAssertTrue(ten.waitForExistence(timeout: 3))
        let fiveStart = seconds(five.label)
        let tenStart = seconds(ten.label)

        showStep()
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
        showTimers()
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
        let three = expectation(for: NSPredicate(format: "label BEGINSWITH '3'"), evaluatedWith: element("servingsLabel"))
        wait(for: [three], timeout: 5)
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
        showTimers()
        element("preset_5").tap()
        element("preset_10").tap()
        showStep()

        switch foldPose {
        case "open", "partial":
            checkUnfolded(foldPose!)
        case "closed":
            requireFoldState(["closed", "none"])
            print("POSE: closed run, app reports \(element("cookPose").label)")
            checkLayout("closed-step1")
            element("nextStep").tap()
            checkLayout("closed-step2")
            if isFocusLayout {
                XCTAssertEqual(element("cookPose").label, "closed")
                // One focus at a time: the timers, then the converter, each with the chip pinned.
                showTimers()
                for id in ["timersHeader", "preset_5", "timerPause_5 min", "timerChipBar"] {
                    XCTAssertTrue(element(id).waitForExistence(timeout: 3), "\(id) missing with the timers in focus")
                }
                snapshot("closed-timers")
                element("focus_convert").tap()
                XCTAssertTrue(element("converterInput").waitForExistence(timeout: 3) && element("converterInput").isHittable,
                              "Converter not on screen with Convert in focus")
                XCTAssertTrue(element("timerCountdown_5 min").isHittable, "Timer chip not pinned with Convert in focus")
                snapshot("closed-convert")
            }
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
        // Open flat with the hinge top to bottom is "open flat landscape"; half open is "book".
        if vertical {
            let expected = pose == "open" ? "openLandscape" : "book"
            let reached = NSPredicate { [self] _, _ in element("cookPose").label == expected }
            _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: reached, object: nil)], timeout: 10)
            XCTAssertEqual(element("cookPose").label, expected, "Wrong layout for the \(pose) hinge")
        }
        checkFoldLayout("unfolded-\(pose)-step1", hinge: hinge.frame)
        element("nextStep").tap()
        checkFoldLayout("unfolded-\(pose)-step2", hinge: hinge.frame)
        photographTurnedPose(pose)
    }

    /// Turns the unfolded Duo a quarter turn, so the hinge runs across: open flat that is "open
    /// flat portrait" (recipe on top, timers below), half open it is "tabletop". Takes the
    /// screenshot when the simulator follows the turn; says so when it doesn't (the poses are
    /// also photographed by `testPoseGallery`).
    private func photographTurnedPose(_ pose: String) {
        let expected = pose == "open" ? "openPortrait" : "tabletop"
        let name = pose == "open" ? "pose-open-portrait" : "pose-tabletop"
        var reachedPose = false
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] where !reachedPose {
            XCUIDevice.shared.orientation = orientation
            let reached = NSPredicate { [self] _, _ in element("cookPose").label == expected }
            reachedPose = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: reached, object: nil)], timeout: 8) == .completed
        }
        let window = app.windows.firstMatch.frame
        print("POSE: turned \(pose) hinge: wanted \(expected), app reports \(element("cookPose").label), window=\(window)")
        if reachedPose {
            sleep(1)
            snapshot(name)
            for id in ["stepText", "stepProgressLabel", "backStep", "timersHeader", "timerCountdown_5 min"] {
                XCTAssertTrue(element(id).exists, "\(id) missing in \(name)")
            }
            // First look at this pose on a simulator: record where things landed.
            let hinge = element("hingeGap").frame
            print("POSE: \(name) hinge=\(hinge) step=\(element("stepText").frame) back=\(element("backStep").frame) timers=\(element("timersHeader").frame)")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: Six poses: each has its own layout

    /// Photographs the layouts for the poses a simulator can't always be put into, by asking
    /// Cook Mode for them by name (COOK_POSE). Runs once, on the closed iPhone Duo; the closed,
    /// open-flat-landscape and book layouts are photographed for real by the layout test.
    func testPoseGallery() throws {
        try XCTSkipUnless(foldPose == "closed", "Pose previews are taken once, on the iPhone Duo")
        for (pose, name) in [("tented", "pose-tented"), ("tabletop", "pose-tabletop-preview"),
                             ("openPortrait", "pose-open-portrait-preview")] {
            app.terminate()
            app.launchEnvironment["COOK_POSE"] = pose
            app.launch()
            openCookMode("Pan-Seared Steak")
            XCTAssertEqual(element("cookPose").label, pose)
            element("nextStep").tap()
            element("startStepTimer").tap()
            XCTAssertTrue(element("timerCountdown_Step 2").waitForExistence(timeout: 3), "Step timer chip missing in \(pose)")
            for id in ["stepText", "stepProgressLabel", "backStep", "nextStep", "exitCook"] {
                XCTAssertTrue(element(id).exists, "\(id) missing in the \(pose) layout")
            }
            switch pose {
            case "tented":
                // Glanceable: the step, its timer and Back / Next. No ingredient list, no converter.
                XCTAssertTrue(element("timerChipBar").exists, "No timer chip in the tented layout")
                XCTAssertFalse(element("ingredient_0").exists, "Tented layout should not list ingredients")
                XCTAssertFalse(element("converterInput").exists, "Tented layout should not show the converter")
            case "tabletop":
                // Look on top, touch below: the step above the ingredients, Back / Next and timers.
                let step = element("stepText").frame
                for id in ["ingredient_0", "backStep", "nextStep", "timersHeader"] {
                    XCTAssertTrue(element(id).exists, "\(id) missing on the tabletop deck")
                    XCTAssertGreaterThanOrEqual(element(id).frame.minY, step.maxY - 1, "\(id) is not below the step on the tabletop")
                }
            default:
                // Recipe on top, timers below.
                XCTAssertGreaterThanOrEqual(element("timersHeader").frame.minY, element("backStep").frame.maxY - 1,
                                            "Timers are not below the recipe in open flat portrait")
            }
            snapshot(name)
        }
        app.terminate()
        app.launchEnvironment["COOK_POSE"] = nil
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
        // Nothing cut off: the whole CONVERT card (input and result) and the first ingredients
        // are on screen, not clipped by the bottom edge or hidden under Back / Next.
        for id in ["converterInput", "converterResult"] {
            let frame = element(id).frame
            XCTAssertTrue(element(id).exists && window.contains(frame), "\(id) cut off in \(name): \(frame) in \(window)")
        }
        XCTAssertTrue(element("converterInput").isHittable, "Converter input not on screen in \(name)")
        // All three kinds of conversion are on screen and tappable, with their pair labels.
        for (id, label) in [("converterPair_Volume", "cups → ml"), ("converterPair_Weight", "oz → g"),
                            ("converterPair_Temp", "°F → °C")] {
            let chip = element(id)
            XCTAssertTrue(chip.exists && chip.isHittable && window.contains(chip.frame),
                          "\(id) not on screen in \(name): \(chip.frame)")
            XCTAssertEqual(chip.label, label, "\(id) chip text in \(name)")
        }
        let nav = element("backStep").frame
        for id in ["ingredient_0", "ingredient_1"] {
            let row = element(id)
            XCTAssertTrue(row.exists && row.isHittable, "\(id) not on screen in \(name)")
            XCTAssertLessThanOrEqual(row.frame.maxY, nav.minY + 1, "\(id) runs under Back / Next in \(name): \(row.frame) vs \(nav)")
        }
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

    /// Back from a recipe to the library. On the Duo the Back chevron sits in the side bar by the
    /// status bar, outside the navigation bar element (only Edit is there), so look for it
    /// anywhere on screen, else swipe from the edge.
    private func goBackToLibrary() {
        let back = app.buttons.matching(NSPredicate(
            format: "identifier == 'BackButton' OR label == 'Back' OR label == 'Recipes'")).firstMatch
        if back.waitForExistence(timeout: 2) && back.isHittable {
            back.tap()
        } else {
            let buttons = app.buttons.allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)" }
            print("BACK: no Back button; buttons on screen: \(buttons)")
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 8, dy: 0))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        }
        XCTAssertTrue(app.navigationBars["Recipes"].waitForExistence(timeout: 5), "Didn't return to the library")
    }

    /// True on the closed iPhone Duo, where Cook Mode shows one focus at a time.
    private var isFocusLayout: Bool { element("focus_timers").exists }

    /// Closed Duo: bring the timers into focus. Elsewhere they're always on screen.
    private func showTimers() {
        let tab = element("focus_timers")
        if tab.exists { tab.tap() }
    }

    /// Closed Duo: bring the step back into focus.
    private func showStep() {
        let tab = element("focus_step")
        if tab.exists { tab.tap() }
    }

    /// Scrolls up until the element is on screen and tappable (list rows load lazily).
    @discardableResult
    private func scrollTo(_ id: String) -> XCUIElement {
        let item = element(id)
        _ = item.waitForExistence(timeout: 5)
        for _ in 0..<8 where !(item.exists && item.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(item.exists && item.isHittable, "\(id) not found on screen")
        return item
    }

    /// Saves the recipe form: the toolbar's Save, or the one at the bottom of the form when the
    /// toolbar's isn't reachable.
    private func saveForm() {
        let save = element("saveRecipe")
        if save.waitForExistence(timeout: 3) && save.isHittable {
            save.tap()
        } else {
            scrollTo("saveRecipeBottom").tap()
        }
    }

    private func hideKeyboard() {
        let done = element("keyboardDone")
        if done.exists && done.isHittable { done.tap() }
    }

    /// Scrolls the library down until the recipe's row is on screen (rows load lazily).
    @discardableResult
    private func findRow(_ title: String) -> XCUIElement {
        let row = element("recipeRow_\(title)")
        _ = row.waitForExistence(timeout: 5)
        for _ in 0..<12 where !(row.exists && row.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(row.exists && row.isHittable, "Missing recipe \(title)")
        return row
    }

    private func scrollLibraryToTop() {
        for _ in 0..<12 where !element("importLink").isHittable {
            app.swipeDown()
        }
    }

    private func openCookMode(_ title: String) {
        let row = findRow(title)
        row.tap()
        let start = element("startCooking")
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(element("stepText").waitForExistence(timeout: 5))
        waitForCookModeToSettle()
    }

    /// Cook Mode slides up as a full-screen cover. A tap sent while it is still moving can land
    /// beside the control (seen on iPad), so wait until the header stops moving.
    private func waitForCookModeToSettle() {
        let exit = element("exitCook")
        var last = CGRect.null
        for _ in 0..<20 {
            let frame = exit.frame
            if frame == last && exit.isHittable { break }
            last = frame
            Thread.sleep(forTimeInterval: 0.25)
        }
        Thread.sleep(forTimeInterval: 0.5)
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
        // The closed Duo's outer screen has no fold in it, and its single column uses the
        // whole height, so the centre-line rule doesn't apply there.
        for button in app.buttons.allElementsBoundByIndex where !isFocusLayout && button.exists && button.isHittable {
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
        if abs(sizes.0 - sizes.1) > 2 {
            // Which parts of the recipe half reach past the timers half's size?
            let parts = element("recipeCard").descendants(matching: .any).allElementsBoundByIndex.prefix(60)
            for part in parts where part.exists {
                print("CARDS: part \(part.elementType.rawValue) id=\(part.identifier) label=\(part.label.prefix(30)) frame=\(part.frame)")
            }
        }
        XCTAssertEqual(sizes.0, sizes.1, accuracy: 2,
                       "Recipe and timers cards differ in size in \(name): \(recipe) vs \(timers)")
    }

    /// Takes a screenshot and checks every Cook Mode control and both timers are on screen,
    /// unclipped, tappable, and clear of the status bar.
    private func checkVisible(_ name: String) {
        snapshot(name)
        let window = app.windows.firstMatch.frame
        let next = element("nextStep").exists ? "nextStep" : "finishCooking"
        // With one focus at a time (closed Duo), the step is in focus and the timers show as
        // the pinned chip; everywhere else the whole timers pane is on screen too.
        let timerIDs = isFocusLayout ? ["timerChipBar", "focus_timers", "focus_convert"] : ["timersHeader", "preset_5"]
        let mustBeVisible = ["exitCook", "stepProgressLabel", "stepText", "servingsPlus", "backStep", next]
            + timerIDs + ["timerCountdown_5 min", "timerCountdown_10 min"]
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
