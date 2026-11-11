import SwiftUI
import SwiftData
import CookCore

func ingredientLine(_ item: Ingredient, servingsFrom base: Int, to servings: Int) -> String {
    let amount = Scaler.scale(item.amountText, from: base, to: servings)
    return [amount, item.unit, item.name].filter { !$0.isEmpty }.joined(separator: " ")
}

/// The scaled amount with a trailing space ("1 1/2 "), or "" when the ingredient has none.
func ingredientAmount(_ item: Ingredient, servingsFrom base: Int, to servings: Int) -> String {
    let amount = Scaler.scale(item.amountText, from: base, to: servings)
    return amount.isEmpty ? "" : amount + " "
}

/// Unit and name: "cup grated parmesan".
func ingredientRest(_ item: Ingredient) -> String {
    [item.unit, item.name].filter { !$0.isEmpty }.joined(separator: " ")
}

/// How Cook Mode is laid out. An iPhone Duo has six poses, each with its own layout; other
/// devices use `plain`.
enum CookPose: String, CaseIterable {
    /// Not a folding phone: recipe and timers side by side when wide, stacked when tall.
    case plain
    /// Folded shut, on the outer screen: one focus at a time under a pinned timer chip.
    case closed
    /// Half open and standing like a tent, on the outer screen: one big step and the timer chip.
    case tented
    /// Open flat, hinge top to bottom: recipe left, timers right.
    case openLandscape
    /// Open flat, hinge across: recipe on top, timers below.
    case openPortrait
    /// Half open like a book, hinge top to bottom: a left page and a right page.
    case book
    /// Half open on a table, hinge across: what you look at on top, what you touch below.
    case tabletop
}

/// Cook Mode: the recipe and the timers are always on screen together, in the layout for the
/// device's pose (see `CookPose`). The hinge state comes from `UIHingeInteraction` and the
/// hinge's direction from its reserved region (FoldSplit.swift).
/// Styled after reference-design.png: pale cream under the recipe, warm cream under the timers,
/// nothing drawn on the hinge and nothing tappable on it.
struct CookModeView: View {
    let recipe: Recipe
    @Environment(TimerStore.self) private var timers
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex = 0
    @State private var servings: Int
    @State private var checked: Set<PersistentIdentifier> = []
    @State private var finished = false
    @State private var fold = FoldPosture.none
    /// Which way the hinge runs while unfolded: true top to bottom (panes side by side), false
    /// across (panes stacked), nil when the screen Cook Mode is on has no hinge region.
    @State private var hingeVertical: Bool? = true
    @State private var rootSize = CGSize.zero
    /// Closed pose: what the single column is showing.
    @State private var focus = Focus.step

    enum Focus: String, CaseIterable {
        case step = "Step", timers = "Timers", convert = "Convert"
    }

    /// Width of the empty strip kept between the two panes (where a hinge would be).
    static let hingeGap: CGFloat = 28
    /// Below this timers-pane height, timers switch to one-line rows so several stay visible.
    static let densePaneHeight: CGFloat = 420
    /// From this timers-pane height up there's room for the line under "Always on this side".
    static let roomyPaneHeight: CGFloat = 760
    /// Book pose: extra room each page keeps beside the hinge, and on its outer edge, so the two
    /// pages are narrower than open flat and sit like a book's, with margins round the text.
    /// The narrower book page sets its step at 34 pt (open flat: 38 pt), so a step still fits
    /// in four lines and the first ingredients stay above Back / Next.
    static let bookGutter: CGFloat = 20
    static let bookOuterMargin: CGFloat = 8
    static let bookStepSize: CGFloat = 34
    /// Below this height a recipe pane drops the COOK MODE label and puts the title in the top
    /// row, so the step keeps room to be read (open flat portrait on a short screen).
    static let shortPaneHeight: CGFloat = 430

    /// UI tests and previews can ask for one pose's layout by name (COOK_POSE=tented), for the
    /// poses a simulator can't be put into.
    static let poseOverride = CookPose(rawValue: ProcessInfo.processInfo.environment["COOK_POSE"] ?? "")

