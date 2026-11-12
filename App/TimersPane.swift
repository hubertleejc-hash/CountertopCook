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
    /// Outer margin around the pane (CookModeView's fold split).
    var margin: CGFloat = 0
    /// Extra room beside the hinge (book pose).
    var gutter: CGFloat = 0
    /// Margin on the page's outer edge (book pose).
    var outer: CGFloat = 0
    /// False where the converter has its own place (the closed Duo's Convert focus).
    var showConverter = true
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
                    Text("\(store.timers.count) active").font(Theme.text(15)).foregroundStyle(Theme.muted)
                }
            }
            if !compact {
                Text("Always on this side")
                    .font(Theme.text(28, bold: true))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if roomy {
                    Text("Change steps, check ingredients — these never leave the screen.")
                        .font(Theme.text(17))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            quickTimers

            ScrollView {
                VStack(alignment: .leading, spacing: dense ? 6 : 10) {
                    if store.timers.isEmpty {
                        Text("No timers yet. Tap a quick timer, or start one from a step.")
                            .font(Theme.text(17))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    }
                    ForEach(store.timers) { timer in
                        TimerCard(timer: timer, now: store.now, compact: compact, dense: dense)
                    }
                    customTimer
                        .padding(.top, 6)
                    if !pinConverter && showConverter {
                        ConverterView()
                            .padding(.top, 6)
                    }
                }
                .padding(.vertical, 2)
            }
            if pinConverter && showConverter {
                ConverterView()
            }
        }
        .padding(compact ? 12 : 20)
        .padding(.leading, gutter)
        .padding(.trailing, outer)
        .padding(.vertical, outer > 0 ? 6 : 0)
        .padding(margin)
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
                .font(Theme.text(17, bold: true))
                .lineLimit(1)
                .padding(.horizontal, dense ? 6 : 18)
                .frame(maxWidth: dense ? .infinity : nil, minHeight: dense ? 32 : 44)
        }
        .buttonStyle(SoftButtonStyle(fill: Theme.pill, foreground: Theme.onPill))
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
                Text("\(minutes)m").font(Theme.timer(17)).foregroundStyle(Theme.ink).frame(minWidth: 36)
                Stepper("Minutes", value: $minutes, in: 1...600)
                    .labelsHidden()
                    .accessibilityIdentifier("timerMinutes")
            }
            Button {
                start(minutes)
            } label: {
                Text("Start").font(Theme.text(17, bold: true)).lineLimit(1).fixedSize().padding(.horizontal, 16).frame(minHeight: 36)
            }
            .buttonStyle(SoftButtonStyle(fill: Theme.pill, foreground: Theme.onPill))
            .accessibilityIdentifier("startCustomTimer")
        }
    }

    private func start(_ minutes: Int) {
        store.add(name: name, minutes: minutes)
        name = ""
        nameFocused = false
    }
}

