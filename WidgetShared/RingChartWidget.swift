#if os(iOS)
import AppIntents
import Charts
import SwiftUI
import WidgetKit

// One ring and how it built up through its period, inspired by Heart Minutes' widget: the ring with its numbers and a
// chart of the running value with the goal.

// MARK: Configuration

/// A ring the user can pick when configuring the widget.
struct RingEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Ring"
    static var defaultQuery = RingQuery()

    var id: UUID
    var name: String
    var setName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(setName)")
    }

    init(_ ring: Ring, in set: RingSet) {
        id = ring.id
        name = ring.name
        setName = set.name
    }
}

struct RingQuery: EntityQuery {
    private var rings: [RingEntity] {
        (RingStore.load()?.sets ?? []).flatMap { set in set.rings.map { RingEntity($0, in: set) } }
    }

    func entities(for identifiers: [UUID]) async throws -> [RingEntity] {
        rings.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [RingEntity] { rings }

    func defaultResult() async -> RingEntity? { rings.first }
}

struct SelectRingIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Ring"
    static var description = IntentDescription("Choose which ring the widget shows.")

    @Parameter(title: "Ring")
    var ring: RingEntity?

    init() {}
}

// MARK: Data

struct RingChartEntry: TimelineEntry {
    let date: Date
    let ring: Ring?
    let setID: RingSet.ID?
    let value: Double
    /// The running value through the period (the metric's base unit).
    let points: [ChartPoint]
    /// The period the chart spans.
    let chart: DateInterval
    let calendar: Calendar

    /// A made-up ring for the widget gallery.
    static var preview: RingChartEntry {
        let ring = RingSet.starter.rings[0]
        let calendar = Calendar.current
        let now = Date.now
        let chart = PeriodProgress.chartInterval(for: ring, now: now, calendar: calendar)
        let value = ring.goal * 0.72
        let steps = 8
        let points = (0...steps).map { i -> ChartPoint in
            let f = Double(i) / Double(steps)
            return ChartPoint(t: chart.start.addingTimeInterval(now.timeIntervalSince(chart.start) * f),
                              v: value * (f * f * (3 - 2 * f)))
        }
        return RingChartEntry(date: now, ring: ring, setID: nil, value: value, points: points, chart: chart,
                              calendar: calendar)
    }
}

struct RingChartProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RingChartEntry { .preview }

    func snapshot(for configuration: SelectRingIntent, in context: Context) async -> RingChartEntry {
        let entry = entry(for: configuration, at: .now)
        return context.isPreview && entry.ring == nil ? .preview : entry
    }

    func timeline(for configuration: SelectRingIntent, in context: Context) async -> Timeline<RingChartEntry> {
        let now = Date.now
        let first = entry(for: configuration, at: now)
        // Redraw when the ring starts a new period (e.g. at midnight).
        let boundaries = first.ring.map {
            ProgressCache.boundaries(for: [$0], after: now, calendar: first.calendar)
        } ?? []
        let entries = [first] + boundaries.map { entry(for: configuration, at: $0) }
        // The app reloads the timeline whenever it has new values; this is only a fallback.
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600)))
    }

    private func entry(for configuration: SelectRingIntent, at date: Date) -> RingChartEntry {
        let library = RingStore.load()
        let calendar = library?.calendar() ?? .current
        let pairs = (library?.sets ?? []).flatMap { set in set.rings.map { (set, $0) } }
        guard let pair = pairs.first(where: { $0.1.id == configuration.ring?.id }) ?? pairs.first else {
            return RingChartEntry(date: date, ring: nil, setID: nil, value: 0, points: [],
                                  chart: DateInterval(start: date, duration: 86_400), calendar: calendar)
        }
        let (set, ring) = pair
        let cache = ProgressCache.load()
        return RingChartEntry(date: date, ring: ring, setID: set.id,
                              value: cache.value(for: ring, at: date, calendar: calendar),
                              points: cache.points(for: ring, at: date, calendar: calendar),
                              chart: PeriodProgress.chartInterval(for: ring, now: date, calendar: calendar),
                              calendar: calendar)
    }
}

// MARK: Views

