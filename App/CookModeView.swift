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
/// One cream page runs under both cards and the gap; the two cards are always the same size.
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
                        recipePane(compact: pane.size.height < 500 || pane.size.width < 320)
                            .padding(margin)
                    }
                    .environment(timers)
                    .environment(\.colorScheme, .light),
                    secondary: GeometryReader { pane in
                        TimersPane(compact: pane.size.height < 500 || pane.size.width < 320,
                                   dense: pane.size.height - 2 * margin < Self.densePaneHeight)
                            .padding(margin)
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
                               dense: size.height - insets.top - insets.bottom - 2 * margin < Self.densePaneHeight)
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

    private func recipePane(compact: Bool) -> some View {
        let step = steps.isEmpty ? nil : steps[min(stepIndex, steps.count - 1)]
        return VStack(spacing: compact ? 8 : 14) {
            header
            ProgressView(value: Double(min(stepIndex + 1, max(steps.count, 1))), total: Double(max(steps.count, 1)))
                .tint(Theme.accent)
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .accessibilityIdentifier("stepProgress")

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(step?.text ?? "This recipe has no steps yet.")
                        .font(Theme.step)
                        .lineSpacing(Theme.stepLineSpacing)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("stepText")

                    if let minutes = step?.timerMinutes, minutes > 0 {
                        Button {
                            timers.add(name: "Step \(stepIndex + 1)", minutes: minutes)
                        } label: {
                            Label("Start \(minutes) min timer", systemImage: "timer")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(SoftButtonStyle(fill: Theme.accent, foreground: .white))
                        .accessibilityIdentifier("startStepTimer")
                    }

                    ingredientChecklist
                }
                .padding(.vertical, 4)
            }

            navigationButtons(compact: compact)
        }
        .padding(compact ? 12 : 20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay {
            if finished {
                finishedOverlay
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipeCard")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(SoftButtonStyle(circle: true))
            .accessibilityLabel("Exit Cook Mode")
            .accessibilityIdentifier("exitCook")

            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "Cook Mode", font: .caption.weight(.heavy))
                Text(recipe.title)
                    .font(Theme.title(20))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("Step \(min(stepIndex + 1, steps.count)) of \(steps.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("stepProgressLabel")
            }
            Spacer(minLength: 4)
            servingsControl
        }
    }

    private var servingsControl: some View {
        HStack(spacing: 4) {
            Button {
                servings = max(1, servings - 1)
            } label: {
                Image(systemName: "minus").font(.headline).frame(width: 40, height: 40)
            }
            .accessibilityLabel("Fewer servings")
            .accessibilityIdentifier("servingsMinus")

            VStack(spacing: 0) {
                Text("\(servings)").font(.title3.bold()).monospacedDigit().foregroundStyle(Theme.ink)
                Text("servings").font(.caption2).foregroundStyle(Theme.muted)
            }
            .frame(minWidth: 48)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("servingsLabel")

            Button {
                servings = min(99, servings + 1)
            } label: {
                Image(systemName: "plus").font(.headline).frame(width: 40, height: 40)
            }
            .accessibilityLabel("More servings")
            .accessibilityIdentifier("servingsPlus")
        }
        .buttonStyle(SoftButtonStyle(circle: true))
    }

    private var ingredientChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(servings == recipe.servings ? "Ingredients" : "Ingredients · scaled for \(servings)")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .padding(.top, 8)
            ForEach(Array(recipe.sortedIngredients.enumerated()), id: \.element.id) { index, item in
                let done = checked.contains(item.persistentModelID)
                Button {
                    if done { checked.remove(item.persistentModelID) } else { checked.insert(item.persistentModelID) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
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
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(done ? "checked" : "not checked")
                .accessibilityIdentifier("ingredient_\(index)")
            }
        }
    }

    private func navigationButtons(compact: Bool) -> some View {
        let height: CGFloat = compact ? 56 : 76
        return HStack(spacing: 12) {
            Button {
                withAnimation { stepIndex = max(0, stepIndex - 1) }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, minHeight: height)
            }
            .buttonStyle(SoftButtonStyle())
            .disabled(stepIndex == 0)
            .accessibilityIdentifier("backStep")

            if isLastStep {
                Button {
                    withAnimation { finished = true }
                } label: {
                    Label("Finish", systemImage: "checkmark")
                        .frame(maxWidth: .infinity, minHeight: height)
                }
                .buttonStyle(SoftButtonStyle(fill: Theme.accent, foreground: .white))
                .accessibilityIdentifier("finishCooking")
            } else {
                Button {
                    withAnimation { stepIndex += 1 }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .frame(maxWidth: .infinity, minHeight: height)
                }
                .buttonStyle(SoftButtonStyle(fill: Theme.accent, foreground: .white))
                .accessibilityIdentifier("nextStep")
            }
        }
        .font(.title2.bold())
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
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
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
