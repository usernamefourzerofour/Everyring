import SwiftUI

/// How Heart Minutes rings are calculated: the Heart Minutes app's settings, laid out the same way (without its
/// comparison with Exercise minutes). Which measurements count, background or workouts, is set on each ring under
/// Activity; the goal and period are the ring's own.
struct HeartMinuteSettingsView: View {
    @Environment(RingsModel.self) private var model
    @State private var healthAge: Int?
    @State private var confirmReset = false

    private typealias D = HeartMinuteSettings

    var body: some View {
        @Bindable var model = model
        let settings = model.library.heartMinutes
        let defaults = HeartMinuteSettings()
        Form {
            Section {
                NavigationLink {
                    BackgroundActivityView()
                } label: {
                    ResetRow(changed: settings.activityMode != defaults.activityMode || settings.pauseSeconds != defaults.pauseSeconds,
                             info: String(localized: "When your heart rate during the day (outside workouts) counts:") + "\n\n"
                                + ActiveMinutes.ActivityMode.allCases.map { "• \($0.title): \($0.explanation)" }.joined(separator: "\n")
                                + "\n\n" + String(localized: "Measurements during workouts always count.")) {
                        model.library.heartMinutes.activityMode = defaults.activityMode
                        model.library.heartMinutes.pauseSeconds = defaults.pauseSeconds
                    } content: {
                        LabeledContent("Background activity", value: settings.activityMode.shortTitle)
                    }
                }
            } header: {
                Text("Heart Minutes")
            } footer: {
                Text("Which measurements count – background measurements, workouts or both – is set on each ring under Activity.")
            }

            Section {
                ResetRow(changed: settings.zoneModel != defaults.zoneModel, info: String(localized: "2 zones: moderate from 50 % and vigorous from 70 % of max heart rate – the American Heart Association (AHA) recommendation. Moderate counts × 1 and vigorous × 2, so 150 min moderate or 75 min vigorous per week is enough.\n\n5 zones: the common zones used by e.g. Garmin and Polar (Z1 from 50 %, Z2 60 %, Z3 70 %, Z4 80 %, Z5 90 %). Z0 is heart rate below 50 %.\n\nLimits and factors can be changed under “Your zones”.")) {
                    model.library.heartMinutes.zoneModel = defaults.zoneModel
                } content: {
                    Picker("Number of zones", selection: $model.library.heartMinutes.zoneModel) {
                        ForEach(ZoneModel.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Heart rate zones")
            } footer: {
                if settings.zoneModel == .two {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Follows the American Heart Association (AHA) recommendations: moderate 50–70 %, vigorous from 70 % of max heart rate.")
                        Link(destination: AHA.targetHeartRatesURL) {
                            Text("Source: American Heart Association – Target Heart Rates")
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.footnote)
                    }
                }
            }

            Section {
                ResetRow(changed: settings.maxHRSource != defaults.maxHRSource, info: String(localized: "Age: max heart rate = 220 − age.\nEnter: your own max heart rate, e.g. measured in a test.")) {
                    model.library.heartMinutes.maxHRSource = defaults.maxHRSource
                } content: {
                    Picker("Max heart rate from", selection: $model.library.heartMinutes.maxHRSource) {
                        ForEach(MaxHRSource.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                switch settings.maxHRSource {
                case .age:
                    ResetRow(changed: healthAge.map { settings.effectiveAge != $0 } ?? false,
                             info: String(localized: "Default: your age from your date of birth in Health.")) {
                        model.library.heartMinutes.age = healthAge
                    } content: {
                        Stepper("Age: \(settings.effectiveAge) years", value: Binding(
                            get: { settings.effectiveAge }, set: { model.library.heartMinutes.age = $0 }), in: 10...100)
                    }
                    LabeledContent("Max heart rate (220 − age)", value: "\(Int(settings.maxHR.rounded())) bpm")
                case .manual:
                    let ageMax = Int(HeartZones.maxHR(age: settings.effectiveAge))
                    ResetRow(changed: settings.manualMaxHR != ageMax, info: String(localized: "The highest heart rate your heart can reach – e.g. measured in a test or the same as in another app. Default: 220 − your age.")) {
                        model.library.heartMinutes.manualMaxHR = ageMax
                    } content: {
                        Stepper("Max heart rate: \(settings.manualMaxHR) bpm", value: $model.library.heartMinutes.manualMaxHR, in: 120...230)
                    }
                }
            } header: {
                Text("Max heart rate")
            }

            Section {
                let zones = settings.zones
                ForEach(zones.indices, id: \.self) { i in
                    ZoneRow(zones: zones, index: i,
                            percent: Binding(get: { zones.percents[i] }, set: { setPercent($0, at: i) }),
                            weight: Binding(get: { zones.weights[i] }, set: { setWeight($0, at: i) }))
                }
                if settings.zonePercents[settings.zoneModel] != nil || settings.zoneWeights[settings.zoneModel] != nil {
                    Button("Reset zones") {
                        model.library.heartMinutes.zonePercents[settings.zoneModel] = nil
                        model.library.heartMinutes.zoneWeights[settings.zoneModel] = nil
                    }
                }
            } header: {
                Text("Your zones")
            } footer: {
                Text("The limits are a percentage of your max heart rate (\(Int(settings.maxHR.rounded())) bpm). The factor is how much one minute in the zone counts; by default the lowest zone doesn’t count (× 0).")
            }

            Section {
                NavigationLink {
                    AdvancedHeartMinuteSettingsView()
                } label: {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text("Heart rate between measurements and gaps.")
            }

            Section {
                Button("Reset all settings", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Tap ⓘ to see what a setting does. \(Image(systemName: "arrow.counterclockwise")) appears when a setting has been changed – tap it to reset the setting to its default.")
            }
        }
        .navigationTitle("Heart Minutes")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset all Heart Minutes settings?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset all", role: .destructive) {
                model.library.heartMinutes = HeartMinuteSettings()
                model.library.heartMinutes.age = healthAge
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            healthAge = RingsModel.isDemo ? nil : HealthManager.shared.ageFromHealth()
        }
    }

    private func setPercent(_ value: Double, at i: Int) {
        var percents = model.library.heartMinutes.zones.percents
        percents[i] = value
        model.library.heartMinutes.zonePercents[model.library.heartMinutes.zoneModel] = percents
    }

    private func setWeight(_ value: Double, at i: Int) {
        var weights = model.library.heartMinutes.zones.weights
        weights[i] = value
        model.library.heartMinutes.zoneWeights[model.library.heartMinutes.zoneModel] = weights
    }
}

/// When background heart rate counts: one list with an explanation below each choice, and the longest pause.
private struct BackgroundActivityView: View {
    @Environment(RingsModel.self) private var model
    @FocusState private var editingPause: Bool

    var body: some View {
        @Bindable var model = model
        let settings = model.library.heartMinutes
        Form {
            Section {
                ForEach(ActiveMinutes.ActivityMode.allCases) { mode in
                    Button {
                        model.library.heartMinutes.activityMode = mode
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title).foregroundStyle(Color.primary)
                                Text(mode.explanation).font(.caption).foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            if settings.activityMode == mode {
                                Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                            }
                        }
                    }
                    .accessibilityAddTraits(settings.activityMode == mode ? .isSelected : [])
                }
            } footer: {
                Text("When your heart rate during the day – outside workouts – counts as Heart Minutes. Workouts always count.")
            }

            if settings.activityMode == .withPauses || settings.activityMode == .watchWithPauses {
                Section {
                    LabeledContent("Longest pause") {
                        SecondsField(value: $model.library.heartMinutes.pauseSeconds, focus: $editingPause)
                    }
                } footer: {
                    Text("Joins two active stretches when the pause between them is at most this many seconds (1–600). Then, for example, gardening with short breaks counts as one continuous activity.")
                }
            }
        }
        .navigationTitle("Background activity")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            // The number pad has no return key.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editingPause = false }.bold()
            }
        }
    }
}

/// Fine-tuning: heart rate between measurements and gaps.
private struct AdvancedHeartMinuteSettingsView: View {
    @Environment(RingsModel.self) private var model
    @FocusState private var editingGap: Bool

    var body: some View {
        @Bindable var model = model
        let settings = model.library.heartMinutes
        let defaults = HeartMinuteSettings()
        Form {
            Section {
                ResetRow(changed: settings.interpolation != defaults.interpolation, info: ActiveMinutes.Interpolation.allExplained) {
                    model.library.heartMinutes.interpolation = defaults.interpolation
                } content: {
                    Picker("Heart rate between measurements", selection: $model.library.heartMinutes.interpolation) {
                        ForEach(ActiveMinutes.Interpolation.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Heart rate between measurements")
            } footer: {
                Text("\(settings.interpolation.title): \(settings.interpolation.explanation)")
            }

            Section {
                ResetRow(changed: settings.maxGapSeconds != defaults.maxGapSeconds, info: String(localized: "If there is more time between two measurements outside a workout than this, the time in between doesn’t count – nothing was measured. From 1 to 600 s. Default: 300 s (5 min).")) {
                    model.library.heartMinutes.maxGapSeconds = defaults.maxGapSeconds
                } content: {
                    LabeledContent("Outside workouts") {
                        SecondsField(value: $model.library.heartMinutes.maxGapSeconds, focus: $editingGap)
                    }
                }
                ResetRow(changed: settings.workoutGaps != defaults.workoutGaps, info: ActiveMinutes.WorkoutGaps.allExplained) {
                    model.library.heartMinutes.workoutGaps = defaults.workoutGaps
                } content: {
                    Picker("In workouts", selection: $model.library.heartMinutes.workoutGaps) {
                        ForEach(ActiveMinutes.WorkoutGaps.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Gaps in measurements")
            } footer: {
                Text("Outside workouts, gaps of up to \(min(max(settings.maxGapSeconds, 1), 600)) s count. During workouts \(settings.workoutGaps.summary)")
            }
        }
        .navigationTitle("Advanced")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editingGap = false }.bold()
            }
        }
    }
}

/// A number of seconds typed in (1–600).
private struct SecondsField: View {
    @Binding var value: Int
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 4) {
            TextField("s", value: $value, format: .number)
                .keyboardType(.numberPad)
                .focused(focus)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 60)
            Text("s").foregroundStyle(.secondary)
        }
        .onChange(of: value) { _, v in
            let clamped = min(max(v, 1), 600)
            if clamped != v { value = clamped }
        }
    }
}

/// A setting with ⓘ (what it does) and, once changed, ↺ (back to the default), as in Heart Minutes.
private struct ResetRow<Content: View>: View {
    let changed: Bool
    let info: String
    let reset: () -> Void
    @ViewBuilder let content: Content
    @State private var showsInfo = false

    var body: some View {
        HStack(spacing: 10) {
            content
            if changed {
                Button(action: reset) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reset to default")
            }
            Button {
                showsInfo = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("What this does")
            .popover(isPresented: $showsInfo) {
                ScrollView {
                    Text(info)
                        .padding()
                        .frame(maxWidth: 360, alignment: .leading)
                }
                .presentationCompactAdaptation(.popover)
            }
        }
    }
}

/// One zone: its name and heart rate range, the lower limit (% of max) and the factor.
private struct ZoneRow: View {
    let zones: HeartZones
    let index: Int
    @Binding var percent: Double
    @Binding var weight: Double

    var body: some View {
        let range = zones.bpmRange(index)
        let color = zones.rgb(index)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(Color(red: color[0], green: color[1], blue: color[2]))
                    .frame(width: 10, height: 10)
                Text(zones.name(index)).font(.headline)
                Spacer()
                Text(range.upperBound.isInfinite
                     ? "\(Int(range.lowerBound))+ bpm"
                     : "\(Int(range.lowerBound))–\(Int(range.upperBound)) bpm")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if index > 0 {
                Stepper(value: $percent, in: min(lowerLimit, upperLimit)...max(lowerLimit, upperLimit), step: 0.05) {
                    Text("From \(percent.formatted(.percent.precision(.fractionLength(0))))")
                }
            }
            Stepper(value: $weight, in: 0...4, step: 0.5) {
                Text("Counts × \(weight.formatted(.number.precision(.fractionLength(0...1))))")
            }
        }
        .padding(.vertical, 2)
    }

    /// A zone's limit stays between its neighbours'.
    private var lowerLimit: Double { index > 1 ? zones.percents[index - 1] + 0.05 : 0.3 }
    private var upperLimit: Double { index + 1 < zones.count ? zones.percents[index + 1] - 0.05 : 1.0 }
}