struct RingChartWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RingChartEntry

    var body: some View {
        if let ring = entry.ring {
            content(ring)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ring.accessibilityText(entry.value, now: entry.date, calendar: entry.calendar))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "circle.dashed").font(.title)
                Text("Add a ring in Everyring.").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func content(_ ring: Ring) -> some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ChartWidgetRing(ring: ring, value: entry.value)
                        .frame(width: 54, height: 54)
                    caption(ring, compact: true)
                    Spacer(minLength: 0)
                }
                RingWidgetChart(entry: entry, ring: ring, compact: true)
            }
        case .systemMedium:
            HStack(spacing: 14) {
                VStack(spacing: 4) {
                    ChartWidgetRing(ring: ring, value: entry.value)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    caption(ring, compact: false, centered: true)
                }
                .frame(width: 104)
                RingWidgetChart(entry: entry, ring: ring)
            }
        default:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ChartWidgetRing(ring: ring, value: entry.value)
                        .frame(width: 92, height: 92)
                    VStack(alignment: .leading, spacing: 2) {
                        Label(ring.name, systemImage: ring.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ring.tint(entry.value))
                        Text(ring.formatValue(entry.value))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(ring.progressText(entry.value))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(ring.period.status(now: entry.date, calendar: entry.calendar))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                RingWidgetChart(entry: entry, ring: ring)
            }
        }
    }

    private func caption(_ ring: Ring, compact: Bool, centered: Bool = false) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 1) {
            Text(ring.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ring.tint(entry.value))
            Text(ring.progressText(entry.value))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !compact {
                Text(ring.period.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(compact ? 2 : 1)
        .minimumScaleFactor(0.7)
        .multilineTextAlignment(centered ? .center : .leading)
    }
}

/// The ring with its icon and percentage in the middle.
private struct ChartWidgetRing: View {
    let ring: Ring
    let value: Double

    var body: some View {
        RingStackView(rings: [ring.display(value)])
            .overlay {
                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    VStack(spacing: 0) {
                        Image(systemName: ring.symbol)
                            .font(.system(size: size * 0.2, weight: .semibold))
                            .foregroundStyle(ring.tint(value))
                        Text(ring.fraction(value), format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: size * 0.2, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.5)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
    }
}

/// The running value through the period with the goal as a dashed line, in the ring's colour.
private struct RingWidgetChart: View {
    let entry: RingChartEntry
    let ring: Ring
    /// Small widget: smaller axis text.
    var compact = false

    var body: some View {
        let color = ring.tint(entry.value)
        let goal = ring.toDisplay(ring.goal)
        let points = spanning.map { (t: $0.t, v: ring.toDisplay($0.v)) }
        let top = max(goal, points.map(\.v).max() ?? 0, 1) * 1.1
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("Time", p.t), y: .value("Value", p.v))
                    .foregroundStyle(.linearGradient(colors: [color.opacity(0.3), color.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", p.t), y: .value("Value", p.v))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            RuleMark(y: .value("Goal", goal))
                .foregroundStyle(ring.isLimit ? RingDisplay.warningGradient.end : Color.gray)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .annotation(position: compact ? .bottom : .top, alignment: .leading, spacing: 1) {
                    Text(ring.isLimit ? LocalizedStringKey("Limit \(ring.formatValue(ring.goal))")
                                      : LocalizedStringKey("Goal \(ring.formatValue(ring.goal))"))
                        .font(.system(size: compact ? 8 : 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
        .chartXScale(domain: entry.chart.start...entry.chart.end)
        .chartYScale(domain: 0...top)
        .chartXAxis {
            let days = entry.chart.duration / 86_400
            if days <= 1.1 {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.3))
                    AxisValueLabel(format: axisFormat(.dateTime.hour())).font(.system(size: compact ? 8 : 10))
                }
            } else if days <= 7.5 {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.3))
                    AxisValueLabel(format: axisFormat(.dateTime.weekday(.narrow)), centered: true)
                        .font(.system(size: compact ? 8 : 10))
                }
            } else {
                AxisMarks(values: dateTicks(stepDays: days <= 14.5 ? (compact ? 5 : 3) : (compact ? 10 : 7))) { _ in
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.3))
                    AxisValueLabel(format: axisFormat(.dateTime.day().month(.defaultDigits)))
                        .font(.system(size: compact ? 8 : 10))
                }
            }
        }
        .chartYAxis(.hidden)
    }

    private func axisFormat(_ style: Date.FormatStyle) -> Date.FormatStyle {
        var style = style
        style.timeZone = entry.calendar.timeZone
        return style
    }

    /// The chart from the period's start, continuing flat to now through hours or days without anything new.
    private var spanning: [ChartPoint] {
        var points = entry.points
        let now = min(entry.date, entry.chart.end)
        if points.isEmpty {
            // Nothing cached yet (or the period just started): a flat line at the ring's value.
            return [ChartPoint(t: entry.chart.start, v: entry.value), ChartPoint(t: now, v: entry.value)]
        }
        if let last = points.last, last.t < now { points.append(ChartPoint(t: now, v: last.v)) }
        return points
    }

    /// Midnights from the day after the period's start, `stepDays` apart.
    private func dateTicks(stepDays: Int) -> [Date] {
        let calendar = entry.calendar
        var ticks: [Date] = []
        guard var day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: entry.chart.start)) else { return [] }
        while day < entry.chart.end {
            ticks.append(day)
            guard let next = calendar.date(byAdding: .day, value: stepDays, to: day) else { break }
            day = next
        }
        return ticks
    }
}

// MARK: Widget

/// One ring and a chart of its period (Home Screen: small, medium and large).
struct RingChartWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "RingChartWidget", intent: SelectRingIntent.self, provider: RingChartProvider()) { entry in
            RingChartWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(entry.setID.map { URL(string: "everyring://set/\($0.uuidString)")! })
        }
        .configurationDisplayName("Ring and Chart")
        .description("One ring and how it built up through its period.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
#endif