    init(recipe: Recipe) {
        self.recipe = recipe
        _servings = State(initialValue: recipe.servings)
    }

    private var pose: CookPose {
        if let forced = Self.poseOverride { return forced }
        switch fold {
        case .closed:
            return .closed
        case .fullyOpen:
            return hingeVertical == false ? .openPortrait : .openLandscape
        case .partiallyOpen:
            // Half open with no hinge region on this screen: Cook Mode is on the outer screen.
            let small = rootSize != .zero && min(rootSize.width, rootSize.height) < 600
            if hingeVertical == nil && small { return .tented }
            return hingeVertical == false ? .tabletop : .book
        case .none, .unknown:
            return .plain
        }
    }

    var body: some View {
        let pose = self.pose
        return Group {
            switch pose {
            case .plain:
                stackedLayout
            case .closed:
                focusLayout
            case .tented:
                tentedLayout
            case .openLandscape, .openPortrait, .book, .tabletop:
                if Self.poseOverride == nil, let split = foldSplit(pose) {
                    split
                } else {
                    previewSplit(pose)
                }
            }
        }
        .background(alignment: .topLeading) { HingeProbe(posture: $fold) }
        .background(alignment: .topLeading) {
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel(pose.rawValue)
                .accessibilityIdentifier("cookPose")
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { rootSize = geo.size }
                    .onChange(of: geo.size) { _, size in rootSize = size }
            }
        }
        .background((pose == .plain ? Theme.background : Color(Theme.recipeSideUI)).ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .alert("Timer done", isPresented: Binding(
            get: { !timers.finishedNames.isEmpty },
            set: { if !$0 { timers.dismissAlert() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(timers.finishedNames.first ?? "Your timer") is done.")
        }
    }

    // MARK: Unfolded poses (the hinge's own split)

    /// The arrangement-view split for the four unfolded poses. The arrangement puts the first
    /// pane leading (hinge top to bottom) or on top (hinge across).
    /// - Open flat landscape: recipe left, timers right.
    /// - Book: the same two pages, each a little narrower, with a gutter beside the hinge.
    /// - Open flat portrait: recipe on top, timers below.
    /// - Tabletop: the step on top to look at; ingredients, Back / Next and timers on the deck.
    private func foldSplit(_ pose: CookPose) -> AnyView? {
        #if FOLD_APIS
        if #available(iOS 27.1, *), fold.isUnfolded {
            let margin: CGFloat = 8
            let gutter = pose == .book ? Self.bookGutter : 0
            return AnyView(
                FoldSplitView(
                    primary: GeometryReader { pane in
                        if pose == .tabletop {
                            lookPane(compact: pane.size.width < 320, margin: margin)
                        } else {
                            recipePane(compact: pane.size.width < 320, tight: true, margin: margin, gutter: gutter,
                                       outer: pose == .book ? Self.bookOuterMargin : 0,
                                       short: pane.size.height < Self.shortPaneHeight)
                        }
                    }
                    .environment(timers)
                    .environment(\.colorScheme, .light),
                    secondary: GeometryReader { pane in
                        if pose == .tabletop {
                            deckPane(margin: margin)
                        } else {
                            // Converter pinned at the bottom and one-line timer rows, so the whole
                            // CONVERT card fits in the unfolded Duo's short half.
                            TimersPane(compact: pane.size.width < 320,
                                       dense: true,
                                       roomy: pane.size.height - 2 * margin >= Self.roomyPaneHeight,
                                       pinConverter: true,
                                       margin: margin,
                                       gutter: gutter,
                                       outer: pose == .book ? Self.bookOuterMargin : 0)
                        }
                    }
                    .environment(timers)
                    .environment(\.colorScheme, .light),
                    bookFold: pose == .book,
                    onHingeAxis: { hingeVertical = $0 }
                )
                .ignoresSafeArea(.container)
            )
        }
        #endif
        return nil
    }

    /// The same four layouts without a hinge, for COOK_POSE previews: two panes on the two
    /// cream tones, side by side or stacked.
    private func previewSplit(_ pose: CookPose) -> some View {
        let margin: CGFloat = 8
        let gutter = pose == .book ? Self.bookGutter : 0
        let half = Self.hingeGap / 2
        let pale = Color(Theme.recipeSideUI), warm = Color(Theme.timersSideUI)
        return GeometryReader { geo in
            if pose == .openLandscape || pose == .book {
                let outer = pose == .book ? Self.bookOuterMargin : 0
                HStack(spacing: 0) {
                    recipePane(compact: geo.size.width / 2 < 320, tight: true, margin: margin, gutter: gutter, outer: outer)
                        .padding(.trailing, half)
                        .frame(width: geo.size.width / 2)
                        .background(pale.ignoresSafeArea())
                    TimersPane(compact: geo.size.width / 2 < 320, dense: true, pinConverter: true, margin: margin,
                               gutter: gutter, outer: outer)
                        .padding(.leading, half)
                        .frame(width: geo.size.width / 2)
                        .background(warm.ignoresSafeArea())
                }
                .overlay {
                    if pose == .book { BookFold().frame(width: Self.hingeGap * 2) }
                }
            } else {
                // On a small screen the halves are short: use the compact text sizes there.
                let compact = geo.size.width < 320 || geo.size.height / 2 < 400
                VStack(spacing: 0) {
                    Group {
                        if pose == .tabletop {
                            lookPane(compact: compact, margin: margin)
                        } else {
                            recipePane(compact: compact, tight: true, margin: margin,
                                       short: geo.size.height / 2 < Self.shortPaneHeight)
                        }
                    }
                    .padding(.bottom, half)
                    .frame(height: geo.size.height / 2)
                    .background(pale.ignoresSafeArea())
                    Group {
                        if pose == .tabletop {
                            deckPane(margin: margin)
                        } else {
                            TimersPane(compact: true, dense: true, margin: margin)
                        }
                    }
                    .padding(.top, half)
                    .frame(height: geo.size.height / 2)
                    .background(warm.ignoresSafeArea())
                }
            }
        }
    }

    // MARK: Closed and tented (outer screen, one column)

    /// Closed: the timer chip stays pinned at the top; below it one thing at a time, the step
    /// (with ingredients, servings and Back / Next), the timers, or the converter.
    private var focusLayout: some View {
        VStack(spacing: 8) {
            TimerChipBar { focus = .timers }
                .padding(.horizontal, 16)
            HStack(spacing: 8) {
                ForEach(Focus.allCases, id: \.self) { item in
                    Button {
                        focus = item
                    } label: {
                        Text(item.rawValue)
                            .font(Theme.text(16, bold: true))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(SoftButtonStyle(fill: focus == item ? Theme.pill : Theme.beige,
                                                 foreground: focus == item ? .white : Theme.ink))
                    .accessibilityValue(focus == item ? "selected" : "")
                    .accessibilityIdentifier("focus_\(item.rawValue.lowercased())")
                }
            }
            .padding(.horizontal, 16)
            switch focus {
            case .step:
                recipePane(compact: rootSize.width < 380, tight: true)
            case .timers:
                TimersPane(compact: true, showConverter: false)
            case .convert:
                // The converter and a card of everyday conversions, centred in the space below
                // the pinned timer chip; scrolls if the screen is short.
                GeometryReader { geo in
                    ScrollView {
                        VStack(spacing: 14) {
                            ConverterView()
                            CommonConversions()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
                    }
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Tented: glanceable from across the counter. Just the step, big, its timer, the timer
    /// chip and Back / Next.
    private var tentedLayout: some View {
        let step = steps.isEmpty ? nil : steps[min(stepIndex, steps.count - 1)]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                exitButton
                progressLabel
                StepProgressBar(value: progressValue)
                    .accessibilityIdentifier("stepProgress")
            }
            TimerChipBar(onTap: nil)
            // The step and its timer sit in the middle of the space; a long step scrolls.
            let block = VStack(alignment: .leading, spacing: 16) {
                stepText(step, compact: false)
                if let minutes = step?.timerMinutes, minutes > 0 {
                    stepTimerButton(minutes: minutes)
                }
            }
            .padding(.vertical, 4)
            Spacer(minLength: 0)
            ViewThatFits(in: .vertical) {
                block
                ScrollView { block }.id(stepIndex)
            }
            Spacer(minLength: 0)
            navigationButtons(compact: false)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay { if finished { finishedOverlay } }
    }

    // MARK: Not a folding phone

    private var stackedLayout: some View {
        // Measure the whole screen (not just the safe area) so the gap sits on the physical
        // centre line, which is where a fold is. Safe-area insets are added back per pane.
        // The outer reader respects the safe area, so it reports the real insets; the inner one
        // ignores it, so its size is the full screen.
        GeometryReader { outer in
        let insets = outer.safeAreaInsets
        GeometryReader { geo in
            let size = geo.size
            let margin: CGFloat = 8
            let half = Self.hingeGap / 2
            let wide = size.width > size.height && size.width >= 560
            let compact = wide ? size.height < 500 : size.width < 500
            if wide {
                // Both cards get the width of the narrower side, so a status bar or camera inset
                // on one edge doesn't make one card thinner. They stay centred on the middle.
                let cardWidth = max(0, size.width / 2 - half - max(insets.leading, insets.trailing) - margin)
                HStack(spacing: 0) {
                    recipePane(compact: compact)
                        .frame(width: cardWidth)
                    HingeGap().frame(width: Self.hingeGap)
                    TimersPane(compact: compact,
                               dense: size.height - insets.top - insets.bottom - 2 * margin < Self.densePaneHeight,
                               roomy: size.height - insets.top - insets.bottom - 2 * margin >= Self.roomyPaneHeight)
                        .frame(width: cardWidth)
                }
                .padding(.top, insets.top + margin)
                .padding(.bottom, insets.bottom + margin)
                .frame(width: size.width)
            } else {
                VStack(spacing: 0) {
                    recipePane(compact: compact)
                        .frame(height: max(0, size.height / 2 - half - insets.top - margin))
                        .padding(.top, insets.top + margin)
                    HingeGap().frame(height: Self.hingeGap)
                    let timersHeight = max(0, size.height / 2 - half - insets.bottom - margin)
                    TimersPane(compact: compact, dense: timersHeight < Self.densePaneHeight)
                        .frame(height: timersHeight)
                        .padding(.bottom, insets.bottom + margin)
                }
                .padding(.leading, insets.leading + margin)
                .padding(.trailing, insets.trailing + margin)
            }
        }
        .ignoresSafeArea(.container)
        }
    }

    // MARK: Tabletop panes

    /// The top half on a tabletop: header, progress and the step, nothing to tap but ✕ and
    /// servings.
    private func lookPane(compact: Bool, margin: CGFloat) -> some View {
        let step = steps.isEmpty ? nil : steps[min(stepIndex, steps.count - 1)]
        return VStack(alignment: .leading, spacing: 8) {
            header(compact: compact)
            HStack(spacing: 12) {
                progressLabel
                StepProgressBar(value: progressValue)
                    .accessibilityIdentifier("stepProgress")
            }
            ScrollView {
                stepText(step, compact: compact)
            }
            .id(stepIndex)
        }
        .padding(.horizontal, compact ? 12 : 20)
        .padding(.vertical, 12)
        .padding(margin)
        .overlay { if finished { finishedOverlay } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipeCard")
    }

    /// The bottom half on a tabletop, the touch deck: ingredients (and the step's timer) on the
    /// left, timers on the right, in two equal columns, with Back / Next across the bottom,
    /// nearest the cook. Too narrow for two columns, it is one column under the timer chip.
    private func deckPane(margin: CGFloat) -> some View {
        let step = steps.isEmpty ? nil : steps[min(stepIndex, steps.count - 1)]
        return VStack(spacing: 8) {
            GeometryReader { geo in
                let touch = ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let minutes = step?.timerMinutes, minutes > 0 {
                            stepTimerButton(minutes: minutes, tight: true)
                        }
                        ingredientChecklist(tight: true)
                    }
                    .padding(.bottom, Self.fadeHeight + 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(stepIndex)
                .bottomFade(Self.fadeHeight)
                if geo.size.width < 520 {
                    VStack(alignment: .leading, spacing: 8) {
                        TimerChipBar(onTap: nil)
                        touch
                    }
                } else {
                    let column = max(0, (geo.size.width - 16) / 2)
                    HStack(alignment: .top, spacing: 16) {
                        touch.frame(width: column)
                        TimersPane(compact: true, dense: true, margin: 0)
                            .frame(width: column)
                    }
                }
            }
            navigationButtons(compact: true)
        }
        .padding(12)
        .padding(margin)
    }

    // MARK: Recipe pane

    private var steps: [RecipeStep] { recipe.sortedSteps }
    private var isLastStep: Bool { stepIndex >= steps.count - 1 }

    private var progressValue: Double {
        Double(min(stepIndex + 1, max(steps.count, 1))) / Double(max(steps.count, 1))
    }

    private var progressLabel: some View {
        Text("Step \(min(stepIndex + 1, steps.count)) of \(steps.count)")
            .font(Theme.text(17))
            .foregroundStyle(Theme.muted)
            .fixedSize()
            .accessibilityIdentifier("stepProgressLabel")
    }

    /// The current step: large Lato with open line spacing.
    private func stepText(_ step: RecipeStep?, compact: Bool, tight: Bool = false, size: CGFloat? = nil) -> some View {
        Text(step?.text ?? "This recipe has no steps yet.")
            .font(size.map { Theme.text($0) } ?? Theme.step(compact: compact))
            .lineSpacing(tight ? 3 : Theme.stepLineSpacing(compact: compact))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("stepText")
    }

    /// `tight`: a short pane (the unfolded Duo's halves, the closed Duo). Same fonts, but less
    /// spacing, the step count beside its bar and shorter Back / Next, so the ingredients show
    /// under a long step. `gutter`: extra room beside the hinge (book pose).
    /// `outer`: margin on the page's outer edge (book pose). `short`: a pane too short for the
    /// full header, so the title goes in the top row and the step keeps its room.
    private func recipePane(compact: Bool, tight: Bool = false, margin: CGFloat = 0, gutter: CGFloat = 0,
                            outer: CGFloat = 0, short: Bool = false) -> some View {
        let step = steps.isEmpty ? nil : steps[min(stepIndex, steps.count - 1)]
        let roomy = !compact && !tight
        return VStack(alignment: .leading, spacing: roomy ? 14 : (tight ? 6 : 8)) {
            if short {
                shortHeader
            } else {
                header(compact: compact)
            }
            let bar = StepProgressBar(value: progressValue)
                .accessibilityIdentifier("stepProgress")
            if tight {
                HStack(spacing: 12) { progressLabel; bar }
            } else {
                progressLabel
                bar
            }

            ScrollView {
                VStack(alignment: .leading, spacing: roomy ? 22 : (tight ? 10 : 14)) {
                    stepText(step, compact: compact, tight: tight, size: outer > 0 ? Self.bookStepSize : nil)

                    if let minutes = step?.timerMinutes, minutes > 0 {
                        stepTimerButton(minutes: minutes, tight: tight)
                    }

                    ingredientChecklist(tight: tight)
                }
                .padding(.top, tight ? 0 : 4)
                // Room under the last row, so it scrolls clear of the fade above Back / Next.
                .padding(.bottom, Self.fadeHeight + 4)
            }
            // Each step starts at its top, not where the last step was scrolled to.
            .id(stepIndex)
            .bottomFade(Self.fadeHeight)
            // The step and its list get the room; the header and buttons keep their own size.
            .layoutPriority(1)

            navigationButtons(compact: compact || tight)
        }
        // Tight trims only top and bottom: the sides keep the timers half's padding, so both
        // halves' content is the same width.
        .padding(.horizontal, compact ? 12 : 20)
        .padding(.vertical, roomy ? 20 : 12)
        .padding(.leading, outer)
        .padding(.vertical, outer > 0 ? 6 : 0)
        .padding(.trailing, gutter)
        .padding(margin)
        .overlay {
            if finished {
                finishedOverlay
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipeCard")
    }

    /// The black "Start N min timer" pill. Each timed step has its own; the timer it starts is
    /// named after the step, so several can run side by side.
    private func stepTimerButton(minutes: Int, tight: Bool = false) -> some View {
        Button {
            timers.add(name: "Step \(stepIndex + 1)", minutes: minutes)
        } label: {
            Label("Start \(minutes) min timer", systemImage: "play.fill")
                .font(Theme.text(20, bold: true))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 22)
                .frame(minHeight: tight ? 48 : 52)
        }
        .buttonStyle(SoftButtonStyle(fill: Theme.pill, foreground: .white))
        .accessibilityIdentifier("startStepTimer")
    }

    /// Height of the fade at the bottom of a scrolling list, where rows pass under Back / Next.
    static let fadeHeight: CGFloat = 16

    /// One row for a short pane: ✕, the title (up to two lines), and servings as − N +.
    private var shortHeader: some View {
        HStack(spacing: 10) {
            exitButton
            Text(recipe.title)
                .font(Theme.title(20))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            servingsControl(short: true)
        }
    }

    /// COOK MODE with servings on the right, then the recipe title (as in reference-design.png).
    private func header(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(spacing: 10) {
                exitButton
                // On one line, else one word per line; never broken inside a word. In a very
                // narrow page it gives way to the servings control.
                ViewThatFits(in: .horizontal) {
                    SectionLabel(text: "Cook Mode").fixedSize()
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(text: "Cook").fixedSize()
                        SectionLabel(text: "Mode").fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(text: "Cook", font: Theme.text(11, bold: true)).fixedSize()
                        SectionLabel(text: "Mode", font: Theme.text(11, bold: true)).fixedSize()
                    }
                    Color.clear.frame(width: 0, height: 0)
                }
                Spacer(minLength: 4)
                servingsControl()
            }
            Text(recipe.title)
                .font(Theme.title(compact ? 24 : 32))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let cuisine = recipe.cuisineKind {
                CuisineBadge(cuisine: cuisine, size: compact ? 12 : 13)
            }
        }
    }

    private var exitButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(SoftButtonStyle(circle: true))
        .accessibilityLabel("Exit Cook Mode")
        .accessibilityIdentifier("exitCook")
    }

    /// A beige pill: white − and + circles around "N servings".
    /// `short`: just the number between − and + (VoiceOver still reads "N servings").
    private func servingsControl(short: Bool = false) -> some View {
        HStack(spacing: 6) {
            Button {
                servings = max(1, servings - 1)
            } label: {
                Image(systemName: "minus").font(.headline).frame(width: 40, height: 40)
            }
            .accessibilityLabel("Fewer servings")
            .accessibilityIdentifier("servingsMinus")

            Text(short ? "\(servings)" : "\(servings) servings")
                .font(Theme.text(17, bold: true).monospacedDigit())
                .accessibilityLabel("\(servings) servings")
                .foregroundStyle(Theme.ink)
                .fixedSize()
                .accessibilityIdentifier("servingsLabel")

            Button {
                servings = min(99, servings + 1)
            } label: {
                Image(systemName: "plus").font(.headline).frame(width: 40, height: 40)
            }
            .accessibilityLabel("More servings")
            .accessibilityIdentifier("servingsPlus")
        }
        .buttonStyle(SoftButtonStyle(fill: Theme.card, circle: true))
        .padding(4)
        .background(Theme.beige, in: Capsule())
    }

    /// `tight`: a little less space between rows (same text size), so the heading and the first
    /// rows fit under a long step on the unfolded Duo.
    private func ingredientChecklist(tight: Bool) -> some View {
        VStack(alignment: .leading, spacing: tight ? 4 : 6) {
            SectionLabel(text: servings == recipe.servings ? "Ingredients" : "Ingredients · scaled for \(servings)",
                         color: Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, tight ? 0 : 4)
            ForEach(Array(recipe.sortedIngredients.enumerated()), id: \.element.id) { index, item in
                let done = checked.contains(item.persistentModelID)
                Button {
                    if done { checked.remove(item.persistentModelID) } else { checked.insert(item.persistentModelID) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: done ? "checkmark.square.fill" : "square")
                            .font(.title2)
                            .foregroundStyle(done ? Theme.accent : Theme.muted)
                            .accessibilityHidden(true)
                        // The amount in bold, fixed-width figures: 1/2 and 1/3 are told apart at a glance.
                        (Text(ingredientAmount(item, servingsFrom: recipe.servings, to: servings)).font(Theme.timer(20))
                         + Text(ingredientRest(item)).font(Theme.text(20)))
                            .strikethrough(done)
                            .foregroundStyle(done ? Theme.muted : Theme.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: tight ? 40 : 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(done ? "checked" : "not checked")
                .accessibilityIdentifier("ingredient_\(index)")
            }
        }
    }

    /// A narrow beige Back and a wide orange Next step.
    private func navigationButtons(compact: Bool) -> some View {
        let height: CGFloat = compact ? 56 : 76
        return HStack(spacing: 12) {
            Button {
                withAnimation { stepIndex = max(0, stepIndex - 1) }
            } label: {
                Label("Back", systemImage: "arrow.left")
                    .padding(.horizontal, 18)
                    .frame(minHeight: height)
            }
            .buttonStyle(SoftButtonStyle())
            .disabled(stepIndex == 0)
            .accessibilityIdentifier("backStep")

            if isLastStep {
                Button {
                    withAnimation { finished = true }
                } label: {
                    Label("Finish", systemImage: "checkmark")
                        .labelStyle(TrailingIconLabelStyle())
                        .frame(maxWidth: .infinity, minHeight: height)
                }
                .buttonStyle(SoftButtonStyle(fill: Theme.accent, foreground: .white))
                .accessibilityIdentifier("finishCooking")
            } else {
                Button {
                    withAnimation { stepIndex += 1 }
                } label: {
                    Label("Next step", systemImage: "arrow.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .frame(maxWidth: .infinity, minHeight: height)
                }
                .buttonStyle(SoftButtonStyle(fill: Theme.accent, foreground: .white))
                .accessibilityIdentifier("nextStep")
            }
        }
        .font(Theme.text(22, bold: true))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var finishedOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "party.popper.fill").font(.system(size: 56)).foregroundStyle(Theme.accent)
            Text("Enjoy your \(recipe.title)!")
                .font(Theme.title(28))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("finishedMessage")
            Button {
                dismiss()
            } label: {
                Text("Done").font(Theme.text(22, bold: true)).frame(maxWidth: 240, minHeight: 60)
            }
            .buttonStyle(SoftButtonStyle(fill: Theme.accent, foreground: .white))
            .accessibilityIdentifier("doneCooking")
            Button("Back to steps") {
                withAnimation { finished = false }
            }
            .font(Theme.text(17, bold: true))
            .tint(Theme.label)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pose == .plain ? Theme.background : Color(Theme.recipeSideUI))
    }
}

/// Orange fill on a beige track, rounded.
struct StepProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.beige)
                Capsule().fill(Theme.accent).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

/// The strip between the cards (where a hinge would be): empty cream, nothing drawn and
/// nothing tappable.
private struct HingeGap: View {
    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}

extension View {
    /// Rows that scroll under the bottom edge fade out instead of being cut by a hard line, so
    /// a half-visible ingredient never looks hidden behind Back / Next.
    func bottomFade(_ height: CGFloat) -> some View {
        mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
            }
        }
    }
}

/// The centre of an open book: a soft shade either side of the spine. Decorative only: it is
/// drawn under the hinge's reserved region, takes no taps and is hidden from VoiceOver.
struct BookFold: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0), location: 0),
            .init(color: .black.opacity(0.07), location: 0.5),
            .init(color: .black.opacity(0), location: 1),
        ], startPoint: .leading, endPoint: .trailing)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
