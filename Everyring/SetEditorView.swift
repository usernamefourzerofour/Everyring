import SwiftUI

/// Edits a ring set: name, rings (add, edit, reorder, delete; at most five) and deleting the set.
struct SetEditorView: View {
    @Environment(RingsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RingSet
    @State private var confirmDelete = false
    @State private var path: [Route] = []
    /// Reordering mode: the system's drag handles (≡) on every ring.
    @State private var editMode: EditMode = .inactive
    private let isNew: Bool
    private let onSaved: (RingSet) -> Void

    private enum Route: Hashable {
        /// Step 1 of a new ring: pick the Health metric.
        case newRing
        /// Step 2: the ring editor with that metric's defaults.
        case newRingEditor(HealthMetric)
        case ring(Ring.ID)
    }

    init(set: RingSet?, onSaved: @escaping (RingSet) -> Void = { _ in }) {
        _draft = State(initialValue: set ?? RingSet(name: String(localized: "New set"), rings: []))
        isNew = set == nil
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    if !draft.rings.isEmpty {
                        RingStackView(rings: draft.rings.map {
                            RingDisplay(id: $0.id, start: $0.gradient.start, end: $0.gradient.end, fraction: model.value(for: $0) > 0
                                        ? $0.fraction(model.value(for: $0)) : 0.7)
                        })
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    }
                    TextField("Set name", text: $draft.name)
                }

                Section {
                    ForEach(draft.rings) { ring in
                        if editMode.isEditing {
                            RingLabel(ring: ring)
                        } else {
                            NavigationLink(value: Route.ring(ring.id)) {
                                HStack {
                                    RingLabel(ring: ring)
                                    Spacer()
                                    if draft.rings.count > 1 {
                                        // A hint that the order can be changed (Reorder, or touch and hold).
                                        Image(systemName: "line.3.horizontal")
                                            .foregroundStyle(.tertiary)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                    }
                    .onMove { draft.rings.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { draft.rings.remove(atOffsets: $0) }

                    if draft.canAddRing && !editMode.isEditing {
                        NavigationLink(value: Route.newRing) {
                            Label("Add Ring", systemImage: "plus.circle.fill")
                        }
                    }
                } header: {
                    HStack {
                        Text("Rings")
                        Spacer()
                        if draft.rings.count > 1 {
                            Button(editMode.isEditing ? "Done" : "Reorder",
                                   systemImage: editMode.isEditing ? "checkmark" : "arrow.up.arrow.down") {
                                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            }
                            .font(.subheadline.weight(.semibold))
                            .textCase(nil)
                        }
                    }
                } footer: {
                    Text("Up to 5 rings. The first ring is the outermost. Tap Reorder and drag ≡ to change the order.")
                }

                if !isNew && model.library.sets.count > 1 {
                    Section {
                        Button("Delete Set", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(isNew ? "New Set" : "Edit Set")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .newRing:
                    MetricPickerView { metric in path.append(.newRingEditor(metric)) }
                case .newRingEditor(let metric):
                    RingEditorView(ring: .new(metric: metric, usedColors: draft.rings.map(\.color)), isNew: true) { ring in
                        if draft.canAddRing { draft.rings.append(ring) }
                        // The editor closes itself; then also leave the metric list, back to the set.
                        DispatchQueue.main.async { path.removeAll() }
                    }
                case .ring(let id):
                    if let ring = draft.rings.first(where: { $0.id == id }) {
                        RingEditorView(ring: ring, isNew: false, previewValue: model.value(for: ring),
                                       onSave: { updated in
                                           if let i = draft.rings.firstIndex(where: { $0.id == id }) { draft.rings[i] = updated }
                                       },
                                       onDelete: { draft.rings.removeAll { $0.id == id } })
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Done", role: .confirm) {
                        var set = draft
                        set.name = set.name.trimmingCharacters(in: .whitespaces)
                        model.save(set)
                        onSaved(set)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.rings.isEmpty)
                }
            }
            .confirmationDialog("Delete “\(draft.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Set", role: .destructive) {
                    model.deleteSet(id: draft.id)
                    dismiss()
                }
            } message: {
                Text("Its rings are deleted too. Your Health data is not affected.")
            }
        }
    }
}

/// A ring's icon, name and goal, for lists.
struct RingLabel: View {
    let ring: Ring

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ring.symbol)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(ring.accent.gradient, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ring.name)
                Text("\(ring.metric.format(ring.goal)) · \(ring.period.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
