import SwiftUI
import SwiftData
import CookCore

func ingredientLine(_ item: Ingredient, servingsFrom base: Int, to servings: Int) -> String {
    let amount = Scaler.scale(item.amountText, from: base, to: servings)
    return [amount, item.unit, item.name].filter { !$0.isEmpty }.joined(separator: " ")
}

/// Cook Mode: the recipe and the timers are always on screen together.
/// - Unfolded iPhone Duo (hinge partially or fully open): a `UIArrangementViewController` split,
///   recipe leading or on top, timers trailing or below, with the gap on the hinge's reserved
///   region (see FoldSplit.swift).
/// - Otherwise, wide (landscape, iPad): recipe left, timers right, 50/50.
/// - Otherwise, tall (closed Duo, portrait phone): recipe step on top, timers below, 50/50.
/// Off the Duo split, a clear gap runs down the middle so no button sits on the centre line.
/// Styled after reference-design.png: one cream page under both halves and the gap, with nothing
/// drawn on the hinge; the two halves are always the same size.
struct CookModeView: View {
    let recipe: Recipe
    @Environment(TimerStore.self) private var timers
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex = 0
    @State private var servings: Int
    @State private var checked: Set<PersistentIdentifier> = []
    @State private var finished = false
    @State private var fold = FoldPosture.none

    /// Width of the empty strip kept between the two panes (where a hinge would be).
    static let hingeGap: CGFloat = 28
    /// Below this timers-pane height, timers switch to one-line rows so several stay visible.
    static let densePaneHeight: CGFloat = 420
    /// From this timers-pane height up there's room for the line under "Always on this side".
    static let roomyPaneHeight: CGFloat = 760

    init(recipe: Recipe) {
        self.recipe = recipe
        _servings = State(initialValue: recipe.servings)
    }

    var body: some View {
        Group {
            if let split = foldSplit {
                split
            } else {
                stackedLayout
            }
        }
        .background(alignment: .topLeading) { HingeProbe(posture: $fold) }
        .background(Theme.background.ignoresSafeArea())
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

    /// The arrangement-view split, only while an iPhone Duo's hinge is open.
    private var foldSplit: AnyView? {
        #if FOLD_APIS
        if #available(iOS 27.1, *), fold.isUnfolded {
            let margin: CGFloat = 8
            return AnyView(
                FoldSplitView(
                    primary: GeometryReader { pane in
                        recipePane(compact: pane.size.height < 500 || pane.size.width < 320, tight: true,
                                   margin: margin)
                    }
                    .environment(timers)
                    .environment(\.colorScheme, .light),
                    secondary: GeometryReader { pane in
                        // Converter pinned at the bottom and one-line timer rows, so the whole
                        // CONVERT card fits in the unfolded Duo's short half.
                        TimersPane(compact: pane.size.height < 500 || pane.size.width < 320,
                                   dense: true,
                                   roomy: pane.size.height - 2 * margin >= Self.roomyPaneHeight,
                                   pinConverter: true,
                                   margin: margin)
                    }
                    .environment(timers)
                    .environment(\.colorScheme, .light)
                )
                .ignoresSafeArea(.container)
            )
        }
        #endif
        return nil
    }

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

    // MARK: Recipe pane

    private var steps: [RecipeStep] { recipe.sortedSteps }
    private var isLastStep: Bool { stepIndex >= steps.count - 1 }

    /// `tight`: the unfolded Duo's short half. Same fonts, but less spacing, the step count
    /// beside its bar and shorter Back / Next, so the ingredients show under a long step.
    private func recipePane(compact: Bool, tight: Bool = false, margin: CGFloat = 0) -> some View {
        let step = steps.isEmpty ? nil : steps[min(stepIndex, steps.count - 1)]
        let roomy = !compact && !tight
        return VStack(alignment: .leading, spacing: roomy ? 14 : 8) {
            header(compact: compact)
            let progress = Text("Step \(min(stepIndex + 1, steps.count)) of \(steps.count)")
                .font(.headline.weight(.regular))
                .foregroundStyle(Theme.muted)
                .fixedSize()
                .accessibilityIdentifier("stepProgressLabel")
            let bar = StepProgressBar(value: Double(min(stepIndex + 1, max(steps.count, 1))) / Double(max(steps.count, 1)))
                .accessibilityIdentifier("stepProgress")
            if tight {
                HStack(spacing: 12) { progress; bar }
            } else {
                progress
                bar
            }

            ScrollView {
                VStack(alignment: .leading, spacing: roomy ? 22 : (tight ? 10 : 14)) {
                    Text(step?.text ?? "This recipe has no steps yet.")
                        .font(Theme.step(compact: compact))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("stepText")

                    if let minutes = step?.timerMinutes, minutes > 0 {
                        Button {
                            timers.add(name: "Step \(stepIndex + 1)", minutes: minutes)
                        } label: {
                            Label("Start \(minutes) min timer", systemImage: "play.fill")
                                .font(.title3.weight(.semibold))
                                .padding(.horizontal, 22)
                                .frame(minHeight: 52)
                        }
                        .buttonStyle(SoftButtonStyle(fill: Theme.pill, foreground: .white))
                        .accessibilityIdentifier("startStepTimer")
                    }

                    ingredientChecklist(tight: tight)
                }
                .padding(.vertical, tight ? 0 : 4)
            }

            navigationButtons(compact: compact || tight)
        }
        // Tight trims only top and bottom: the sides keep the timers half's padding, so both
        // halves' content is the same width.
        .padding(.horizontal, compact ? 12 : 20)
        .padding(.vertical, roomy ? 20 : 12)
        .padding(margin)
        .overlay {
            if finished {
                finishedOverlay
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipeCard")
    }

    /// COOK MODE with servings on the right, then the recipe title (as in reference-design.png).
    private func header(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(spacing: 10) {
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
                SectionLabel(text: "Cook Mode")
                Spacer(minLength: 4)
                servingsControl
            }
            Text(recipe.title)
                .font(Theme.title(compact ? 24 : 32))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    /// A beige pill: white − and + circles around "N servings".
    private var servingsControl: some View {
        HStack(spacing: 6) {
            Button {
                servings = max(1, servings - 1)
            } label: {
                Image(systemName: "minus").font(.headline).frame(width: 40, height: 40)
            }
            .accessibilityLabel("Fewer servings")
            .accessibilityIdentifier("servingsMinus")

            Text("\(servings) servings")
                .font(.headline.weight(.medium))
                .monospacedDigit()
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
                        Text(ingredientLine(item, servingsFrom: recipe.servings, to: servings))
                            .font(.title3)
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
        .font(.title2.weight(.semibold))
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
                Text("Done").font(.title2.bold()).frame(maxWidth: 240, minHeight: 60)
            }
            .buttonStyle(SoftButtonStyle(fill: Theme.accent, foreground: .white))
            .accessibilityIdentifier("doneCooking")
            Button("Back to steps") {
                withAnimation { finished = false }
            }
            .font(.headline)
            .tint(Theme.label)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

/// Orange fill on a beige track, rounded.
private struct StepProgressBar: View {
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
