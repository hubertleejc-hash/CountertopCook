import SwiftUI
import CookCore

struct TimersPane: View {
    let compact: Bool
    /// Short pane: tighter spacing and one-line timer rows.
    var dense = false
    @Environment(TimerStore.self) private var store
    @State private var name = ""
    @State private var minutes = 5
    @FocusState private var nameFocused: Bool

    private static let presets = [1, 5, 10, 15, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 6 : (compact ? 8 : 12)) {
            HStack {
                Label("Timers", systemImage: "timer")
                    .font(.title2.bold())
                    .accessibilityIdentifier("timersHeader")
                Spacer()
                if !store.timers.isEmpty {
                    Text("\(store.timers.count) active").foregroundStyle(.secondary)
                }
            }

            addBar

            ScrollView {
                VStack(spacing: dense ? 6 : 10) {
                    if store.timers.isEmpty {
                        Text("No timers yet. Tap a preset, or start one from a step.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    ForEach(store.timers) { timer in
                        TimerCard(timer: timer, now: store.now, compact: compact, dense: dense)
                    }
                    ConverterView()
                        .padding(.top, 6)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(compact ? 12 : 20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    /// Name + minutes + Start, and one-tap presets that start right away (using the name, if typed).
    private var addBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Name (optional)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .accessibilityIdentifier("timerName")
                HStack(spacing: 2) {
                    Text("\(minutes)m").font(.headline).monospacedDigit().frame(minWidth: 36)
                    Stepper("Minutes", value: $minutes, in: 1...600)
                        .labelsHidden()
                        .accessibilityIdentifier("timerMinutes")
                }
                Button("Start") { start(minutes) }
                    .buttonStyle(.borderedProminent)
                    .font(.headline)
                    .accessibilityIdentifier("startCustomTimer")
            }
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.self) { preset in
                    Button {
                        start(preset)
                    } label: {
                        Text("\(preset)m").font(.headline).frame(maxWidth: .infinity, minHeight: dense ? 26 : 36)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Start \(preset) minute timer")
                    .accessibilityIdentifier("preset_\(preset)")
                }
            }
        }
    }

    private func start(_ minutes: Int) {
        store.add(name: name, minutes: minutes)
        name = ""
        nameFocused = false
    }
}

struct TimerCard: View {
    let timer: CookTimer
    let now: Date
    let compact: Bool
    /// One-line row for short panes, so several timers stay on screen at once.
    var dense = false
    @Environment(TimerStore.self) private var store

    var body: some View {
        let done = timer.isFinished(at: now)
        Group {
            if dense {
                HStack(spacing: 8) {
                    countdown(done: done, size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(timer.name).font(.subheadline.bold()).lineLimit(1)
                        status(done: done).font(.caption.bold())
                    }
                    Spacer(minLength: 4)
                    buttons(done: done, size: 44)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(timer.name).font(.headline).lineLimit(1)
                        Spacer()
                        status(done: done).font(.headline)
                    }
                    HStack(spacing: 8) {
                        countdown(done: done, size: compact ? 40 : 56)
                        Spacer(minLength: 4)
                        buttons(done: done, size: 48)
                    }
                }
                .padding(12)
            }
        }
        .background(done ? Color.red.opacity(0.18) : Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private func countdown(done: Bool, size: CGFloat) -> some View {
        Text(TimeFormat.countdown(timer.remaining(at: now)))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(done ? Color.red : (timer.isPaused ? Color.secondary : Color.primary))
            .accessibilityIdentifier("timerCountdown_\(timer.name)")
    }

    @ViewBuilder
    private func status(done: Bool) -> some View {
        if done {
            Text("Done!").foregroundStyle(.red)
        } else if timer.isPaused {
            Text("Paused").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func buttons(done: Bool, size: CGFloat) -> some View {
        if !done {
            iconButton(timer.isPaused ? "play.fill" : "pause.fill",
                       label: timer.isPaused ? "Resume" : "Pause",
                       id: "timerPause_\(timer.name)", size: size) { store.togglePause(timer.id) }
        }
        iconButton("goforward.plus", label: "Add 1 minute", id: "timerAddMinute_\(timer.name)", size: size) {
            store.addMinute(timer.id)
        }
        iconButton("xmark", label: done ? "Dismiss" : "Cancel", id: "timerCancel_\(timer.name)", size: size) {
            store.cancel(timer.id)
        }
    }

    private func iconButton(_ symbol: String, label: String, id: String, size: CGFloat,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.bold())
                .foregroundStyle(Color.accentColor)
                .frame(width: size, height: size)
                .background(Color(.systemFill), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

struct ConverterView: View {
    @State private var expanded = false
    @State private var category: ConversionCategory = .volume
    @State private var input = "1"
    @State private var from: CookingUnit = .cup
    @State private var to: CookingUnit = .milliliter

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Type", selection: $category) {
                    ForEach(ConversionCategory.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: category) { _, newValue in
                    switch newValue {
                    case .volume: from = .cup; to = .milliliter
                    case .weight: from = .ounce; to = .gram
                    case .temperature: from = .fahrenheit; to = .celsius
                    }
                }

                HStack(spacing: 6) {
                    TextField("1 1/2", text: $input)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 90)
                        .accessibilityIdentifier("converterInput")
                    unitPicker("From", selection: $from)
                    Button {
                        swap(&from, &to)
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .accessibilityLabel("Swap units")
                    unitPicker("To", selection: $to)
                }

                Text(result)
                    .font(.title2.bold())
                    .monospacedDigit()
                    .accessibilityIdentifier("converterResult")
            }
            .padding(.top, 8)
        } label: {
            Label("Converter", systemImage: "scalemass").font(.headline)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var result: String {
        guard let value = Converter.convert(text: input, from: from, to: to) else { return "Enter a number" }
        return "= \(Converter.format(value)) \(to.rawValue)"
    }

    private func unitPicker(_ title: String, selection: Binding<CookingUnit>) -> some View {
        Picker(title, selection: selection) {
            ForEach(category.units) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}
