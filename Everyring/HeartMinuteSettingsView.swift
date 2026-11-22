import SwiftUI

/// How Heart Minutes rings are calculated: max heart rate, zones, when background heart rate counts and how gaps are
/// handled. The same settings and defaults as the Heart Minutes app.
struct HeartMinuteSettingsView: View {
    @Environment(RingsModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let settings = model.library.heartMinutes
        let zones = settings.zones
        Form {
            Section {
                Picker("Max heart rate from", selection: $model.library.heartMinutes.maxHRSource) {
                    ForEach(MaxHRSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if settings.maxHRSource == .age {
                    Stepper(value: Binding(get: { settings.effectiveAge },
                                           set: { model.library.heartMinutes.age = $0 }), in: 10...100) {
                        LabeledContent("Age", value: "\(settings.effectiveAge)")
                    }
                } else {
                    Stepper(value: $model.library.heartMinutes.manualMaxHR, in: 100...230) {
                        LabeledContent("Max heart rate", value: "\(settings.manualMaxHR) bpm")
                    }
                }
            } header: {
                Text("Max heart rate")
            } footer: {
                Text(settings.maxHRSource == .age
                     ? LocalizedStringKey("Max heart rate \(Int(settings.maxHR)) bpm (220 − age). The age is read from your date of birth in Health the first time.")
                     : "Enter a max heart rate you have measured, e.g. in a test.")
            }

            Section {
                Picker("Zones", selection: $model.library.heartMinutes.zoneModel) {
                    ForEach(ZoneModel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                ForEach(zones.indices, id: \.self) { i in
                    ZoneRow(zones: zones, index: i,
                            percent: Binding(get: { zones.percents[i] }, set: { setPercent($0, at: i) }),
                            weight: Binding(get: { zones.weights[i] }, set: { setWeight($0, at: i) }))
                }
            } header: {
                Text("Heart rate zones")
            } footer: {
                Text("A minute in a zone counts with the zone’s factor: by default moderate × 1 and vigorous × 2, as the American Heart Association recommends (150 minutes of moderate or 75 of vigorous activity a week).")
            }

            Section {
                Picker("Counts", selection: $model.library.heartMinutes.activityMode) {
                    ForEach(ActiveMinutes.ActivityMode.allCases) { Text($0.title).tag($0) }
                }
                if settings.activityMode == .watchWithPauses || settings.activityMode == .withPauses {
                    Stepper(value: Binding(get: { max(1, settings.pauseSeconds / 60) },
                                           set: { model.library.heartMinutes.pauseSeconds = $0 * 60 }), in: 1...10) {
                        LabeledContent("Longest pause", value: Self.minutes(settings.pauseSeconds / 60))
                    }
                }
            } header: {
                Text("Background heart rate")
            } footer: {
                Text(settings.activityMode.explanation)
            }

            Section {
                Picker("Gaps in workouts", selection: $model.library.heartMinutes.workoutGaps) {
                    ForEach(ActiveMinutes.WorkoutGaps.allCases) { Text($0.title).tag($0) }
                }
                Picker("Between measurements", selection: $model.library.heartMinutes.interpolation) {
                    ForEach(ActiveMinutes.Interpolation.allCases) { Text($0.title).tag($0) }
                }
                Stepper(value: Binding(get: { max(1, settings.maxGapSeconds / 60) },
                                       set: { model.library.heartMinutes.maxGapSeconds = $0 * 60 }), in: 1...10) {
                    LabeledContent("Longest gap", value: Self.minutes(settings.maxGapSeconds / 60))
                }
            } header: {
                Text("Measurements")
            } footer: {
                Text("During workouts \(settings.workoutGaps.summary) \(settings.interpolation.explanation) Outside workouts, a gap longer than the longest gap doesn’t count.")
            }

            Section {
                Button("Reset to Defaults", role: .destructive) {
                    let age = model.library.heartMinutes.age
                    model.library.heartMinutes = HeartMinuteSettings()
                    model.library.heartMinutes.age = age
                }
            }
        }
        .navigationTitle("Heart Minutes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func minutes(_ n: Int) -> String {
        Duration.seconds(n * 60).formatted(.units(allowed: [.minutes], width: .abbreviated))
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
                    LabeledContent("From", value: percent.formatted(.percent.precision(.fractionLength(0))))
                }
            }
            Stepper(value: $weight, in: 0...4, step: 0.5) {
                LabeledContent("Counts", value: "× \(weight.formatted(.number.precision(.fractionLength(0...1))))")
            }
        }
        .padding(.vertical, 2)
    }

    /// A zone's limit stays between its neighbours'.
    private var lowerLimit: Double { index > 1 ? zones.percents[index - 1] + 0.05 : 0.3 }
    private var upperLimit: Double { index + 1 < zones.count ? zones.percents[index + 1] - 0.05 : 1.0 }
}
