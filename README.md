# Countertop Cook

A small, personal iOS cooking app. Local only: no account, no server, no AI.

In Cook Mode the recipe and the timers are always on screen together:
- **Wide (unfolded / landscape / iPad):** recipe on the left, timers on the right, split 50/50.
- **Tall (closed phone / portrait / tented):** recipe step on top, timers right below, split 50/50.
- A clear strip runs down the physical centre of the screen, so no button sits on a fold or hinge.

## Layout

| Path | What |
| --- | --- |
| `CookCore/` | Swift package with the pure logic: fractions and serving scaling, unit converter, timer engine. Tested with `swift test`. |
| `App/` | SwiftUI + SwiftData app (recipe library, editor, Cook Mode, timers pane). |
| `UITests/` | XCUITests covering the v1 acceptance tests, saving screenshots along the way. |
| `project.yml` | XcodeGen spec; `xcodegen generate` creates `CountertopCook.xcodeproj`. |
| `.github/workflows/ci.yml` | Builds on GitHub's macOS runners and runs all tests on iPhone, iPad and any iPhone Duo simulator. |

## Build

On a Mac with Xcode 15 or later:

```bash
brew install xcodegen
xcodegen generate
open CountertopCook.xcodeproj
```

Without Xcode, push to GitHub: the CI workflow builds the app and runs every test. Screenshots
are attached to each run under **Artifacts → test-results**.

Core logic only (works with just the Command Line Tools):

```bash
swift test --package-path CookCore
```
