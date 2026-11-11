import Foundation
import Testing
@testable import CookCore

@Suite struct StepTimeTests {
    @Test func findsMinutesAndHours() {
        #expect(StepTime.minutes(in: "Cover and simmer for 15 minutes.") == 15)
        #expect(StepTime.minutes(in: "Melt the butter in a pot and toast the rice for 2 minutes.") == 2)
        #expect(StepTime.minutes(in: "Bake at 350°F for 1 hour 30 minutes.") == 90)
        #expect(StepTime.minutes(in: "Bake for 1 hour and 15 min, then cool.") == 75)
        #expect(StepTime.minutes(in: "Rest the dough for 1.5 hours.") == 90)
        #expect(StepTime.minutes(in: "Let it rest 12 hours.") == 720)
        #expect(StepTime.minutes(in: "Give it a 5-minute rest.") == 5)
        #expect(StepTime.minutes(in: "Fry 3 mins per side") == 3)
    }

    @Test func rangeUsesTheEarlierEnd() {
        #expect(StepTime.minutes(in: "Roast for 8-10 minutes until golden.") == 8)
        #expect(StepTime.minutes(in: "Simmer 2 to 3 hours.") == 120)
        #expect(StepTime.minutes(in: "Cook 20–25 min.") == 20)
    }

    @Test func neverGuesses() {
        #expect(StepTime.minutes(in: "Pat the steaks dry and season both sides.") == nil)
        #expect(StepTime.minutes(in: "Cook for a few minutes until soft.") == nil)
        #expect(StepTime.minutes(in: "Stir for 30 seconds.") == nil)
        #expect(StepTime.minutes(in: "Heat the oven to 200°C and add 2 cups of stock.") == nil)
        #expect(StepTime.minutes(in: "Rest for 1/2 hour.") == nil)
        #expect(StepTime.minutes(in: "Add 500 ml water.") == nil)
    }

    @Test func labelledDurations() {
        #expect(StepTime.duration(in: "1 hr 15 min") == 75)
        #expect(StepTime.duration(in: "45 minutes") == 45)
        #expect(StepTime.duration(in: "1h 30m") == 90)
        #expect(StepTime.duration(in: "overnight") == nil)
    }
}

@Suite struct TextRecipeParserTests {
    static let pasted = """
    Lemon Garlic Chicken

    My grandmother made this every Sunday. THIS STORY MUST NOT BE IMPORTED.

    Serves 4 | Prep time: 10 min | Cook time: 25 min

    Ingredients:
    - 4 chicken thighs
    - 2 tbsp olive oil
    • 3 cloves garlic, minced
    For the sauce:
    - 1 lemon, juiced
    - salt, to taste

    Instructions
    1. Heat the oil in a pan over medium heat.
    2) Brown the chicken for 6 minutes per side.
    Step 3: Add the garlic and lemon juice and simmer for 10-12 minutes.
    4. Rest, then serve.

    Notes
    Keeps 3 days in the fridge.
    """

    @Test func headingsGiveIngredientsAndSteps() {
        let recipe = TextRecipeParser.parse(Self.pasted)
        #expect(recipe.title == "Lemon Garlic Chicken")
        #expect(recipe.servings == 4)
        #expect(recipe.totalMinutes == 35)
        #expect(recipe.ingredients == [
            .init(amount: "4", unit: "", name: "chicken thighs"),
            .init(amount: "2", unit: "tbsp", name: "olive oil"),
            .init(amount: "3", unit: "cloves", name: "garlic, minced"),
            .init(amount: "1", unit: "", name: "lemon, juiced"),
            .init(amount: "", unit: "", name: "salt, to taste"),
        ])
        #expect(recipe.steps == [
            "Heat the oil in a pan over medium heat.",
            "Brown the chicken for 6 minutes per side.",
            "Add the garlic and lemon juice and simmer for 10-12 minutes.",
            "Rest, then serve.",
        ])
        #expect(recipe.steps.map(StepTime.minutes(in:)) == [nil, 6, 10, nil])
        let everything = ([recipe.title] + recipe.steps + recipe.ingredients.map(\.name)).joined(separator: " ")
        #expect(!everything.contains("MUST NOT BE IMPORTED"))
        #expect(!everything.contains("fridge"))
    }

    @Test func missingFactsStayEmpty() {
        let recipe = TextRecipeParser.parse("Toast\n\nIngredients\n2 slices bread\nbutter\n\nMethod\nToast the bread.\nButter it.")
        #expect(recipe.title == "Toast")
        #expect(recipe.servings == nil)
        #expect(recipe.totalMinutes == nil)
        #expect(recipe.ingredients == [.init(amount: "2", unit: "slices", name: "bread"), .init(amount: "", unit: "", name: "butter")])
        #expect(recipe.steps == ["Toast the bread.", "Butter it."])
        #expect(recipe.steps.map(StepTime.minutes(in:)) == [nil, nil])
    }

    @Test func withoutHeadingsUsesNumbersAndAmounts() {
        let text = """
        Quick Pancakes
        Cook these on Sunday mornings for 10 minutes of joy.
        0:00 Intro
        1 cup flour
        2 eggs
        1. Whisk everything.
        2. Fry for 2 minutes per side.
        """
        let recipe = TextRecipeParser.parse(text)
        #expect(recipe.title == "Quick Pancakes")
        #expect(recipe.totalMinutes == nil)
        #expect(recipe.ingredients == [.init(amount: "1", unit: "cup", name: "flour"), .init(amount: "2", unit: "", name: "eggs")])
        #expect(recipe.steps == ["Whisk everything.", "Fry for 2 minutes per side."])
    }

    @Test func textWithNoRecipeGivesNothing() {
        let recipe = TextRecipeParser.parse("Just a nice day\nWe went to the market and it was lovely.")
        #expect(recipe.ingredients.isEmpty)
        #expect(recipe.steps.isEmpty)
    }
}

