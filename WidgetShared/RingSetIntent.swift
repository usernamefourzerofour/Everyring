import AppIntents
import Foundation

/// A ring set the user can pick when configuring a widget.
struct RingSetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Ring Set"
    static var defaultQuery = RingSetQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ set: RingSet) {
        id = set.id
        name = set.name
    }
}

struct RingSetQuery: EntityQuery {
    private var sets: [RingSet] { RingStore.load()?.sets ?? [] }

    func entities(for identifiers: [UUID]) async throws -> [RingSetEntity] {
        sets.filter { identifiers.contains($0.id) }.map(RingSetEntity.init)
    }

    func suggestedEntities() async throws -> [RingSetEntity] {
        sets.map(RingSetEntity.init)
    }

    func defaultResult() async -> RingSetEntity? {
        sets.first.map(RingSetEntity.init)
    }
}

struct SelectRingSetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Ring Set"
    static var description = IntentDescription("Choose which ring set the widget shows.")

    @Parameter(title: "Ring Set")
    var ringSet: RingSetEntity?

    init() {}
}
