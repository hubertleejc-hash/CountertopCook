import SwiftUI
import SwiftData
import CookCore

func ingredientLine(_ item: Ingredient, servingsFrom base: Int, to servings: Int) -> String {
    let amount = Scaler.scale(item.amountText, from: base, to: servings)
    return [amount, item.unit, item.name].filter { !$0.isEmpty }.joined(separator: " ")
}

/// Cook Mode: the recipe and the timers are always on screen together.
/// - Wide (unfolded, landscape, iPad): recipe left, timers right, 50/50.
/// - Tall (closed phone, portrait, tented): recipe step on top, timers below, 50/50.
/// A clear gap runs down the middle of either split so no button ever sits on a fold.
struct CookModeView: View {
    let recipe: Recipe
    @Environment(TimerStore.self) private var timers
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex = 0
    @State private var servings: Int
    @State private var checked: Set<PersistentIdentifier> = []
    @State private var finished = false

    /// Width of the empty strip kept between the two panes (where a hinge would be).
    static let hingeGap: CGFloat = 28

    init(recipe: Recipe) {
        self.recipe = recipe
        _servings = State(initialValue: recipe.servings)
    }

    var body: some View {
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
                HStack(spacing: 0) {
                    recipePane(compact: compact)
                        .frame(width: max(0, size.width / 2 - half - insets.leading - margin))
                        .padding(.leading, insets.leading + margin)
                    HingeGap(vertical: true).frame(width: Self.hingeGap)
                    TimersPane(compact: compact)
                        .frame(width: max(0, size.width / 2 - half - insets.trailing - margin))
                        .padding(.trailing, insets.trailing + margin)
                }
                .padding(.top, insets.top + margin)
                .padding(.bottom, insets.bottom + margin)
            } else {
                VStack(spacing: 0) {
                    recipePane(compact: compact)
                        .frame(height: max(0, size.height / 2 - half - insets.top - margin))
                        .padding(.top, insets.top + margin)
                    HingeGap(vertical: false).frame(height: Self.hingeGap)
                    TimersPane(compact: compact)
                        .frame(height: max(0, size.height / 2 - half - insets.bottom - margin))
                        .padding(.bottom, insets.bottom + margin)
                }
                .padding(.leading, insets.leading + margin)
                .padding(.trailing, insets.trailing + margin)
            }
        }
        .ignoresSafeArea(.container)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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

    // MARK: Recipe pane

    private var steps: [RecipeStep] { recipe.sortedSteps }
    private var isLastStep: Bool { stepIndex >= steps.count - 1 }

    private func recipePane(compact: Bool) -> some View {
        let step = steps.isEmpty ? nil : steps[min(stepIndex, steps.count - 1)]
        return VStack(spacing: compact ? 8 : 14) {
            header
            ProgressView(value: Double(min(stepIndex + 1, max(steps.count, 1))), total: Double(max(steps.count, 1)))
                .tint(.orange)
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .accessibilityIdentifier("stepProgress")

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(step?.text ?? "This recipe has no steps yet.")
                        .font(.system(size: compact ? 26 : 38, weight: .semibold, design: .rounded))
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
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .accessibilityIdentifier("startStepTimer")
                    }

                    ingredientChecklist
                }
                .padding(.vertical, 4)
            }

            navigationButtons(compact: compact)
        }
        .padding(compact ? 12 : 20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            if finished {
                finishedOverlay
            }
        }
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
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Exit Cook Mode")
            .accessibilityIdentifier("exitCook")

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title).font(.headline).lineLimit(1)
                Text("Step \(min(stepIndex + 1, steps.count)) of \(steps.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
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
                Image(systemName: "minus").frame(width: 32, height: 36)
            }
            .accessibilityLabel("Fewer servings")
            .accessibilityIdentifier("servingsMinus")

            VStack(spacing: 0) {
                Text("\(servings)").font(.title3.bold()).monospacedDigit()
                Text("servings").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(minWidth: 48)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("servingsLabel")

            Button {
                servings = min(99, servings + 1)
            } label: {
                Image(systemName: "plus").frame(width: 32, height: 36)
            }
            .accessibilityLabel("More servings")
            .accessibilityIdentifier("servingsPlus")
        }
        .buttonStyle(.bordered)
    }

    private var ingredientChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(servings == recipe.servings ? "Ingredients" : "Ingredients · scaled for \(servings)")
                .font(.headline)
                .padding(.top, 8)
            ForEach(Array(recipe.sortedIngredients.enumerated()), id: \.element.id) { index, item in
                let done = checked.contains(item.persistentModelID)
                Button {
                    if done { checked.remove(item.persistentModelID) } else { checked.insert(item.persistentModelID) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(done ? Color.green : Color.secondary)
                            .accessibilityHidden(true)
                        Text(ingredientLine(item, servingsFrom: recipe.servings, to: servings))
                            .font(.title3)
                            .strikethrough(done)
                            .foregroundStyle(done ? Color.secondary : Color.primary)
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
            .buttonStyle(.bordered)
            .disabled(stepIndex == 0)
            .accessibilityIdentifier("backStep")

            if isLastStep {
                Button {
                    withAnimation { finished = true }
                } label: {
                    Label("Finish", systemImage: "checkmark")
                        .frame(maxWidth: .infinity, minHeight: height)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("finishCooking")
            } else {
                Button {
                    withAnimation { stepIndex += 1 }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .frame(maxWidth: .infinity, minHeight: height)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityIdentifier("nextStep")
            }
        }
        .font(.title2.bold())
    }

    private var finishedOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "party.popper.fill").font(.system(size: 56)).foregroundStyle(.orange)
            Text("Enjoy your \(recipe.title)!")
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("finishedMessage")
            Button {
                dismiss()
            } label: {
                Text("Done").font(.title2.bold()).frame(maxWidth: 240, minHeight: 60)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("doneCooking")
            Button("Back to steps") {
                withAnimation { finished = false }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

/// The non-interactive strip between the panes. Purely decorative; nothing tappable lives here.
private struct HingeGap: View {
    let vertical: Bool

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: vertical ? 4 : 44, height: vertical ? 44 : 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
