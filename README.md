# Hearth

A small, personal iOS cooking app (formerly Countertop Cook; the bundle ID is unchanged).
Local only: no account, no server. Apple Intelligence, on the phone, only to write out recipes that are spoken or hard to read. All text is English.

## What it does

- **Startup page.** The Hearth mark and name for a moment, then the library.
- **Library.** A shelf of books, one per recipe, on three shelves (Food, Drinks, Desserts), with
  favourites, search and sorting. A book's cover is the recipe's first photo (added by you, or the
  import source's own photo of the dish), full bleed under the title; without one it is a cloth
  cover: navy, green or brick with a thin gold border. **Change cover** on the recipe page
  replaces it any time. Long-press a book to favourite or delete it. Ten starter recipes ship with the app.
- **A recipe opens like a book.** Paper pages for the cover and photos, the ingredients, the
  method and **My notes**, the cook's own page. Two pages side by side on a wide screen.
  Photos come from the photo library and are stored with the recipe.
- **Light and Evening Hearth (dark).** Dark mode is warm espresso and cream, never black or
  cold grey: background #1C1712, recipe half #211B15, timers half #2A2118, cards #2E2720, text
  #F5EDE3, secondary text #C9BBA8, accent #F08A3C. It follows the phone, or the Light / Dark /
  System switch in the library. Tricolore strips and motifs are muted at night.
- **Import from anywhere, reviewed before saving.** When the plain reader can't find both an
  ingredient list and steps (a video that only *says* the recipe, a busy photo), Apple
  Intelligence on the phone (iOS 26+, where available) writes the recipe out from the text,
  captions or speech, and the review screen says so. Nothing leaves the phone. When no recipe
  can be found at all, a "Couldn't find the recipe" screen says why and offers the next way in
  (screenshots, a saved video, pasting, or filling it in).
  - **+ → Import from a link.** A recipe page's link: only its schema.org Recipe data is read, never the story text.
  - A YouTube link, or Share → Hearth from the YouTube app: the video's title and description
    (and captions, when YouTube serves them).
  - A TikTok, Instagram, Facebook, Pinterest or other video or post link: the post's caption.
    Emoji headings and bullets ("📝 INGREDIENTS 👇", "🧄 2 cloves garlic", "1️⃣ Boil…") and
    hashtags are handled. A video that only *says* the recipe can't be read from its link.
  - A YouTube video with no written recipe: its captions (from the public watch page), then
    Apple Intelligence. The video itself is never downloaded; for a video with no captions,
    Hearth suggests a screen recording and Import a saved video.
  - **+ → Import a saved video.** A video in Photos (Xiaohongshu, Douyin, TikTok…) or a screen
    recording of one playing: the words it shows on screen and what it says (speech recognition
    on the phone).
  - Chinese recipes: 食材 / 用料 / 调料 / 做法 / 步骤 headings, amounts such as 2块, 300g, 半根,
    适量, 少许, a whole grid row on one line, and ①–⑨ / ❶ / 第1步 step numbers.
  - **+ → Import from photos / Scan a recipe page.** A cookbook page, a recipe card, a handwritten
    note, or screenshots of the recipe from a video. The text is read on the phone (Apple's Vision
    text recognition; two-column cards are read column by column). Several photos make one
    recipe, in the order picked. Share → Hearth from Photos does the same.
  - Pasted text: an Ingredients list and a Method / Instructions list.
  - Every import opens a review screen first. Nothing is invented: an amount, a time or a serving
    count the source doesn't give is left blank and listed as "not in the source".
  - Typing a recipe in by hand is still there, under **+**, as the fallback.
- **Auto-timers.** A step whose text states a time ("simmer for 15 minutes") gets its own Start
  button in Cook Mode. Timers are named by step and run side by side.
- **To-buy list.** From any recipe, tick what you already have; the rest goes on the list. The
  same item from several recipes becomes one line with the amounts added. Check items off as you shop.
- **Cook Mode.** One big step at a time, Back / Next, ingredients under the step, servings
  scaling, and a converter (cups → ml, oz → g, °F → °C). The recipe and the timers are always
  on screen together.

## Six poses (iPhone Duo)

Each has its own layout, chosen from the real fold APIs (`UIHingeInteraction` for the hinge
state, the hinge's reserved region for its direction):

| Pose | Layout |
| --- | --- |
| Closed | Outer screen, one column: Step, Timers or Convert in focus, with the timer chip pinned on top. |
| Open flat, landscape | Recipe left, timers right, on the two cream tones. Nothing drawn or tappable on the hinge. |
| Open flat, portrait | Recipe on top, timers below. |
| Book | Left page and right page, each a little narrower, with a gutter beside the hinge. |
| Tented | Outer screen, glanceable: one big step, its timer, the timer chip, Back / Next. |
| Tabletop | The step on top to look at; ingredients, Back / Next and timers on the deck below. |

Other iPhones and iPads use the plain layout: side by side when wide, stacked when tall.

## Design

- Warm cream two-tone: recipe side `#FAF8F3`, timers side `#F4EFE4`.
- Fonts: **Lora** for recipe titles only; **Lato** for steps, ingredients, timers and all other
  text (both under the SIL Open Font License, in `App/Fonts`). Amounts and countdowns use bold,
  fixed-width figures.
- French and Italian touches are visual only: tricolore strips, bistro navy and basil green, an
  Eiffel Tower and a basil leaf. No French or Italian words.
- The logo (`App/HearthLogo.swift`) is drawn in code; `ci/render-icon.swift` renders the app icon from it.

## Layout of the repo

| Path | What |
| --- | --- |
| `CookCore/` | Swift package with the pure logic: fractions and scaling, converter, timers, recipe-page / pasted-text / YouTube reading, step times, to-buy merging. Tested with `swift test`. |
| `App/` | SwiftUI + SwiftData app. |
| `ShareExtension/` | Puts Hearth in the iOS Share Sheet and hands the shared link or text to the app. |
| `UITests/` | XCUITests for the acceptance tests, saving screenshots along the way. |
| `project.yml` | XcodeGen spec; `xcodegen generate` creates `CountertopCook.xcodeproj`. |
| `.github/workflows/ci.yml` | Builds on GitHub's macOS runners and runs all tests on iPhone, iPad and the iPhone Duo simulator (closed, open and half open). |

## Build

On a Mac with Xcode:

```bash
brew install xcodegen
xcodegen generate
open CountertopCook.xcodeproj
```

Without Xcode, push to GitHub: the CI workflow builds the app and runs every test. Screenshots
and summaries are published to the `ci-results` and `ci-results-duo` branches.

Core logic only (works with just the Command Line Tools):

```bash
swift test --package-path CookCore
```
