import SwiftUI
import CookCore

/// The timers half, as in reference-design.png: TIMERS, "Always on this side", running timers,
/// QUICK TIMER pills and the converter, straight on the cream page (no pane card).
struct TimersPane: View {
    let compact: Bool
    /// Short pane: tighter spacing, one row of presets and one-line timer rows.
    var dense = false
    /// Tall pane (iPad): room for the explanatory line under the title.
    var roomy = false
    /// Keep CONVERT fully on screen below the scrolling timers (unfolded Duo's short half).
    var pinConverter = false
    @Environment(TimerStore.self) private var store
    @State private var name = ""
    @State private var minutes = 5
    @FocusState private var nameFocused: Bool

    private static let presets = [1, 5, 10, 15, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 6 : (compact ? 8 : 12)) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Timers")
                    .accessibilityIdentifier("timersHeader")
                Spacer()
                if !store.timers.isEmpty {
                    Text("\(store.timers.count) active").font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
            if !compact {
                Text("Always on this side")
                    .font(Theme.title(28))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if roomy {
                    Text("Change steps, check ingredients — these never leave the screen.")
                        .font(.body)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            quickTimers

            ScrollView {
                VStack(alignment: .leading, spacing: dense ? 6 : 10) {
                    if store.timers.isEmpty {
                        Text("No timers yet. Tap a quick timer, or start one from a step.")
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    }
                    ForEach(store.timers) { timer in
                        TimerCard(timer: timer, now: store.now, compact: compact, dense: dense)
                    }
                    customTimer
                        .padding(.top, 6)
                    if !pinConverter {
                        ConverterView()
                            .padding(.top, 6)
                    }
                }
                .padding(.vertical, 2)
            }
            if pinConverter {
                ConverterView()
            }
        }
        .padding(compact ? 12 : 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timersCard")
    }

    /// QUICK TIMER: black pills that start right away (using the name, if typed). Wrapped like
    /// the reference; one row when the pane is short.
    @ViewBuilder
    private var quickTimers: some View {
        if dense {
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.self) { preset in
                    presetButton(preset, title: "\(preset)m")
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Quick timer", color: Theme.muted)
                FlowLayout(spacing: 10) {
                    ForEach(Self.presets, id: \.self) { preset in
                        presetButton(preset, title: "\(preset) min")
                    }
                }
            }
        }
    }

    private func presetButton(_ preset: Int, title: String) -> some View {
        Button {
            start(preset)
        } label: {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, dense ? 6 : 18)
                .frame(maxWidth: dense ? .infinity : nil, minHeight: dense ? 32 : 44)
        }
        .buttonStyle(SoftButtonStyle(fill: Theme.pill, foreground: .white))
        .accessibilityLabel("Start \(preset) minute timer")
        .accessibilityIdentifier("preset_\(preset)")
    }

    /// Any length, with an optional name.
    private var customTimer: some View {
        HStack(spacing: 8) {
            TextField("Name (optional)", text: $name)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .focused($nameFocused)
                .accessibilityIdentifier("timerName")
            HStack(spacing: 2) {
                Text("\(minutes)m").font(.headline).monospacedDigit().foregroundStyle(Theme.ink).frame(minWidth: 36)
                Stepper("Minutes", value: $minutes, in: 1...600)
                    .labelsHidden()
                    .accessibilityIdentifier("timerMinutes")
            }
            Button {
                start(minutes)
            } label: {
                Text("Start").font(.headline).padding(.horizontal, 16).frame(minHeight: 36)
            }
            .buttonStyle(SoftButtonStyle(fill: Theme.pill, foreground: .white))
            .accessibilityIdentifier("startCustomTimer")
        }
    }

    private func start(_ minutes: Int) {
        store.add(name: name, minutes: minutes)
        name = ""
        nameFocused = false
    }
}

/// Lays children out left to right and wraps to a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map { $0.width }.max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty && row.width + spacing + size.width > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
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
                        Text(timer.name).font(.subheadline.bold()).foregroundStyle(Theme.ink).lineLimit(1)
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
                        Text(timer.name).font(.headline).foregroundStyle(Theme.ink).lineLimit(1)
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
        .background(done ? Color.red.opacity(0.18) : Theme.card,
                    in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private func countdown(done: Bool, size: CGFloat) -> some View {
        Text(TimeFormat.countdown(timer.remaining(at: now)))
            .font(Theme.timer(size))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(done ? Color.red : (timer.isPaused ? Theme.muted : Theme.ink))
            .accessibilityIdentifier("timerCountdown_\(timer.name)")
    }

    @ViewBuilder
    private func status(done: Bool) -> some View {
        if done {
            Text("Done!").foregroundStyle(.red)
        } else if timer.isPaused {
            Text("Paused").foregroundStyle(Theme.muted)
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
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .background(Theme.beige, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// CONVERT: an always-open white card, as in reference-design.png.
struct ConverterView: View {
    @State private var category: ConversionCategory = .volume
    @State private var input = "1"
    @State private var from: CookingUnit = .cup
    @State private var to: CookingUnit = .milliliter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Convert", color: Theme.muted)
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
                    .font(.title3)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: 110, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.beige, lineWidth: 2))
                    .accessibilityIdentifier("converterInput")
                unitPicker("From", selection: $from)
                Button {
                    swap(&from, &to)
                } label: {
                    Image(systemName: "arrow.left.arrow.right").frame(width: 36, height: 36)
                }
                .buttonStyle(SoftButtonStyle(circle: true))
                .accessibilityLabel("Swap units")
                unitPicker("To", selection: $to)
            }

            Text(result)
                .font(Theme.timer(28))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("converterResult")
        }
        .tint(Theme.ink)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
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
