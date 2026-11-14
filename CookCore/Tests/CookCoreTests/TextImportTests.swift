import Foundation
import CoreGraphics
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

@Suite struct VideoCaptionTests {
    /// The way recipe videos write their captions: emoji headings and bullets, keycap step
    /// numbers, hashtags at the end.
    static let caption = """
    Creamy garlic butter noodles 🍜✨

    📝 INGREDIENTS 👇
    🧄 4 cloves garlic, minced
    🧈 2 tbsp butter
    🍝 200g noodles

    👩‍🍳 Instructions:
    1️⃣ Boil the noodles for 8 minutes.
    2️⃣ Melt the butter and fry the garlic.
    3️⃣ Toss together.

    #noodles #easyrecipe @hearth
    """

    @Test func emojiHeadingsBulletsAndKeycaps() {
        let recipe = TextRecipeParser.parse(Self.caption)
        #expect(recipe.title == "Creamy garlic butter noodles 🍜✨")
        #expect(recipe.ingredients == [
            .init(amount: "4", unit: "cloves", name: "garlic, minced"),
            .init(amount: "2", unit: "tbsp", name: "butter"),
            .init(amount: "200", unit: "g", name: "noodles"),
        ])
        #expect(recipe.steps == ["Boil the noodles for 8 minutes.", "Melt the butter and fry the garlic.", "Toss together."])
    }

    @Test func headingVariants() {
        let recipe = TextRecipeParser.parse("Toast\nIngredients for 2 people:\n2 slices bread\n~ How to make it ~\nToast the bread.")
        #expect(recipe.ingredients == [.init(amount: "2", unit: "slices", name: "bread")])
        #expect(recipe.steps == ["Toast the bread."])
    }

    @Test func tikTokCaptionFromPageData() {
        let html = #"""
        <html><head><meta property="og:title" content="Garlic noodles | TikTok"><meta property="og:description" content="Creamy garlic butter noodles…"></head>
        <body><script id="__UNIVERSAL_DATA_FOR_REHYDRATION__">{"itemInfo":{"itemStruct":{"desc":"Garlic noodles\nIngredients:\n2 tbsp butter\n4 cloves garlic\nMethod:\n1. Fry the garlic in the butter.\n#noodles"}}}</script></body></html>
        """#
        let info = PageCaption.extract(html: html, page: URL(string: "https://www.tiktok.com/@cook/video/123"))
        #expect(info.title == "Garlic noodles | TikTok")
        let recipe = TextRecipeParser.parse(info.text ?? "")
        #expect(recipe.title == "Garlic noodles")
        #expect(recipe.ingredients.map(\.name) == ["butter", "garlic"])
        #expect(recipe.steps == ["Fry the garlic in the butter."])
    }

    @Test func instagramDescriptionKeepsOnlyTheCaption() {
        let html = #"""
        <meta property="og:description" content="1,234 likes, 56 comments - hearthcook on March 3, 2025: &quot;Let&#039;s cook pesto&#x0a;Ingredients&#x0a;2 cups basil&#x0a;Method&#x0a;1. Blend it.&quot;. " />
        """#
        let info = PageCaption.extract(html: html, page: URL(string: "https://www.instagram.com/reel/abc/"))
        #expect(info.text == "Let's cook pesto\nIngredients\n2 cups basil\nMethod\n1. Blend it.")
        let recipe = TextRecipeParser.parse(info.text ?? "")
        #expect(recipe.title == "Let's cook pesto")
        #expect(recipe.ingredients == [.init(amount: "2", unit: "cup", name: "basil")])
        #expect(recipe.steps == ["Blend it."])
    }

    @Test func pageDataIsOnlyReadOnVideoSites() {
        let html = #"<script>{"desc":"Ingredients\n1 cup sugar"}</script>"#
        #expect(PageCaption.extract(html: html, page: URL(string: "https://example.com/post")).text == nil)
    }
}

@Suite struct ChineseRecipeTests {
    /// The 鸡丝凉面 card as the photo reader puts it in order: the title, two ingredient grids,
    /// then nine step panels (number and title, then the panel's text over a few lines), then tips.
    static let card = """
    鸡丝凉面
    食材准备
    鸡胸肉 2块
    鲜面条 300g
    黄瓜 1根
    胡萝卜 半根
    花生碎 适量
    香菜 适量
    熟白芝麻 适量
    香油 少许
    凉拌汁
    蒜末 3瓣
    生抽 3勺
    香醋 2勺
    1 煮鸡胸肉
    鸡胸肉冷水下锅，加姜片和
    少许料酒，煮至断生熟透，
    捞出放凉。
    ② 撕成鸡丝
    放凉后的鸡胸肉顺着纹理撕
    成细丝，口感更嫩更入味。
    ❸ 调凉拌汁
    碗中放蒜末、生抽、香醋，搅匀备用。
    小贴士
    1. 面条过凉后拌少许香油，更筋道不粘；
    """

    @Test func readsTheCard() {
        let recipe = TextRecipeParser.parse(Self.card)
        #expect(recipe.title == "鸡丝凉面")
        #expect(recipe.ingredients.count == 11)
        #expect(recipe.ingredients[0] == .init(amount: "2", unit: "块", name: "鸡胸肉"))
        #expect(recipe.ingredients[1] == .init(amount: "300", unit: "g", name: "鲜面条"))
        #expect(recipe.ingredients[3] == .init(amount: "1/2", unit: "根", name: "胡萝卜"))
        #expect(recipe.ingredients[4] == .init(amount: "", unit: "适量", name: "花生碎"))
        #expect(recipe.ingredients[8] == .init(amount: "3", unit: "瓣", name: "蒜末"))
        #expect(recipe.steps == [
            "煮鸡胸肉：鸡胸肉冷水下锅，加姜片和少许料酒，煮至断生熟透，捞出放凉。",
            "撕成鸡丝：放凉后的鸡胸肉顺着纹理撕成细丝，口感更嫩更入味。",
            "调凉拌汁：碗中放蒜末、生抽、香醋，搅匀备用。",
        ])
    }

    @Test func gridRowReadAsOneLine() {
        let recipe = TextRecipeParser.parse("食材\n鸡胸肉 2块 鲜面条 300g 黄瓜 1根\n盐 少许 2个鸡蛋")
        #expect(recipe.ingredients.map(\.name) == ["鸡胸肉", "鲜面条", "黄瓜", "盐", "鸡蛋"])
        #expect(recipe.ingredients.last == .init(amount: "2", unit: "个", name: "鸡蛋"))
    }

    @Test func stepPanelsWithoutNumbers() {
        // The circled numbers can be lost on a busy card: the titles and sentences still make steps.
        let recipe = TextRecipeParser.parse("面\n用料\n面条 200g\n煮面条\n锅中水开下面条，煮至熟透。\n装盘\n淋上酱汁即可。")
        #expect(recipe.ingredients == [.init(amount: "200", unit: "g", name: "面条")])
        #expect(recipe.steps == ["煮面条：锅中水开下面条，煮至熟透。", "装盘：淋上酱汁即可。"])
    }

    @Test func proseIsNotARecipe() {
        let recipe = TextRecipeParser.parse("今天给大家介绍一道“蛋炒饭”，在家也能做出路边摊的感觉。蛋黄蛋清分开炒的原因是两个香气。\n\n大家好，我是厨师长。")
        #expect(recipe.ingredients.isEmpty)
        #expect(recipe.steps.isEmpty)
    }

    @Test func chineseNumbers() {
        #expect(ChineseRecipe.chineseNumber("两") == "2")
        #expect(ChineseRecipe.chineseNumber("十二") == "12")
        #expect(ChineseRecipe.chineseNumber("半") == "1/2")
        #expect(ChineseRecipe.chineseNumber("文") == nil)
    }
}

@Suite struct TextLayoutTests {
    private func box(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat = 28) -> TextLayout.Box {
        .init(text: text, rect: CGRect(x: x, y: y, width: w, height: h))
    }

    @Test func stepPanelsAreReadOneAtATime() {
        // Two rows of three panels, each panel's text under a picture: never across the row.
        var boxes: [TextLayout.Box] = []
        for (row, top) in [(0, 640.0), (1, 980.0)] {
            for column in 0..<3 {
                let x = 50.0 + Double(column) * 350
                let n = row * 3 + column + 1
                boxes.append(box("\(n) 标题\(n)", x, top, 160, 34))
                boxes.append(box("第\(n)步第一行，", x, top + 45, 260))
                boxes.append(box("第\(n)步第二行。", x, top + 80, 200))
            }
        }
        let lines = TextLayout.readingOrder(boxes).components(separatedBy: "\n")
        #expect(lines == (1...6).flatMap { ["\($0) 标题\($0)", "第\($0)步第一行，", "第\($0)步第二行。"] })
    }

    @Test func ingredientGridReadCellByCell() {
        let boxes = [
            box("鸡丝凉面", 560, 20, 390, 90),
            box("食材准备", 560, 128, 120),
            box("鸡胸肉 2块", 565, 170, 115), box("鲜面条 300g", 735, 170, 130), box("黄瓜 1根", 900, 170, 90),
            box("胡萝卜 半根", 565, 205, 120), box("花生碎 适量", 735, 205, 120), box("香菜 适量", 900, 205, 100),
        ]
        let lines = TextLayout.readingOrder(boxes).components(separatedBy: "\n")
        #expect(lines.first == "鸡丝凉面")
        #expect(Set(lines) == Set(boxes.map(\.text)))
        #expect(lines.count == boxes.count)
    }

    @Test func captionsJSON() {
        let json = #"{"events":[{"segs":[{"utf8":"先把"},{"utf8":"鸡蛋打散"}]},{"segs":[{"utf8":"\n"}]},{"segs":[{"utf8":"热锅下油"}]}]}"#
        #expect(YouTubePage.transcript(json3: Data(json.utf8)) == "先把鸡蛋打散\n热锅下油")
    }
}
