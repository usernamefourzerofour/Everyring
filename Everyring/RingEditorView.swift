import SwiftUI

/// Edits one ring: metric → goal → period → name, colour and icon, with a live preview.
struct RingEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ring: Ring
    /// The goal in the display unit (km, mi, kcal, …); a number of days for a days-reaching ring.
    @State private var displayGoal: Double
    /// A days-reaching ring's daily target in the display unit.
    @State private var displayTarget: Double
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
        _displayGoal = State(initialValue: ring.isDaysReaching ? ring.goal.rounded() : Self.rounded(ring.metric.toDisplay(ring.goal)))
        _displayTarget = State(initialValue: Self.rounded(ring.metric.toDisplay(
            ring.dailyTarget > 0 ? ring.dailyTarget : ring.metric.suggestedGoal(for: .today))))
        _nameEdited = State(initialValue: !isNew)
        _goalEdited = State(initialValue: !isNew)
        self.isNew = isNew
        self.showsCancel = showsCancel
        self.previewValue = previewValue
        self.onSave = onSave
        self.onDelete = onDelete
    }

    /// "20 min", "1 hr 30 min".
    static func minutesText(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// Goals are entered with at most two decimals (62.137… mi shows as 62.14).
    static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private var edited: Ring {
        var r = ring
        if ring.isDaysReaching {
            r.goal = max(1, displayGoal.rounded())
            let same = abs(Self.rounded(ring.metric.toDisplay(ring.dailyTarget)) - displayTarget) < 0.000_001
            if !same { r.dailyTarget = ring.metric.fromDisplay(displayTarget) }
            return r
        }
        // Keep the exact stored goal unless the user changed the (rounded) number shown.
        let unchanged = abs(Self.rounded(ring.metric.toDisplay(ring.goal)) - displayGoal) < 0.000_001
        if !unchanged { r.goal = ring.metric.fromDisplay(displayGoal) }
        return r
    }

    /// The most days a days-reaching goal can ask for in one period (about: a month counts 30 days).
    private var maxDays: Int {
        let n = Double(ring.period.nominalDays)
        let perWeek = Double(ring.countedDaysPerWeek(calendar: Calendar.current))
        return perWeek >= 7 ? Int(n) : max(1, Int((n * perWeek / 7).rounded(.up)))
    }

    /// A days-reaching goal to start from: most days of the period (5 days a week).
    private var suggestedDays: Double {
        max(1, (Double(maxDays) * 5 / 7).rounded())
    }

    private var goalIsValid: Bool {
        ring.isDaysReaching ? displayGoal >= 1 && displayTarget > 0 : displayGoal > 0
    }

    /// Whether the ring can be saved.
    private var isValid: Bool {
        goalIsValid && (workoutLengthsAreValid || !edited.usesWorkoutLengths)
    }

    /// Only workouts between these lengths count (workout rings, and activity rings that count only during workouts).
    /// Any whole number of minutes; empty means any length.
    @ViewBuilder private var workoutLengthPickers: some View {
        minutesField("Shortest workout", value: $ring.minimumWorkoutMinutes)
        minutesField("Longest workout", value: $ring.maximumWorkoutMinutes)
        if !workoutLengthsAreValid {
            Text("The longest workout must be longer than the shortest.")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func minutesField(_ title: LocalizedStringKey, value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Any", value: Binding<Int?>(
                get: { value.wrappedValue > 0 ? value.wrappedValue : nil },
                set: { value.wrappedValue = max(0, $0 ?? 0) }
            ), format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 90)
            Text("min")
                .foregroundStyle(.secondary)
        }
    }

    /// No range that leaves out every workout.
    private var workoutLengthsAreValid: Bool {
        ring.maximumWorkoutMinutes == 0 || ring.maximumWorkoutMinutes > ring.minimumWorkoutMinutes
    }

    var body: some View {
        Form {
            Section {
                RingPreview(ring: edited, value: previewValue)
            }

            Section {
                NavigationLink {
                    MetricPickerView(selection: $ring.metric)
                } label: {
                    HStack {
                        Text("Metric")
                        Spacer()
                        // Workouts: the kinds have their own row below, so name only the category here.
                        Text(ring.metric.pickerTitle)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if ring.metric.supportsWorkoutLeaveOut {
                    Picker("Activity", selection: $ring.activity) {
                        Text("All activity").tag(ActivityScope.all)
                        Text("Only during workouts").tag(ActivityScope.duringWorkouts)
                        Text("Only background activity").tag(ActivityScope.outsideWorkouts)
                    }
                    let leftOut = WorkoutFilter.make(ring.leftOutWorkouts, excludes: true)
                    // Background activity already leaves out every workout.
                    if ring.activity != .outsideWorkouts {
                        NavigationLink {
                            WorkoutFilterView(measure: .minutes, excludeOnly: true, metricTitle: ring.metric.title,
                                              onlyDuringWorkouts: ring.activity == .duringWorkouts,
                                              filter: Binding(get: { leftOut },
                                                              set: { ring.leftOutWorkouts = $0?.kinds ?? [] }))
                        } label: {
                            HStack {
                                Text("Leave out workouts")
                                Spacer()
                                Text(leftOut?.listed ?? String(localized: "None"))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    // Which workouts count as workouts, when the ring counts only during or only outside them.
                    if ring.activity != .all {
                        workoutLengthPickers
                    }
                }
                if case .workouts(let measure, let filter) = ring.metric {
                    Picker("Count", selection: Binding(
                        get: { measure },
                        set: { ring.metric = .workouts($0, kind: WorkoutFilter.adapted(filter, to: $0)) }
                    )) {
                        Text("Workouts").tag(WorkoutMeasure.count)
                        Text("Minutes").tag(WorkoutMeasure.minutes)
                        Text("Distance").tag(WorkoutMeasure.distance)
                    }
                    NavigationLink {
                        WorkoutFilterView(measure: measure, filter: Binding(
                            get: { filter },
                            set: { ring.metric = .workouts(measure, kind: $0) }
                        ))
                    } label: {
                        HStack {
                            Text("Types")
                            Spacer()
                            Text(WorkoutFilter.summary(filter))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    workoutLengthPickers
                }
                NavigationLink {
                    SourcesView(metric: ring.metric, selection: $ring.sources)
                } label: {
                    HStack {
                        Text("Sources")
                        Spacer()
                        Text(ring.sources.isEmpty ? String(localized: "All") : String(localized: "\(ring.sources.count) selected"))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Health data")
            } footer: {
                if ring.metric.supportsWorkoutLeaveOut {
                    switch ring.activity {
                    case .all: EmptyView()
                    case .duringWorkouts:
                        Text("Counts only what was logged while a workout ran. Background activity, like walking around or taking the stairs, is left out.")
                    case .outsideWorkouts:
                        Text("Counts only background activity, like walking around or taking the stairs. What was logged while a workout ran is left out.")
                    }
                }
            }

            Section {
                Picker("Goal type", selection: $ring.goalKind) {
                    Text("Reach").tag(GoalKind.reach)
                    Text("Stay under").tag(GoalKind.limit)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                if ring.period.nominalDays > 1 {
                    Picker("Count", selection: $ring.aggregation) {
                        Text("Total").tag(GoalAggregation.total)
                        Text("Average").tag(GoalAggregation.dailyAverage)
                        Text("Days").tag(GoalAggregation.daysReaching)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }
                if ring.isAverage {
                    Toggle("Skip days without data", isOn: $ring.averageSkipsEmptyDays)
                }
                if ring.isDaysReaching {
                    HStack {
                        Text(ring.goalKind == .limit ? "Each day under" : "Each day at least")
                        TextField("Target", value: Binding(
                            get: { displayTarget },
                            set: { displayTarget = $0; goalEdited = true }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        Text(ring.metric.unitName())
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: Binding(get: { Int(displayGoal) }, set: { displayGoal = Double($0); goalEdited = true }),
                            in: 1...maxDays) {
                        Text(Int(displayGoal) == 1 ? "On 1 day" : "On \(Int(displayGoal)) days")
                    }
                } else {
                    HStack {
                        TextField(ring.isLimit ? "Limit" : "Goal", value: Binding(
                            get: { displayGoal },
                            set: { displayGoal = $0; goalEdited = true }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        Text(ring.isAverage ? String(localized: "\(ring.metric.unitName()) a day") : ring.metric.unitName())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Goal")
            } footer: {
                if !goalIsValid {
                    Text("The goal must be more than zero.")
                } else if ring.isDaysReaching {
                    Text(ring.goalKind == .limit
                         ? LocalizedStringKey("Counts the days you log something and stay under the target. The ring closes when you've done it on \(Int(displayGoal)) days in the period.")
                         : "Counts the days that reach the target. The ring closes when you've done it on \(Int(displayGoal)) days in the period.")
                } else if ring.isAverage {
                    Text(ring.averageSkipsEmptyDays
                         ? LocalizedStringKey("A daily average: the ring compares your average per day over the period with the goal. Days without any data, such as a night without your watch, are left out.")
                         : "A daily average: the ring compares your average per day over the period with the goal. Days without data count as zero.")
                } else if ring.isLimit {
                    Text("A limit: the ring turns red when you go over it. A period counts when you logged something and stayed under.")
                } else {
                    Text("A goal to reach: the ring closes at 100 % and can go on past it.")
                }
            }

            // Right after the goal: what happens when it's reached (a limit never closes).
            if !ring.isLimit {
                Section {
                    Picker("When closed", selection: $ring.whenClosed) {
                        ForEach(ClosedAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("When the goal is reached")
                } footer: {
                    switch ring.whenClosed {
                    case .show: Text("The ring stays as it is.")
                    case .fade: Text("The ring turns pale and matte on the home screen, in widgets and on the watch, so rings still to do stand out.")
                    case .hide: Text("The ring disappears from the home screen, widgets and the watch until its next period. Its place stays empty, so the other rings don't move.")
                    }
                }
            }

            Section {
                PeriodPicker(period: $ring.period)
                if ring.period.nominalDays > 1 {
                    Picker("Days", selection: $ring.days) {
                        ForEach(DayFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if ring.days == .custom {
                        WeekdayPicker(selection: $ring.customDays)
                    }
                }
            } header: {
                Text("Period")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ring.period.isRolling
                         ? LocalizedStringKey("The ring always shows the last days up to now. Old days drop out as new ones begin, so it can also go down. Stay above your goal.")
                         : "The ring fills up during the period and starts over when the next one begins. Close it before the period ends.")
                    switch ring.effectiveDays {
                    case .everyDay: EmptyView()
                    case .weekdays: Text("Only weekdays count: what you do at the weekend is left out.")
                    case .weekends: Text("Only weekends count: what you do on weekdays is left out.")
                    case .custom: Text("Only the days you pick count: what you do on the others is left out.")
                    }
                }
            }

            Section {
                TextField("Name", text: Binding(
                    get: { ring.name },
                    set: { ring.name = $0; nameEdited = true }
                ))
                ColorRow(selection: $ring.color, custom: $ring.customTint)
                ColorPicker("Custom colour", selection: Binding(
                    get: { ring.customTint?.color ?? ring.color.color },
                    set: { ring.customTint = RingTint($0) }
                ), supportsOpacity: false)
                SymbolGrid(selection: $ring.symbol, color: ring.accent)
            } header: {
                Text("Appearance")
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
                .disabled(!isValid)
            }
        }
        .task(id: ring.metric) {
            // Ask for access to the chosen Health type right away, while the editor is open, instead of after saving.
            // Let the metric list finish closing first; HealthKit only shows the sheet for types not asked before.
            guard !RingsModel.isDemo else { return }
            try? await Task.sleep(for: .milliseconds(450))
            try? await HealthManager.shared.requestAuthorization(for: [ring.metric])
        }
        .onChange(of: ring.metric) { old, new in
            // A name that is still the old metric's own name follows the metric; one the user wrote stays.
            let nameIsDefault = ring.name.trimmingCharacters(in: .whitespaces).isEmpty || ring.name == old.title
            if !nameEdited || nameIsDefault {
                ring.name = new.title
                nameEdited = false
            }
            // Likewise the icon: the old metric's icon follows, one the user picked stays.
            if ring.symbol == old.defaultSymbol { ring.symbol = new.defaultSymbol }
            // And the colour: the old metric's colour follows, one the user picked stays.
            if ring.customTint == nil && ring.color == old.defaultColor { ring.color = new.defaultColor }
            // Sources and left-out workouts belong to the old metric's data.
            if !old.isSameKind(as: new) { ring.sources = [] }
            if !new.supportsWorkoutLeaveOut {
                ring.leftOutWorkouts = []
                ring.activity = .all
            }
            // A goal in another unit makes no sense; start from a suggestion.
            if old.baseUnit != new.baseUnit { goalEdited = false }
            if !goalEdited {
                ring.goalKind = new.defaultGoalKind
                if ring.isDaysReaching {
                    displayTarget = Self.rounded(new.toDisplay(new.suggestedGoal(for: .today)))
                } else {
                    displayGoal = Self.rounded(new.toDisplay(new.suggestedGoal(for: ring.isAverage ? .today : ring.period)))
                }
            }
        }
        .onChange(of: ring.period) { old, period in
            let wasDays = ring.aggregation == .daysReaching && old.nominalDays > 1
            if wasDays != ring.isDaysReaching {
                // Into or out of counting days (a one-day period can't count days): the day's target and the goal
                // trade places.
                if ring.isDaysReaching {
                    displayTarget = displayGoal
                    displayGoal = suggestedDays
                } else {
                    displayGoal = displayTarget
                }
            } else if ring.isDaysReaching {
                displayGoal = goalEdited ? min(displayGoal, Double(maxDays)) : suggestedDays
            } else if !goalEdited {
                // An average goal is per day, so it stays the same when the period changes.
                displayGoal = Self.rounded(ring.metric.toDisplay(ring.metric.suggestedGoal(for: ring.isAverage ? .today : period)))
            }
        }
        .onChange(of: ring.days) { _, days in
            // Start custom days from the weekdays.
            if days == .custom && ring.customDays.isEmpty {
                ring.customDays = (1...7).filter { $0 != 1 && $0 != 7 }
            }
            if ring.isDaysReaching { displayGoal = min(displayGoal, Double(maxDays)) }
        }
        .onChange(of: ring.customDays) {
            if ring.isDaysReaching { displayGoal = min(displayGoal, Double(maxDays)) }
        }
        .onChange(of: ring.aggregation) { old, new in
            // Keep the goal meaning the same: a week's 70,000 steps is 10,000 a day, or 10,000 on 5 days.
            let days = Double(ring.period.nominalDays)
            guard days > 1, old != new else { return }
            // What one day is worth in the old way of counting.
            let perDay: Double = switch old {
            case .total: displayGoal / days
            case .dailyAverage: displayGoal
            case .daysReaching: displayTarget
            }
            switch new {
            case .total: displayGoal = Self.rounded(perDay * days)
            case .dailyAverage: displayGoal = Self.rounded(perDay)
            case .daysReaching:
                displayTarget = Self.rounded(perDay)
                displayGoal = suggestedDays
            }
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
            RingStackView(rings: [RingDisplay(id: ring.id, start: ring.gradient.start, end: ring.gradient.end, fraction: fraction)])
                .frame(width: 88, height: 88)
                .overlay {
                    Image(systemName: ring.symbol)
                        .font(.title2)
                        .foregroundStyle(ring.accent)
                }
                .animation(.smooth, value: fraction)
            VStack(alignment: .leading, spacing: 4) {
                Text(ring.name.isEmpty ? ring.metric.title : ring.name)
                    .font(.headline)
                Text(ring.goalText)
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

/// The Health metrics by category. Picks a metric for an existing ring (`selection`), or starts a new ring (`onPick`).
struct MetricPickerView: View {
    @Environment(\.dismiss) private var dismiss
    private let current: HealthMetric?
    private let onPick: (HealthMetric) -> Void
    private let dismissesOnPick: Bool
    private let title: LocalizedStringKey

    /// Changes the metric of a ring being edited, then goes back.
    init(selection: Binding<HealthMetric>) {
        current = selection.wrappedValue
        onPick = { metric in
            // Keep the chosen workout kinds when switching between workout measures.
            if case .workouts(_, let filter) = selection.wrappedValue, case .workouts(let measure, _) = metric {
                selection.wrappedValue = .workouts(measure, kind: WorkoutFilter.adapted(filter, to: measure))
            } else {
                selection.wrappedValue = metric
            }
        }
        dismissesOnPick = true
        title = "Metric"
    }

    /// The first step of a new ring: the caller moves on to the ring editor.
    init(onPick: @escaping (HealthMetric) -> Void) {
        current = nil
        self.onPick = onPick
        dismissesOnPick = false
        title = "New Ring"
    }

    var body: some View {
        List {
            ForEach(HealthMetric.Category.offered) { category in
                Section(category.title) {
                    ForEach(category.metrics, id: \.self) { metric in
                        Button {
                            onPick(metric)
                            if dismissesOnPick { dismiss() }
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isSelected(_ metric: HealthMetric) -> Bool {
        guard let current else { return false }
        return current.isSameKind(as: metric)
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
    /// A freely picked colour; picking a palette colour clears it.
    @Binding var custom: RingTint?

    var body: some View {
        HStack {
            ForEach(RingColor.allCases, id: \.self) { color in
                let isSelected = custom == nil && selection == color
                Button {
                    selection = color
                    custom = nil
                } label: {
                    Circle()
                        .fill(LinearGradient(colors: [color.gradient.start, color.gradient.end],
                                             startPoint: .bottomLeading, endPoint: .topTrailing))
                        .frame(width: 30, height: 30)
                        .overlay {
                            if isSelected {
                                Circle().strokeBorder(.background, lineWidth: 3)
                                Circle().strokeBorder(color.color, lineWidth: 1.5).padding(-3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

struct SymbolGrid: View {
    @Binding var selection: String
    let color: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 8)], spacing: 8) {
            // Only icons this system has (newer SF Symbols would show as empty circles on older ones).
            ForEach(Ring.symbols(including: selection).filter { UIImage(systemName: $0) != nil }, id: \.self) { symbol in
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(selection == symbol ? .white : .primary)
                        .background(selection == symbol ? AnyShapeStyle(color.gradient)
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

extension RingTint {
    /// The sRGB components of a colour picked in the colour picker.
    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(min(1, max(0, r))), green: Double(min(1, max(0, g))), blue: Double(min(1, max(0, b))))
    }
}

/// Picks the kinds of workouts a ring counts: all, only some, or all except some.
struct WorkoutFilterView: View {
    let measure: WorkoutMeasure
    /// Activity rings (steps, exercise minutes, …): workouts can only be left out (most activity is background
    /// activity, not workouts, so "only these" would mislead).
    var excludeOnly = false
    /// For `excludeOnly`: what is left out, "Steps".
    var metricTitle = ""
    /// For `excludeOnly`: the ring counts only activity during workouts (so background activity is already left out).
    var onlyDuringWorkouts = false
    @Binding var filter: WorkoutFilter?
    @State private var kinds: Set<WorkoutKind>
    @State private var excludes: Bool

    init(measure: WorkoutMeasure, excludeOnly: Bool = false, metricTitle: String = "", onlyDuringWorkouts: Bool = false,
         filter: Binding<WorkoutFilter?>) {
        self.measure = measure
        self.excludeOnly = excludeOnly
        self.metricTitle = metricTitle
        self.onlyDuringWorkouts = onlyDuringWorkouts
        _filter = filter
        _kinds = State(initialValue: Set(filter.wrappedValue?.kinds ?? []))
        _excludes = State(initialValue: excludeOnly || filter.wrappedValue?.excludes == true)
    }

    /// Alphabetical in the user's language.
    private var available: [WorkoutKind] {
        WorkoutKind.allCases
            .filter { measure != .distance || $0.hasDistance }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        Form {
            if !excludeOnly {
                Section {
                    Picker("Mode", selection: $excludes) {
                        Text("Only these").tag(false)
                        Text("All except these").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } footer: {
                    Text(kinds.isEmpty
                         ? LocalizedStringKey("No types picked: the ring counts all workouts.")
                         : excludes ? "The ring counts every workout except the types you pick."
                                    : "The ring counts only the types you pick.")
                }
            }

            Section {
                ForEach(available, id: \.self) { kind in
                    Button {
                        if kinds.contains(kind) { kinds.remove(kind) } else { kinds.insert(kind) }
                    } label: {
                        HStack {
                            Label(kind.title, systemImage: kind.symbol)
                                .foregroundStyle(.primary)
                            Spacer()
                            if kinds.contains(kind) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(kinds.contains(kind) ? .isSelected : [])
                }
            } footer: {
                if excludeOnly && onlyDuringWorkouts {
                    Text("\(metricTitle) logged during workouts of the types you pick is left out. The ring counts only your other workouts.")
                } else if excludeOnly {
                    Text("\(metricTitle) logged during workouts of the types you pick is left out. Everything else still counts, including background activity and workouts you didn't record.")
                }
            }
        }
        .navigationTitle(excludeOnly ? "Leave Out Workouts" : "Workout Types")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !kinds.isEmpty {
                Button("Clear") { kinds.removeAll() }
            }
        }
        .onChange(of: kinds) { save() }
        .onChange(of: excludes) { save() }
    }

    private func save() {
        filter = WorkoutFilter.make(kinds, excludes: excludes)
    }
}

/// Picks the apps and devices whose data a ring counts.
struct SourcesView: View {
    @Environment(RingsModel.self) private var model
    let metric: HealthMetric
    @Binding var selection: [String]
    @State private var sources: [HealthSource]?

    var body: some View {
        Form {
            Section {
                Button {
                    selection = []
                } label: {
                    HStack {
                        Text("All sources").foregroundStyle(.primary)
                        Spacer()
                        if selection.isEmpty { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
            }
            Section {
                if let sources {
                    if sources.isEmpty {
                        Text("No apps or devices have written \(metric.title.lowercased()) to Health yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sources) { source in
                        Button {
                            if let index = selection.firstIndex(of: source.id) {
                                selection.remove(at: index)
                            } else {
                                selection.append(source.id)
                            }
                        } label: {
                            HStack {
                                Text(source.name).foregroundStyle(.primary)
                                Spacer()
                                if selection.contains(source.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .accessibilityAddTraits(selection.contains(source.id) ? .isSelected : [])
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } header: {
                Text("Only from")
            } footer: {
                Text("Only data from the apps and devices you pick counts. Health already avoids counting the same activity twice from your iPhone and Apple Watch, so most rings need no change.")
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .task { sources = await model.sources(for: metric) }
    }
}

/// Seven round day buttons ("M T W T F S S", from the calendar's first weekday) for picking which days count. At least
/// one day stays picked.
struct WeekdayPicker: View {
    @Binding var selection: [Int]
    private let calendar = Calendar.current

    var body: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let names = calendar.standaloneWeekdaySymbols
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { weekday in
                let on = selection.contains(weekday)
                Button {
                    if on {
                        if selection.count > 1 { selection.removeAll { $0 == weekday } }
                    } else {
                        selection.append(weekday)
                        selection.sort()
                    }
                } label: {
                    Text(symbols[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[weekday - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
