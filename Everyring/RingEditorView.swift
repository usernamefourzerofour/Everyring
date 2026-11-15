import SwiftUI

/// Edits one ring: metric → goal → period → name, colour and icon, with a live preview.
struct RingEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ring: Ring
    /// The goal in the display unit (km, mi, kcal, …).
    @State private var displayGoal: Double
    @State private var nameEdited: Bool
    @State private var goalEdited: Bool
    @State private var confirmDelete = false

    private let isNew: Bool
    private let showsCancel: Bool
    private let previewValue: Double?
    private let onSave: (Ring) -> Void
    private let onDelete: (() -> Void)?

    /// - Parameters:
    ///   - ring: the ring to edit, or a new ring's defaults (`isNew`).
    ///   - previewValue: the ring's current value, for the preview; `nil` shows 70 %.
    init(ring: Ring, isNew: Bool, showsCancel: Bool = false, previewValue: Double? = nil,
         onSave: @escaping (Ring) -> Void, onDelete: (() -> Void)? = nil) {
        _ring = State(initialValue: ring)
        _displayGoal = State(initialValue: Self.rounded(ring.metric.toDisplay(ring.goal)))
        _nameEdited = State(initialValue: !isNew)
        _goalEdited = State(initialValue: !isNew)
        self.isNew = isNew
        self.showsCancel = showsCancel
        self.previewValue = previewValue
        self.onSave = onSave
        self.onDelete = onDelete
    }

    /// Goals are entered with at most two decimals (62.137… mi shows as 62.14).
    static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private var edited: Ring {
        var r = ring
        r.goal = ring.metric.fromDisplay(displayGoal)
        return r
    }

    var body: some View {
        Form {
            Section {
                RingPreview(ring: edited, value: previewValue)
            }

            Section("Health data") {
                NavigationLink {
                    MetricPickerView(selection: $ring.metric)
                } label: {
                    HStack {
                        Text("Metric")
                        Spacer()
                        Text(ring.metric.title)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if case .workouts(let measure, let kind) = ring.metric {
                    Picker("Count", selection: Binding(
                        get: { measure },
                        set: { ring.metric = .workouts($0, kind: $0 == .distance && kind?.hasDistance == false ? nil : kind) }
                    )) {
                        Text("Workouts").tag(WorkoutMeasure.count)
                        Text("Minutes").tag(WorkoutMeasure.minutes)
                        Text("Distance").tag(WorkoutMeasure.distance)
                    }
                    Picker("Type", selection: Binding(
                        get: { kind },
                        set: { ring.metric = .workouts(measure, kind: $0) }
                    )) {
                        Text("All workouts").tag(WorkoutKind?.none)
                        ForEach(WorkoutKind.allCases.filter { measure != .distance || $0.hasDistance }, id: \.self) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(Optional(kind))
                        }
                    }
                }
            }

            Section {
                HStack {
                    TextField("Goal", value: Binding(
                        get: { displayGoal },
                        set: { displayGoal = $0; goalEdited = true }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    Text(ring.metric.unitName())
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Goal")
            } footer: {
                if displayGoal <= 0 { Text("The goal must be more than zero.") }
            }

            Section {
                PeriodPicker(period: $ring.period)
            } header: {
                Text("Period")
            } footer: {
                Text(ring.period.isRolling
                     ? LocalizedStringKey("The ring always shows the last days up to now. Old days drop out as new ones begin, so it can also go down. Stay above your goal.")
                     : "The ring fills up during the period and starts over when the next one begins. Close it before the period ends.")
            }

            Section("Appearance") {
                TextField("Name", text: Binding(
                    get: { ring.name },
                    set: { ring.name = $0; nameEdited = true }
                ))
                ColorRow(selection: $ring.color)
                SymbolGrid(selection: $ring.symbol, color: ring.color)
            }

            if let onDelete, !isNew {
                Section {
                    Button("Delete Ring", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Delete this ring?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete Ring", role: .destructive) {
                                onDelete()
                                dismiss()
                            }
                        }
                }
            }
        }
        .navigationTitle(isNew ? "New Ring" : "Edit Ring")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Done", role: .confirm) {
                    var r = edited
                    if r.name.trimmingCharacters(in: .whitespaces).isEmpty { r.name = r.metric.title }
                    onSave(r)
                    dismiss()
                }
                .disabled(displayGoal <= 0)
            }
        }
        .onChange(of: ring.metric) { old, new in
            if !nameEdited { ring.name = new.title }
            if !nameEdited || ring.symbol == old.defaultSymbol { ring.symbol = new.defaultSymbol }
            // A goal in another unit makes no sense; start from a suggestion.
            if old.baseUnit != new.baseUnit { goalEdited = false }
            if !goalEdited { displayGoal = Self.rounded(new.toDisplay(new.suggestedGoal(for: ring.period))) }
        }
        .onChange(of: ring.period) { _, period in
            if !goalEdited { displayGoal = Self.rounded(ring.metric.toDisplay(ring.metric.suggestedGoal(for: period))) }
        }
    }
}