@Suite struct YouTubePageTests {
    @Test func videoIDs() {
        #expect(YouTubePage.videoID(from: URL(string: "https://youtu.be/abcDEF12345?si=xyz")!) == "abcDEF12345")
        #expect(YouTubePage.videoID(from: URL(string: "https://www.youtube.com/watch?v=abcDEF12345&t=10s")!) == "abcDEF12345")
        #expect(YouTubePage.videoID(from: URL(string: "https://m.youtube.com/shorts/abcDEF12345")!) == "abcDEF12345")
        #expect(YouTubePage.videoID(from: URL(string: "https://example.com/watch?v=abcDEF12345")!) == nil)
        #expect(YouTubePage.videoID(from: URL(string: "https://www.youtube.com/@somechannel")!) == nil)
    }

    @Test func readsTitleDescriptionAndCaptions() {
        let html = #"""
        <html><head><meta property="og:title" content="Fallback"></head><body><script>
        var ytInitialPlayerResponse = {"captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[{"baseUrl":"https://www.youtube.com/api/timedtext?v=abc&lang=fr","name":{"simpleText":"French"},"languageCode":"fr"},{"baseUrl":"https://www.youtube.com/api/timedtext?v=abc&lang=en","name":{"simpleText":"English"},"languageCode":"en"}]}},"videoDetails":{"videoId":"abcDEF12345","title":"One-Pan \"Lemon\" Rice","lengthSeconds":"300","shortDescription":"Ingredients:\n1 cup rice\n2 tbsp butter\n\nMethod:\n1. Rinse the rice.\n2. Simmer for 15 minutes.","author":"Test Kitchen"},"microformat":{"playerMicroformatRenderer":{"ownerChannelName":"Test Kitchen TV"}}};
        </script></body></html>
        """#
        let info = YouTubePage.extract(html: html)
        #expect(info.title == "One-Pan \"Lemon\" Rice")
        #expect(info.channel == "Test Kitchen TV")
        #expect(info.captionURL?.absoluteString == "https://www.youtube.com/api/timedtext?v=abc&lang=en")
        let recipe = TextRecipeParser.parse(info.description ?? "")
        #expect(recipe.ingredients == [.init(amount: "1", unit: "cup", name: "rice"), .init(amount: "2", unit: "tbsp", name: "butter")])
        #expect(recipe.steps == ["Rinse the rice.", "Simmer for 15 minutes."])
    }

    @Test func transcriptFromTimedText() {
        let xml = #"<?xml version="1.0"?><transcript><text start="0" dur="2">Hi, it&amp;#39;s me</text><text start="2" dur="3">add 2 cups &amp;amp; stir</text></transcript>"#
        #expect(YouTubePage.transcript(xml: xml) == "Hi, it's me add 2 cups & stir")
    }
}

@Suite struct ShoppingMergeTests {
    @Test func combinesSameItemAndUnit() {
        let combined = ShoppingMerge.combine([
            .init(amount: "2", unit: "tbsp", name: "butter"),
            .init(amount: "3", unit: "cloves", name: "garlic, smashed"),
            .init(amount: "3", unit: "tbsp", name: "Butter"),
            .init(amount: "4", unit: "cloves", name: "garlic, sliced"),
            .init(amount: "1 1/2", unit: "cup", name: "grated parmesan"),
            .init(amount: "1/2", unit: "cups", name: "grated parmesan"),
        ])
        #expect(combined.map(\.text) == ["5 tbsp butter", "7 cloves garlic", "2 cup grated parmesan"])
    }

    @Test func differentUnitsAndFreeTextStaySeparate() {
        let combined = ShoppingMerge.combine([
            .init(amount: "", unit: "", name: "salt, to taste"),
            .init(amount: "1", unit: "tsp", name: "salt"),
            .init(amount: "", unit: "", name: "Salt"),
            .init(amount: "2", unit: "", name: "ribeye steaks, 1 inch thick"),
        ])
        #expect(combined.map(\.text) == ["salt", "1 tsp salt", "2 ribeye steaks"])
    }
}
