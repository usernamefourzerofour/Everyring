import SwiftUI
import WidgetKit

/// One widget for every size: the chosen ring set, drawn from the App Group cache. Shared by the iPhone/iPad widget
/// extension and the Apple Watch complications.
struct RingsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "RingsWidget", intent: SelectRingSetIntent.self, provider: RingsProvider()) { entry in
            RingsWidgetView(entry: entry)
        }
        .configurationDisplayName("Rings")
        .description("A ring set at a glance.")
        .supportedFamilies(Self.families)
    }

    #if os(watchOS)
    static let families: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]
    #else
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge,
                                           .accessoryCircular, .accessoryRectangular, .accessoryInline]
    #endif
}

struct RingsEntry: TimelineEntry {
    struct Item: Identifiable {
        var ring: Ring
        var value: Double
        var id: Ring.ID { ring.id }
        var fraction: Double { ring.fraction(value) }
        var display: RingDisplay { RingDisplay(id: ring.id, color: ring.color, fraction: fraction) }
    }

    let date: Date
    let set: RingSet?
    let items: [Item]
    let calendar: Calendar

    var displays: [RingDisplay] { items.map(\.display) }

    /// Example rings for the widget gallery.
    static var preview: RingsEntry {
        let set = RingSet.starter
        let fractions = [0.72, 1.24, 0.46, 1.0, 0.31]
        let items = set.rings.enumerated().map { index, ring in Item(ring: ring, value: ring.goal * fractions[index % 5]) }
        return RingsEntry(date: .now, set: set, items: items, calendar: .current)
    }
}

struct RingsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RingsEntry { .preview }

    func snapshot(for configuration: SelectRingSetIntent, in context: Context) async -> RingsEntry {
        let entry = entry(for: configuration, at: .now)
        return context.isPreview && entry.set == nil ? .preview : entry
    }

    /// Watch faces list one complication per ring set.
    func recommendations() -> [AppIntentRecommendation<SelectRingSetIntent>] {
        (RingStore.load()?.sets ?? []).map { set in
            let intent = SelectRingSetIntent()
            intent.ringSet = RingSetEntity(set)
            return AppIntentRecommendation(intent: intent, description: Text(set.name))
        }
    }

    func timeline(for configuration: SelectRingSetIntent, in context: Context) async -> Timeline<RingsEntry> {
        let now = Date.now
        let first = entry(for: configuration, at: now)
        // Redraw when a fixed ring starts a new period (e.g. at midnight), so it doesn't show yesterday's value.
        let boundaries = ProgressCache.boundaries(for: first.set?.rings ?? [], after: now, calendar: first.calendar)
        let entries = [first] + boundaries.map { entry(for: configuration, at: $0) }
        // The app reloads the timeline whenever it has new values; this is only a fallback.
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600)))
    }

    private func entry(for configuration: SelectRingSetIntent, at date: Date) -> RingsEntry {
        guard let library = RingStore.load() else {
            return RingsEntry(date: date, set: nil, items: [], calendar: .current)
        }
        let calendar = library.calendar()
        let set = library.sets.first { $0.id == configuration.ringSet?.id } ?? library.sets.first
        let cache = ProgressCache.load()
        let items = (set?.rings ?? []).map {
            RingsEntry.Item(ring: $0, value: cache.value(for: $0, at: date, calendar: calendar))
        }
        return RingsEntry(date: date, set: set, items: items, calendar: calendar)
    }
}

struct RingsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RingsEntry

    var body: some View {
        content
            .widgetURL(entry.set.map { URL(string: "everyring://set/\($0.id.uuidString)")! })
            .containerBackground(.background, for: .widget)
    }

    @ViewBuilder private var content: some View {
        if entry.items.isEmpty {
            empty
        } else {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            #if os(watchOS)
            case .accessoryCorner: corner
            #else
            case .systemMedium: medium
            case .systemLarge: large
            #endif
            default: small
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "circle.circle")
                .font(.title2)
            if family != .accessoryCircular && family != .accessoryInline {
                Text("Open Everyring to add rings.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.secondary)
    }

    private var rings: some View {
        RingStackView(rings: entry.displays)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.items.map { $0.ring.accessibilityText($0.value, now: entry.date, calendar: entry.calendar) }
                .joined(separator: "; "))
    }

    // MARK: Home Screen

    /// Rings with a compact legend: each ring's icon and percentage.
    private var small: some View {
        HStack(spacing: 8) {
            rings
            VStack(alignment: .leading, spacing: entry.items.count > 4 ? 1 : 3) {
                ForEach(entry.items) { item in
                    HStack(spacing: 3) {
                        Image(systemName: item.ring.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 14)
                        Text(item.fraction, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(item.ring.color.color)
                }
            }
            .fixedSize()
            .accessibilityHidden(true)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            rings
            VStack(alignment: .leading, spacing: entry.items.count > 4 ? 2 : 5) {
                ForEach(entry.items) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.ring.symbol)
                            .foregroundStyle(item.ring.color.color)
                            .frame(width: 18)
                        Text(item.ring.name)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(item.fraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                            .foregroundStyle(item.ring.color.color)
                    }
                    .font(entry.items.count > 3 ? .caption : .subheadline)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.set?.name ?? "")
                .font(.headline)
            rings
                .frame(maxWidth: .infinity, maxHeight: 150)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.items) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.ring.symbol)
                            .foregroundStyle(item.ring.color.color)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.ring.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(item.ring.progressText(item.value)) · \(item.ring.period.status(now: entry.date, calendar: entry.calendar))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(item.fraction, format: .percent.precision(.fractionLength(0)))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(item.ring.color.color)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Lock Screen

    private var circular: some View {
        RingStackView(rings: entry.displays, trackOpacity: 0.3)
            .padding(2)
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.items.map { $0.ring.accessibilityText($0.value, now: entry.date, calendar: entry.calendar) }
                .joined(separator: "; "))
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            RingStackView(rings: entry.displays, trackOpacity: 0.3)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entry.items.prefix(3)) { item in
                    HStack(spacing: 4) {
                        Text(item.ring.name)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(item.fraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
    }

    #if os(watchOS)
    /// The first ring as a gauge along the corner, with its icon in the corner.
    private var corner: some View {
        let first = entry.items[0]
        return Image(systemName: first.ring.symbol)
            .font(.title3)
            .widgetAccentable()
            .widgetLabel {
                Gauge(value: min(first.fraction, 1)) {
                    Text(first.ring.name)
                } currentValueLabel: {
                    Text(first.fraction, format: .percent.precision(.fractionLength(0)))
                }
                .tint(first.ring.color.color)
            }
            .accessibilityLabel(first.ring.accessibilityText(first.value, now: entry.date, calendar: entry.calendar))
    }
    #endif

    private var inline: some View {
        Text(entry.items.prefix(2).map {
            "\($0.ring.name) \($0.fraction.formatted(.percent.precision(.fractionLength(0))))"
        }.joined(separator: " · "))
    }
}

#if os(iOS)
#Preview("Small", as: .systemSmall) {
    RingsWidget()
} timeline: {
    RingsEntry.preview
}

#Preview("Medium", as: .systemMedium) {
    RingsWidget()
} timeline: {
    RingsEntry.preview
}

#Preview("Large", as: .systemLarge) {
    RingsWidget()
} timeline: {
    RingsEntry.preview
}

#Preview("Circular", as: .accessoryCircular) {
    RingsWidget()
} timeline: {
    RingsEntry.preview
}
#endif
