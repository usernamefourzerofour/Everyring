import SwiftUI

/// The watch app: one page per ring set (scroll the Digital Crown between them), tap a ring for details.
struct WatchHomeView: View {
    @Environment(RingsModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedSet: RingSet.ID?

    var body: some View {
        NavigationStack {
            Group {
                if model.library.sets.isEmpty {
                    ContentUnavailableView("No rings yet", systemImage: "iphone",
                                           description: Text("Set up your rings in Everyring on your iPhone."))
                } else {
                    TabView(selection: $selectedSet) {
                        ForEach(model.library.sets) { set in
                            WatchSetPage(set: set)
                                .tag(Optional(set.id))
                        }
                    }
                    .tabViewStyle(.verticalPage)
                }
            }
            .navigationDestination(for: Ring.ID.self) { WatchRingDetail(ringID: $0) }
        }
        .onOpenURL { url in
            // everyring://set/<id> from a complication.
            guard url.host() == "set", let id = UUID(uuidString: url.lastPathComponent) else { return }
            selectedSet = id
        }
        .sensoryFeedback(.success, trigger: model.celebration) { _, new in new != nil }
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await model.refresh() }
            case .background: WatchRefresh.schedule()
            default: break
            }
        }
    }
}

struct WatchSetPage: View {
    @Environment(RingsModel.self) private var model
    let set: RingSet

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                RingStackView(rings: model.displays(for: set))
                    .frame(height: 110)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(set.rings.map { model.accessibilityText(for: $0) }.joined(separator: "; "))

                ForEach(set.rings) { ring in
                    NavigationLink(value: ring.id) {
                        WatchRingRow(ring: ring, value: model.value(for: ring))
                    }
                }
            }
        }
        .navigationTitle(set.name)
    }
}

struct WatchRingRow: View {
    let ring: Ring
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ring.symbol)
                .foregroundStyle(ring.color.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(ring.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(ring.progressText(value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            Text(ring.fraction(value), format: .percent.precision(.fractionLength(0)))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(ring.tint(value))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ring.accessibilityText(value))
    }
}

struct WatchRingDetail: View {
    @Environment(RingsModel.self) private var model
    let ringID: Ring.ID
    @State private var streak: Streak?

    var body: some View {
        if let ring = model.ring(id: ringID) {
            let value = model.value(for: ring)
            ScrollView {
                VStack(spacing: 8) {
                    RingStackView(rings: [ring.display(value)])
                        .frame(height: 90)
                        .overlay {
                            Text(ring.fraction(value), format: .percent.precision(.fractionLength(0)))
                                .font(.headline.monospacedDigit())
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(model.accessibilityText(for: ring))
                    Text(ring.progressText(value))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(ring.period.status(calendar: model.calendar))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let streak {
                        Divider()
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Streak").font(.caption2).foregroundStyle(.secondary)
                                Text(ring.period.streakUnits(streak.current)).font(.footnote.weight(.semibold))
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Best").font(.caption2).foregroundStyle(.secondary)
                                Text(ring.period.streakUnits(streak.best)).font(.footnote.weight(.semibold))
                            }
                        }
                    }
                }
            }
            .navigationTitle(ring.name)
            .task(id: ring) { streak = await model.history(for: ring)?.streak }
        } else {
            ContentUnavailableView("Ring deleted", systemImage: "circle.dashed")
        }
    }
}

extension RingsModel {
    func accessibilityText(for ring: Ring) -> String {
        ring.accessibilityText(value(for: ring), calendar: calendar)
    }
}