/// The ring as it will look, with its name, goal and period.
struct RingPreview: View {
    let ring: Ring
    let value: Double?

    var body: some View {
        let fraction = value.map { ring.fraction($0) } ?? 0.7
        HStack(spacing: 16) {
            RingStackView(rings: [RingDisplay(id: ring.id, color: ring.color, fraction: fraction)])
                .frame(width: 88, height: 88)
                .overlay {
                    Image(systemName: ring.symbol)
                        .font(.title2)
                        .foregroundStyle(ring.color.color)
                }
                .animation(.smooth, value: fraction)
            VStack(alignment: .leading, spacing: 4) {
                Text(ring.name.isEmpty ? ring.metric.title : ring.name)
                    .font(.headline)
                Text(ring.metric.format(ring.goal))
                    .font(.subheadline)
                Text(ring.period.status())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct MetricPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: HealthMetric

    var body: some View {
        List {
            ForEach(HealthMetric.Category.allCases) { category in
                Section(category.title) {
                    ForEach(category.metrics, id: \.self) { metric in
                        Button {
                            // Keep a chosen workout kind when switching between workout measures.
                            if case .workouts(_, let kind) = selection, case .workouts(let measure, _) = metric {
                                selection = .workouts(measure, kind: measure == .distance && kind?.hasDistance == false ? nil : kind)
                            } else {
                                selection = metric
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Label(metric.title, systemImage: metric.defaultSymbol)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isSelected(metric) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .accessibilityLabel("Selected")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Metric")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isSelected(_ metric: HealthMetric) -> Bool {
        if case .workouts(let a, _) = selection, case .workouts(let b, _) = metric { return a == b }
        return selection == metric
    }
}

/// Fixed (resets) or rolling periods, with presets and custom lengths.
struct PeriodPicker: View {
    @Binding var period: RingPeriod
    /// Show the custom rolling stepper even when N happens to match a preset.
    @State private var customRolling = false

    private enum Kind: Hashable { case fixed, rolling }
    private enum FixedChoice: Hashable { case today, week, month, custom }
    private enum CustomUnit: Hashable { case days, weeks }

    var body: some View {
        Picker("Type", selection: kind) {
            Text("Resets").tag(Kind.fixed)
            Text("Rolling").tag(Kind.rolling)
        }
        .pickerStyle(.segmented)
        .listRowSeparator(.hidden)

        if period.isRolling {
            Picker("Window", selection: rollingChoice) {
                ForEach(RingPeriod.rollingPresets, id: \.self) { preset in
                    Text(preset.title).tag(preset.nominalDays)
                }
                Text("Custom").tag(0)
            }
            if rollingChoice.wrappedValue == 0 {
                Stepper(value: rollingDays, in: RingPeriod.rollingRange) {
                    Text("Last \(rollingDays.wrappedValue) days")
                }
            }
        } else {
            Picker("Period", selection: fixedChoice) {
                Text("Today").tag(FixedChoice.today)
                Text("This week").tag(FixedChoice.week)
                Text("This month").tag(FixedChoice.month)
                Text("Custom").tag(FixedChoice.custom)
            }
            if fixedChoice.wrappedValue == .custom {
                Picker("Repeat", selection: customUnit) {
                    Text("Days").tag(CustomUnit.days)
                    Text("Weeks").tag(CustomUnit.weeks)
                }
                .pickerStyle(.segmented)
                Stepper(value: customCount, in: customUnit.wrappedValue == .days ? RingPeriod.customDaysRange
                                                                                  : RingPeriod.customWeeksRange) {
                    Text(period.title)
                }
                DatePicker("Starting", selection: customAnchor, displayedComponents: .date)
            }
        }
    }

    private var kind: Binding<Kind> {
        Binding(get: { period.isRolling ? .rolling : .fixed },
                set: { period = $0 == .rolling ? .rollingDays(7) : .thisWeek; customRolling = false })
    }

    private var rollingDays: Binding<Int> {
        Binding(get: { period.nominalDays }, set: { period = .rollingDays($0) })
    }

    private var rollingChoice: Binding<Int> {
        Binding(
            get: {
                let n = period.nominalDays
                let isPreset = RingPeriod.rollingPresets.contains(.rollingDays(n))
                return customRolling || !isPreset ? 0 : n
            },
            set: { n in
                if n == 0 {
                    customRolling = true
                } else {
                    customRolling = false
                    period = .rollingDays(n)
                }
            })
    }

    private var fixedChoice: Binding<FixedChoice> {
        Binding(
            get: {
                switch period {
                case .today: .today
                case .thisWeek: .week
                case .thisMonth: .month
                default: .custom
                }
            },
            set: { choice in
                switch choice {
                case .today: period = .today
                case .week: period = .thisWeek
                case .month: period = .thisMonth
                case .custom: period = .everyWeeks(2, from: Calendar.current.startOfDay(for: .now))
                }
            })
    }

    private var customUnit: Binding<CustomUnit> {
        Binding(
            get: { if case .everyDays = period { .days } else { .weeks } },
            set: { unit in
                let anchor = customAnchor.wrappedValue
                period = unit == .days ? .everyDays(10, from: anchor) : .everyWeeks(2, from: anchor)
            })
    }

    private var customCount: Binding<Int> {
        Binding(
            get: {
                switch period {
                case .everyDays(let n, _), .everyWeeks(let n, _): n
                default: 1
                }
            },
            set: { n in
                switch period {
                case .everyDays(_, let from): period = .everyDays(n, from: from)
                case .everyWeeks(_, let from): period = .everyWeeks(n, from: from)
                default: break
                }
            })
    }

    private var customAnchor: Binding<Date> {
        Binding(
            get: {
                switch period {
                case .everyDays(_, let from), .everyWeeks(_, let from): from
                default: Calendar.current.startOfDay(for: .now)
                }
            },
            set: { date in
                let day = Calendar.current.startOfDay(for: date)
                switch period {
                case .everyDays(let n, _): period = .everyDays(n, from: day)
                case .everyWeeks(let n, _): period = .everyWeeks(n, from: day)
                default: break
                }
            })
    }
}

struct ColorRow: View {
    @Binding var selection: RingColor

    var body: some View {
        HStack {
            ForEach(RingColor.allCases, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(LinearGradient(colors: [color.gradient.start, color.gradient.end],
                                             startPoint: .bottomLeading, endPoint: .topTrailing))
                        .frame(width: 30, height: 30)
                        .overlay {
                            if selection == color {
                                Circle().strokeBorder(.background, lineWidth: 3)
                                Circle().strokeBorder(color.color, lineWidth: 1.5).padding(-3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

struct SymbolGrid: View {
    @Binding var selection: String
    let color: RingColor

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 8)], spacing: 8) {
            ForEach(Ring.symbols, id: \.self) { symbol in
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(selection == symbol ? .white : .primary)
                        .background(selection == symbol ? AnyShapeStyle(color.color.gradient)
                                                        : AnyShapeStyle(.fill.tertiary), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                .accessibilityAddTraits(selection == symbol ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        RingEditorView(ring: .new(), isNew: true) { _ in }
    }
}
