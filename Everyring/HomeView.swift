import SwiftUI

/// Home: swipeable ring sets, each with the large ring stack and a list of its rings.
struct HomeView: View {
    @Environment(RingsModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedSet: RingSet.ID?

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedSet) {
                ForEach(model.library.sets) { set in
                    RingSetPage(set: set)
                        .tag(Optional(set.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: model.library.sets.count > 1 ? .automatic : .never))
            .navigationTitle(currentSet?.name ?? String(localized: "Everyring"))
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) {
                if let error = model.error {
                    Text(error)
                        .font(.footnote)
                        .padding(10)
                        .glassEffect()
                        .padding()
                }
            }
        }
        .onAppear { if selectedSet == nil { selectedSet = model.library.sets.first?.id } }
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }

    private var currentSet: RingSet? { model.library.set(id: selectedSet) }
}

struct RingSetPage: View {
    @Environment(RingsModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let set: RingSet

    var body: some View {
        ScrollView {
            let columns = sizeClass == .regular
                ? [GridItem(.flexible(), spacing: 32), GridItem(.flexible())]
                : [GridItem(.flexible())]
            LazyVGrid(columns: columns, alignment: .center, spacing: 24) {
                RingStackView(rings: model.displays(for: set))
                    .frame(maxWidth: sizeClass == .regular ? 420 : 300)
                    .padding(.horizontal)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(set.rings.map { model.accessibilityText(for: $0) }.joined(separator: "; "))

                VStack(spacing: 12) {
                    ForEach(set.rings) { ring in
                        RingRow(ring: ring)
                    }
                }
            }
            .padding()
            .padding(.bottom, 32)
        }
        .refreshable { await model.refresh() }
    }
}

struct RingRow: View {
    @Environment(RingsModel.self) private var model
    let ring: Ring

    var body: some View {
        let value = model.value(for: ring)
        HStack(spacing: 14) {
            Image(systemName: ring.symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(ring.color.color.gradient, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(ring.name)
                    .font(.headline)
                Text(ring.progressText(value))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(ring.period.status(calendar: model.calendar))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(ring.fraction(value), format: .percent.precision(.fractionLength(0)))
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(ring.color.color)
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityText(for: ring))
    }
}

extension RingsModel {
    func accessibilityText(for ring: Ring) -> String {
        ring.accessibilityText(value(for: ring), calendar: calendar)
    }
}

#Preview {
    HomeView()
        .environment(RingsModel(library: .starter))
}
