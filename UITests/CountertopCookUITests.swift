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
        chooseAdd("addRecipe", titled: "Type it in by hand")
        type("Test Toast", into: "recipeTitle")
        type("1 1/2", into: "ingredientAmount_0")
        type("slice", into: "ingredientUnit_0")
        type("bread", into: "ingredientName_0")
        type("Toast the bread.", into: "stepText_0")
        hideKeyboard()
        scrollTo("addStep").tap()
        type("Butter it.", into: "stepText_1")
        hideKeyboard()
        scrollTo("addStep").tap()
        type("Eat while warm.", into: "stepText_2")
        hideKeyboard()
        snapshot("editor-before-save")
        saveForm()

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

    // MARK: Startup page, then the shelf of books

    func testStartupPageThenLibrary() {
        app.terminate()
        app.launchArguments = ["-uitesting", "-splash"]
        app.launch()
        let splash = element("splash")
        XCTAssertTrue(splash.waitForExistence(timeout: 5), "No startup page")
        XCTAssertEqual(splash.label, "Hearth")
        snapshot("startup")
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: splash)
        wait(for: [gone], timeout: 15)
        XCTAssertTrue(app.navigationBars["Recipes"].exists, "The library didn't follow the startup page")
        // The name and mark live on the startup page now, not in the library.
        XCTAssertFalse(element("libraryHeader").exists, "The Hearth banner is still in the library")
        XCTAssertEqual(element("libraryCount").label, "10 recipes")
        findRow("Pan-Seared Steak")
        findRow("Garlic Butter Pasta")
        snapshot("library-shelf")
    }

    // MARK: Evening Hearth: warm dark colours, and the Light / Dark / System switch

    func testDarkModeColours() {
        app.terminate()
        app.launchArguments = ["-uitesting", "-startAppearance", "dark"]
        app.launch()
        let menu = element("appearanceMenu")
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "No appearance switch in the library")
        XCTAssertEqual(menu.value as? String, "Dark")
        let window = app.windows.firstMatch.frame
        let shot = screenshot()
        // The page: warm espresso, not black. A starter's plain cover: navy cloth.
        expectColour(shot, at: CGPoint(x: window.minX + 6, y: menu.frame.midY), is: 0x1C1712, "dark library background")
        let book = findRow("Pan-Seared Steak").frame
        expectColour(screenshot(), at: CGPoint(x: book.midX, y: book.minY + book.height * 0.3), is: 0x1B2F4A, "plain cover")
        snapshot("dark-library")

        // A recipe's book: its pages are warm brown cards with cream text.
        element("recipeRow_Pan-Seared Steak").tap()
        let title = element("recipeTitleHeader")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        expectColour(screenshot(), at: CGPoint(x: title.frame.minX - 8, y: title.frame.midY), is: 0x2E2720, "dark book page")
        snapshot("dark-recipe-book")
        element("startCooking").tap()
        XCTAssertTrue(element("stepText").waitForExistence(timeout: 5))
        waitForCookModeToSettle()
        snapshot("dark-cook-mode")
        element("exitCook").tap()
        XCTAssertTrue(element("startCooking").waitForExistence(timeout: 5))
        goBackToLibrary()

        // Light from the switch: back to the daytime cream at once.
        scrollLibraryToTop()
        element("appearanceMenu").tap()
        let light = element("appearance_light")
        (light.waitForExistence(timeout: 3) ? light : app.buttons["Light"].firstMatch).tap()
        let lit = expectation(for: NSPredicate(format: "value == 'Light'"), evaluatedWith: element("appearanceMenu"))
        wait(for: [lit], timeout: 5)
        sleep(1)
        expectColour(screenshot(), at: CGPoint(x: window.minX + 6, y: element("appearanceMenu").frame.midY), is: 0xFDF6E9,
                     "light library background")
        snapshot("light-library")
    }

    // MARK: Library: the filter row and the cart / + fit on screen

    func testLibraryFilterRowAndButtonsFit() {
        let favourites = element("favouritesFilter")
        XCTAssertTrue(favourites.waitForExistence(timeout: 5))
        // A row that had to scroll: bring Favourites in from the right.
        for _ in 0..<3 where !favourites.isHittable {
            element("category_Desserts").swipeLeft()
        }
        let add = element("addMenu"), cart = element("openToBuy"), search = element("librarySearch")
        let window = app.windows.firstMatch.frame
        print("FILTERS: favourites=\(favourites.frame) add=\(add.frame) cart=\(cart.frame) window=\(window)")
        XCTAssertTrue(favourites.isHittable, "Favourites can't be reached")
        // Favourites ends inside the page's right margin, where the + button ends, not under the
        // screen edge or the Duo's status strip.
        XCTAssertGreaterThanOrEqual(favourites.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(favourites.frame.maxX, add.frame.maxX + 1, "Favourites runs past the page margin")
        // The cart and + are on the page, beside the search field, clear of the filter row and
        // below the navigation bar.
        for button in [cart, add] {
            XCTAssertTrue(button.isHittable, "\(button.identifier) can't be tapped")
            XCTAssertLessThanOrEqual(button.frame.maxX, window.maxX)
            XCTAssertFalse(button.frame.intersects(favourites.frame), "\(button.identifier) overlaps the filter row")
            XCTAssertLessThan(button.frame.maxY, favourites.frame.minY, "\(button.identifier) isn't above the filter row")
            XCTAssertEqual(button.frame.midY, search.frame.midY, accuracy: 6, "\(button.identifier) isn't beside the search field")
        }
        favourites.tap()
        XCTAssertEqual(favourites.value as? String, "selected")
        snapshot("library-filters")
    }

    // MARK: A recipe opens as a book and keeps the cook's own notes

    func testRecipeOpensAsBookAndKeepsNotes() {
        findRow("Pan-Seared Steak").tap()
        let title = element("recipeTitleHeader")
        XCTAssertTrue(title.waitForExistence(timeout: 5), "The recipe's book didn't open")
        XCTAssertEqual(title.label, "Pan-Seared Steak")
        XCTAssertEqual(element("recipeFacts").label, "2 servings · 25 min")
        XCTAssertTrue(element("addPhoto").exists, "No way to add a photo")
        XCTAssertTrue(element("startCooking").isHittable, "Start Cooking isn't on the first page")
        snapshot("recipe-book")

        scrollTo("recipeNotes")
        type("Mum likes it medium.", into: "recipeNotes")
        hideKeyboard()
        snapshot("recipe-notes")
        goBackToLibrary()
        findRow("Pan-Seared Steak").tap()
        XCTAssertEqual(scrollTo("recipeNotes").value as? String, "Mum likes it medium.", "The note wasn't kept")
    }

    // MARK: Recipe sources: ten starters on first launch, deletable

    func testTenStarterRecipesAndDelete() {
        let starters = ["Pan-Seared Steak", "Garlic Butter Pasta", "Simple No-Knead Bread",
                        "Fluffy Scrambled Eggs", "Easy Tomato Soup", "Chicken and Veg Stir-Fry",
                        "Weekend Pancakes", "Sheet-Pan Roast Vegetables", "One-Pot Bean Chili",
                        "Lemon Herb Chicken Thighs"]
        for title in starters { findRow(title) }
        snapshot("library-starters")

        // Books are deleted from the menu that a long press opens.
        let victim = findRow("One-Pot Bean Chili")
        victim.press(forDuration: 1.2)
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "No Delete in the book's long-press menu")
        delete.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: victim)
        wait(for: [gone], timeout: 5)
        findRow("Lemon Herb Chicken Thighs")
    }

    // MARK: Recipe sources: import from a link (pages served by CI from ci/fixtures)

    func testImportFromLink() throws {
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment["IMPORT_FIXTURE_URL"],
                                 "IMPORT_FIXTURE_URL is not set: ci/run-ui-tests.sh serves ci/fixtures for this test")
        chooseAdd("menuImportLink", titled: "Import from a link")
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
        // The page publishes a photo of the dish: the review offers it as the book's cover.
        XCTAssertTrue(element("reviewCover").exists, "The source's photo isn't on the review screen")
        XCTAssertEqual(element("reviewCoverToggle").value as? String, "1", "The source's photo isn't chosen as the cover")
        // The review sheet scrolls: the third ingredient row comes fully into view. Swipe the
        // form itself (on iPad it is a sheet in the middle of the screen).
        let third = element("ingredientName_2")
        let form = app.collectionViews.containing(.any, identifier: "recipeTitle").firstMatch
        let window = app.windows.firstMatch.frame
        for _ in 0..<8 where !(third.exists && third.isHittable && third.frame.maxY <= window.maxY - 60) {
            (form.exists ? form : app).swipeUp(velocity: .slow)
        }
        XCTAssertTrue(third.isHittable && window.contains(third.frame), "Third ingredient row cut off: \(third.frame)")
        XCTAssertEqual(third.value as? String, "lemon, zested and juiced")
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

        // Its book on the shelf has the source's photo for a cover; the starters, with no photo,
        // have the plain cloth cover.
        XCTAssertEqual(findRow("Weeknight Lemon Rice").value as? String, "photo cover")
        snapshot("library-photo-cover")
        XCTAssertEqual(findRow("Pan-Seared Steak").value as? String, "plain cover")

        // A page with no recipe card: a clear error, no review screen, and nothing is added.
        chooseAdd("menuImportLink", titled: "Import from a link")
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
        chooseAdd("menuPasteText", titled: "Paste recipe text")
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

        scrollLibraryToTop()
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
        XCTAssertTrue(element("ingredient_1").label.contains("1/2 cup grated parmesan"), element("ingredient_1").label)

        element("servingsPlus").tap()
        let three = expectation(for: NSPredicate(format: "label BEGINSWITH '3'"), evaluatedWith: element("servingsLabel"))
        wait(for: [three], timeout: 5)
        XCTAssertTrue(element("servingsLabel").label.hasPrefix("3"), element("servingsLabel").label)
        XCTAssertTrue(element("ingredient_0").label.contains("300 g spaghetti"), element("ingredient_0").label)
        XCTAssertTrue(element("ingredient_1").label.contains("3/4 cup grated parmesan"), element("ingredient_1").label)
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
        // Long timers on purpose (15 and 30 minutes): a timer finishing mid-test shows the "Timer
        // done" alert, which covers every button and makes the visibility checks fail. On a
        // slow CI runner this test has taken more than five minutes.
        showTimers()
        element("preset_15").tap()
        element("preset_30").tap()
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
            checkLastIngredientReachable("closed-step2")
            if isFocusLayout {
                XCTAssertEqual(element("cookPose").label, "closed")
                // One focus at a time: the timers, then the converter, each with the chip pinned.
                showTimers()
                for id in ["timersHeader", "preset_5", "timerPause_15 min", "timerChipBar"] {
                    XCTAssertTrue(element(id).waitForExistence(timeout: 3), "\(id) missing with the timers in focus")
                }
                snapshot("closed-timers")
                element("focus_convert").tap()
                XCTAssertTrue(element("converterInput").waitForExistence(timeout: 3) && element("converterInput").isHittable,
                              "Converter not on screen with Convert in focus")
                XCTAssertTrue(element("timerCountdown_15 min").isHittable, "Timer chip not pinned with Convert in focus")
                // No dead space: the everyday conversions fill the screen under the converter.
                let common = element("commonConversions")
                XCTAssertTrue(common.exists, "No common conversions under the converter")
                XCTAssertTrue(app.windows.firstMatch.frame.contains(common.frame), "Common conversions cut off: \(common.frame)")
                XCTAssertGreaterThan(common.frame.height, 200, "Common conversions card is too small: \(common.frame)")
                let oven = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '350 °F'")).firstMatch
                XCTAssertTrue(oven.exists, "Oven temperatures missing from common conversions")
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
            checkLastIngredientReachable("landscape-step3")
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
        if pose == "partial" && vertical { checkBookPose(hinge: hinge) }
        element("nextStep").tap()
        checkFoldLayout("unfolded-\(pose)-step2", hinge: hinge.frame)
        photographTurnedPose(pose)
    }

    /// Book (half open, hinge top to bottom) must not look like open flat: the fold is shaded,
    /// and each page keeps a wider margin beside the spine (open flat keeps 28 pt).
    private func checkBookPose(hinge: XCUIElement) {
        let value = hinge.value as? String ?? ""
        XCTAssertTrue(value.contains("fold=book"), "No book fold drawn on the hinge: \(value)")
        let recipe = element("recipeCard").frame, timers = element("timersCard").frame
        let leftMargin = hinge.frame.minX - recipe.maxX, rightMargin = timers.minX - hinge.frame.maxX
        print("POSE: book margins beside the spine \(leftMargin) and \(rightMargin); pages \(recipe.width) and \(timers.width)")
        XCTAssertGreaterThanOrEqual(leftMargin, 44, "The left page runs up to the spine as in open flat: \(recipe) vs \(hinge.frame)")
        XCTAssertGreaterThanOrEqual(rightMargin, 44, "The right page runs up to the spine as in open flat: \(timers) vs \(hinge.frame)")
        XCTAssertLessThan(recipe.width, 300, "Book pages should be narrower than open flat's 315 pt: \(recipe.width)")
        snapshot("pose-book")
    }

    /// Scrolls the step's list to the end: the last ingredient must come fully into view, clear
    /// of the fade above Back / Next.
    private func checkLastIngredientReachable(_ name: String) {
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'ingredient_'"))
        let count = rows.count
        XCTAssertGreaterThan(count, 0, "No ingredients in \(name)")
        guard count > 0 else { return }
        let last = element("ingredient_\(count - 1)")
        let card = element("recipeCard")
        func clear() -> Bool { last.isHittable && last.frame.maxY <= element("backStep").frame.minY - 12 }
        for _ in 0..<10 where !clear() {
            let from = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        }
        print("POSE: \(name) last ingredient \(last.frame) back=\(element("backStep").frame)")
        XCTAssertTrue(clear(), "The last ingredient stays under Back / Next in \(name): \(last.frame) vs \(element("backStep").frame)")
        snapshot("\(name)-ingredients-end")
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
            for id in ["stepText", "stepProgressLabel", "backStep", "timersHeader", "timerCountdown_15 min"] {
                XCTAssertTrue(element(id).exists, "\(id) missing in \(name)")
            }
            // First look at this pose on a simulator: record where things landed.
            let hinge = element("hingeGap").frame
            print("POSE: \(name) hinge=\(hinge) step=\(element("stepText").frame) back=\(element("backStep").frame) timers=\(element("timersHeader").frame)")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: Open flat portrait: a long step is readable in full

    /// The recipe half is short in open flat portrait. A long step must start right under the
    /// progress bar, scroll to its end above Back / Next, and leave the timers below it.
    func testOpenPortraitShowsWholeLongStep() {
        guard foldPose == nil || foldPose == "closed" else { return }
        let longStep = "Whisk the eggs with the milk, a pinch of salt and the vanilla, then pour the mixture into the warm pan, tilt it so the batter covers the base evenly, and cook gently until the edges set and the middle is just firm."
        app.terminate()
        app.launchEnvironment["COOK_POSE"] = "openPortrait"
        app.launch()
        chooseAdd("menuPasteText", titled: "Paste recipe text")
        let editor = element("pasteTextEditor")
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Paste screen didn't open")
        editor.tap()
        editor.typeText("Long Step Test\nIngredients\n2 eggs\n1 cup milk\nMethod\n\(longStep)\nServe.")
        hideKeyboard()
        scrollTo("pasteTextRead").tap()
        XCTAssertTrue(element("reviewNotice").waitForExistence(timeout: 5))
        saveForm()
        let start = element("startCooking")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let step = element("stepText")
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        waitForCookModeToSettle()
        XCTAssertEqual(element("cookPose").label, "openPortrait")
        XCTAssertEqual(step.label, longStep)
        // The step starts right under the progress bar, not scrolled or squeezed away.
        let progress = element("stepProgressLabel").frame, nav = element("backStep").frame
        XCTAssertGreaterThanOrEqual(step.frame.minY, progress.maxY - 1, "The step starts above the progress bar: \(step.frame)")
        XCTAssertLessThanOrEqual(step.frame.minY, progress.maxY + 40, "The step doesn't start under the progress bar: \(step.frame)")
        XCTAssertGreaterThan(nav.minY - step.frame.minY, 100, "Too little room for the step: \(step.frame) vs Back \(nav)")
        XCTAssertTrue(step.isHittable, "The step is not on screen")
        // The timers sit below the recipe half.
        XCTAssertGreaterThanOrEqual(element("timersHeader").frame.minY, nav.maxY - 1, "Timers are not below the recipe")
        snapshot("open-portrait-long-step")
        // Scrolled, the end of the step comes above Back / Next.
        let card = element("recipeCard")
        for _ in 0..<6 where step.frame.maxY > nav.minY - 4 {
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                .press(forDuration: 0.05, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        }
        XCTAssertLessThanOrEqual(step.frame.maxY, nav.minY - 4, "The end of the step can't be scrolled into view: \(step.frame) vs \(nav)")
        snapshot("open-portrait-long-step-end")
        // The next step starts at its top again.
        element("nextStep").tap()
        XCTAssertEqual(element("stepText").label, "Serve.")
        XCTAssertGreaterThanOrEqual(element("stepText").frame.minY, element("stepProgressLabel").frame.maxY - 1)
        app.terminate()
        app.launchEnvironment["COOK_POSE"] = nil
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
                // A deck wide enough has the whole timers pane; a narrow one has the timer chip.
                let timers = element("timersHeader").exists ? "timersHeader" : "timerChipBar"
                for id in ["ingredient_0", "backStep", "nextStep", timers] {
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
        let timerIDs = ["timersHeader", "preset_5", "timerCountdown_15 min", "timerCountdown_30 min"]
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
        // A tap while a sheet is still sliding up can miss, leaving no keyboard focus: wait for
        // the keyboard, and tap again if it didn't come.
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 3) { break }
        }
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
        for _ in 0..<12 where !element("librarySearch").isHittable {
            app.swipeDown()
        }
    }

    /// Opens the library's + menu and picks one way of adding a recipe.
    private func chooseAdd(_ id: String, titled title: String) {
        scrollLibraryToTop()
        let menu = element("addMenu")
        (menu.waitForExistence(timeout: 5) ? menu : app.buttons["Add Recipe"].firstMatch).tap()
        let item = element(id)
        (item.waitForExistence(timeout: 3) ? item : app.buttons[title].firstMatch).tap()
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
        // Let a step change finish animating, so the screenshot isn't two steps cross-fading.
        Thread.sleep(forTimeInterval: 0.8)
        snapshot(name)
        let window = app.windows.firstMatch.frame
        let next = element("nextStep").exists ? "nextStep" : "finishCooking"
        // With one focus at a time (closed Duo), the step is in focus and the timers show as
        // the pinned chip; everywhere else the whole timers pane is on screen too.
        let timerIDs = isFocusLayout ? ["timerChipBar", "focus_timers", "focus_convert"] : ["timersHeader", "preset_5"]
        let mustBeVisible = ["exitCook", "stepProgressLabel", "stepText", "servingsPlus", "backStep", next]
            + timerIDs + ["timerCountdown_15 min", "timerCountdown_30 min"]
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

    /// The screen as it is now: the one that shows something (see `snapshot`).
    private func screenshot() -> XCUIScreenshot {
        let shots = XCUIScreen.screens.map { $0.screenshot() }
        return shots.first(where: { !isBlank($0.image) }) ?? XCUIScreen.main.screenshot()
    }

    /// Checks the colour at a point (in window points) against a hex colour, in sRGB.
    private func expectColour(_ shot: XCUIScreenshot, at point: CGPoint, is hex: UInt32, _ what: String,
                              tolerance: Int = 10, file: StaticString = #filePath, line: UInt = #line) {
        guard let cg = shot.image.cgImage else { return XCTFail("No screenshot for \(what)", file: file, line: line) }
        let window = app.windows.firstMatch.frame
        let scale = CGFloat(cg.width) / max(window.width, 1)
        let x = Int((point.x - window.minX) * scale), y = Int((point.y - window.minY) * scale)
        guard x >= 0, y >= 0, x < cg.width, y < cg.height, let pixel = cg.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))
        else { return XCTFail("\(what): \(point) is off the screenshot", file: file, line: line) }
        var rgba = [UInt8](repeating: 0, count: 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return XCTFail("\(what): couldn't read the pixel", file: file, line: line) }
        let want = [Int((hex >> 16) & 0xFF), Int((hex >> 8) & 0xFF), Int(hex & 0xFF)]
        let got = rgba.prefix(3).map(Int.init)
        let text = got.map { String(format: "%02X", $0) }.joined()
        print("COLOUR: \(what) at \(point) = #\(text), want #\(String(format: "%06X", hex))")
        XCTAssertTrue(zip(got, want).allSatisfy { abs($0 - $1) <= tolerance },
                      "\(what) is #\(text), want #\(String(format: "%06X", hex))", file: file, line: line)
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