/// Running timers as a row of chips, name and countdown, always on screen. Used where there is
/// no room for the whole timers pane (closed and tented poses). A finished timer turns red.
struct TimerChipBar: View {
    /// Tapping a chip opens the timers (nil: chips are display only).
    var onTap: (() -> Void)?
    @Environment(TimerStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.headline)
                    .foregroundStyle(Theme.label)
                    .accessibilityHidden(true)
                if store.timers.isEmpty {
                    Text("No timers running")
                        .font(Theme.text(15))
                        .foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("timerChipEmpty")
                }
                ForEach(store.timers) { timer in
                    let done = timer.isFinished(at: store.now)
                    HStack(spacing: 6) {
                        Text(timer.name)
                            .font(Theme.text(14, bold: true))
                            .foregroundStyle(done ? Color.red : Theme.muted)
                            .lineLimit(1)
                        Text(TimeFormat.countdown(timer.remaining(at: store.now)))
                            .font(Theme.timer(18))
                            .foregroundStyle(done ? Color.red : (timer.isPaused ? Theme.muted : Theme.ink))
                            .accessibilityIdentifier("timerCountdown_\(timer.name)")
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(done ? Color.red.opacity(0.18) : Theme.card, in: Capsule())
                    .accessibilityElement(children: .contain)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timerChipBar")
    }
}

/// Everyday kitchen conversions at a glance, worked out by the same converter as the card above.
struct CommonConversions: View {
    private static let rows: [(String, CookingUnit, CookingUnit)] = [
        ("1", .cup, .milliliter), ("1", .tablespoon, .milliliter), ("1", .teaspoon, .milliliter),
        ("1", .ounce, .gram), ("1", .pound, .gram),
        ("350", .fahrenheit, .celsius), ("400", .fahrenheit, .celsius), ("425", .fahrenheit, .celsius),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Common conversions", color: Theme.muted)
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                if let value = Converter.convert(text: row.0, from: row.1, to: row.2) {
                    HStack {
                        Text("\(row.0) \(row.1.rawValue)")
                            .font(Theme.text(17))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 8)
                        Text("\(Converter.format(value)) \(row.2.rawValue)")
                            .font(Theme.timer(17))
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(minHeight: 28)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("commonConversions")
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
                        Text(timer.name).font(Theme.text(15, bold: true)).foregroundStyle(Theme.ink).lineLimit(1)
                        status(done: done).font(Theme.text(12, bold: true))
                    }
                    Spacer(minLength: 4)
                    buttons(done: done, size: 44)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(timer.name).font(Theme.text(17, bold: true)).foregroundStyle(Theme.ink).lineLimit(1)
                        Spacer()
                        status(done: done).font(Theme.text(17, bold: true))
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

/// CONVERT: an always-open white card, as in reference-design.png. Three pair chips
/// (cups → ml, oz → g, °F → °C) pick the kind of conversion and are always on screen; the
/// unit menus below them pick any other unit of that kind.
struct ConverterView: View {
    @State private var category: ConversionCategory = .volume
    @State private var input = "1"
    @State private var from: CookingUnit = .cup
    @State private var to: CookingUnit = .milliliter

    private static let pairs: [(ConversionCategory, CookingUnit, CookingUnit, String)] = [
        (.volume, .cup, .milliliter, "cups → ml"), (.weight, .ounce, .gram, "oz → g"),
        (.temperature, .fahrenheit, .celsius, "°F → °C"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Convert", color: Theme.muted)
            FlowLayout(spacing: 8) {
                ForEach(Self.pairs, id: \.0) { pair in
                    let selected = category == pair.0
                    Button {
                        category = pair.0
                        from = pair.1
                        to = pair.2
                    } label: {
                        Text(pair.3)
                            .font(Theme.text(15, bold: true))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                    }
                    .buttonStyle(SoftButtonStyle(fill: selected ? Theme.pill : Theme.beige,
                                                 foreground: selected ? Theme.onPill : Theme.ink))
                    .accessibilityValue(selected ? "selected" : "")
                    .accessibilityIdentifier("converterPair_\(pair.0.rawValue)")
                }
            }

            HStack(spacing: 6) {
                TextField("1", text: $input)
                    .keyboardType(.numbersAndPunctuation)
                    .font(Theme.timer(20))
                    .padding(.horizontal, 10)
                    .frame(width: 64, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.beige, lineWidth: 2))
                    .accessibilityIdentifier("converterInput")
                unitPicker("From", selection: $from)
                    .accessibilityIdentifier("converterFrom")
                Button {
                    swap(&from, &to)
                } label: {
                    Image(systemName: "arrow.left.arrow.right").font(.subheadline.bold()).frame(width: 32, height: 32)
                }
                .buttonStyle(SoftButtonStyle(circle: true))
                .accessibilityLabel("Swap units")
                unitPicker("To", selection: $to)
                    .accessibilityIdentifier("converterTo")
                Spacer(minLength: 0)
            }

            Text(result)
                .font(Theme.timer(26))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier("converterResult")
        }
        .tint(Theme.ink)
        .padding(14)
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
        .fixedSize()
    }
}
