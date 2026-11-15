import SwiftUI

/// One ring: progress, period and streaks. History follows in a later milestone.
struct RingDetailView: View {
    @Environment(RingsModel.self) private var model
    let ringID: Ring.ID
    @State private var streak: Streak?
    @State private var loadingStreak = true
    @State private var editing = false

    var body: some View {
        if let ring = model.ring(id: ringID) {
            let value = model.value(for: ring)
            ScrollView {
                VStack(spacing: 24) {
                    RingStackView(rings: [RingDisplay(id: ring.id, color: ring.color, fraction: ring.fraction(value))])
                        .frame(maxWidth: 240)
                        .overlay {
                            VStack(spacing: 2) {
                                Image(systemName: ring.symbol)
                                    .font(.title)
                                    .foregroundStyle(ring.color.color)
                                Text(ring.fraction(value), format: .percent.precision(.fractionLength(0)))
                                    .font(.title2.monospacedDigit().weight(.semibold))
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(model.accessibilityText(for: ring))

                    VStack(spacing: 6) {
                        Text(ring.progressText(value))
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(ring.period.status(calendar: model.calendar))
                            .foregroundStyle(.secondary)
                    }

                    StreakCard(ring: ring, streak: streak, loading: loadingStreak)
                }
                .padding()
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(ring.name)
            .toolbar {
                Button("Edit") { editing = true }
            }
            .sheet(isPresented: $editing) {
                NavigationStack {
                    RingEditorView(ring: ring, isNew: false, showsCancel: true, previewValue: value,
                                   onSave: { model.update($0) },
                                   onDelete: { model.deleteRing(id: ring.id) })
                }
            }
            .task(id: ring) {
                loadingStreak = true
                streak = await model.streak(for: ring)
                loadingStreak = false
            }
        } else {
            ContentUnavailableView("Ring deleted", systemImage: "circle.dashed")
        }
    }
}

struct StreakCard: View {
    let ring: Ring
    let streak: Streak?
    let loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Streak", systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(ring.color.color)
            if let streak {
                HStack {
                    StreakNumber(title: "Current", text: ring.period.streakUnits(streak.current))
                    StreakNumber(title: "Best", text: ring.period.streakUnits(streak.best))
                }
            } else if loading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Couldn’t read Health data.")
                    .foregroundStyle(.secondary)
            }
            Text(ring.period.isRolling
                 ? LocalizedStringKey("Days in a row on which the last \(ring.period.nominalDays) days reached your goal.")
                 : "Periods in a row in which you closed the ring.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 20))
    }
}

private struct StreakNumber: View {
    let title: LocalizedStringKey
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
