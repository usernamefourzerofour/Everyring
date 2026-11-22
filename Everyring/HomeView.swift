import SwiftUI

/// Home: swipeable ring sets, each with the large ring stack and a list of its rings.
struct HomeView: View {
    @Environment(RingsModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedSet: RingSet.ID?
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        case newSet, editSet(RingSet), settings

        var id: String {
            switch self {
            case .newSet: "new"
            case .editSet(let set): set.id.uuidString
            case .settings: "settings"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.library.sets.isEmpty {
                    ContentUnavailableView {
                        Label("No ring sets", systemImage: "circle.circle")
                    } description: {
                        Text("A ring set holds up to five rings, each with its own goal and period.")
                    } actions: {
                        Button("Create Ring Set") { sheet = .newSet }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    TabView(selection: $selectedSet) {
                        ForEach(model.library.sets) { set in
                            RingSetPage(set: set)
                                .tag(Optional(set.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: model.library.sets.count > 1 ? .automatic : .never))
                    .indexViewStyle(.page(backgroundDisplayMode: .automatic))
                }
            }
            .navigationTitle(currentSet?.name ?? String(localized: "Everyring"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Ring.ID.self) { RingDetailView(ringID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { sheet = .settings }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Ring Sets", systemImage: "ellipsis") {
                        if let currentSet {
                            Button("Edit “\(currentSet.name)”", systemImage: "pencil") { sheet = .editSet(currentSet) }
                        }
                        Button("New Ring Set", systemImage: "plus") { sheet = .newSet }
                    }
                }
            }
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
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newSet:
                SetEditorView(set: nil) { selectedSet = $0.id }
            case .editSet(let set):
                SetEditorView(set: set)
            case .settings:
                NavigationStack { SettingsView() }
            }
        }
        .onAppear { if currentSet?.id != selectedSet { selectedSet = currentSet?.id } }
        .onChange(of: model.library.sets.map(\.id)) { _, ids in
            if let selectedSet, ids.contains(selectedSet) { return }
            selectedSet = ids.first
        }
        .onOpenURL { url in
            // everyring://set/<id> from a widget.
            guard url.host() == "set", let id = UUID(uuidString: url.lastPathComponent),
                  model.library.sets.contains(where: { $0.id == id }) else { return }
            selectedSet = id
        }
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
                RingStackView(rings: model.displays(for: set), showsLabels: true)
                    .frame(maxWidth: sizeClass == .regular ? 420 : 300)
                    .padding(.horizontal)
                    .animation(.smooth(duration: 0.8), value: model.displays(for: set))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(set.rings.map { model.accessibilityText(for: $0) }.joined(separator: "; "))

                VStack(spacing: 12) {
                    ForEach(set.rings) { ring in
                        NavigationLink(value: ring.id) {
                            RingRow(ring: ring)
                        }
                        .buttonStyle(.plain)
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
                .background(ring.accent.gradient, in: .circle)
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
                .foregroundStyle(ring.tint(value))
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityText(for: ring))
        .accessibilityAddTraits(.isButton)
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
