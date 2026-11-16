import Charts
import SwiftUI

/// One ring: progress, period, streaks and history.
struct RingDetailView: View {
    @Environment(RingsModel.self) private var model
    let ringID: Ring.ID
    @State private var history: RingHistory?
    @State private var loading = true
    @State private var editing = false
    /// 0 = this month (or year for monthly rings), -1 = the one before, …
    @State private var pageOffset = 0
    @State private var page: HistoryPage?
    @State private var progress: PeriodProgress?
    @State private var pageFailed = false
    /// A period picked in the history for the chart; `nil` = the one in progress.
    @State private var selected: DateInterval?
    @State private var pageRing: Ring?
    /// The ring the chart and streak were read for.
    @State private var loadedRing: Ring?

    var body: some View {
        if let ring = model.ring(id: ringID) {
            let value = model.value(for: ring)
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    RingStackView(rings: [ring.display(value)])
                        .frame(maxWidth: 240)
                        .overlay {
                            VStack(spacing: 2) {
                                Image(systemName: ring.symbol)
                                    .font(.title)
                                    .foregroundStyle(ring.tint(value))
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

                    if let history, !history.hasData {
                        NoDataCard(ring: ring)
                    } else {
                    if let progress {
                        ProgressChartCard(ring: ring, progress: progress, calendar: model.calendar,
                                          onShowCurrent: selected == nil ? nil : { withAnimation { selected = nil } })
                            .id("chart")
                    }

                    StreakCard(ring: ring, streak: history?.streak, loading: loading)

                    HistoryCard(ring: ring, page: page, failed: pageFailed, offset: $pageOffset, calendar: model.calendar,
                                selected: selected) { interval, isCurrent in
                        withAnimation {
                            selected = isCurrent || interval == selected ? nil : interval
                            proxy.scrollTo("chart", anchor: .top)
                        }
                    }
                    }
                }
                .padding()
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
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
            .task(id: PageKey(ring: ring, offset: pageOffset)) {
                // Never show the old page for a changed ring (e.g. today → this week) while the new one loads.
                if pageRing != ring { page = nil }
                pageRing = ring
                page = await withTimeout { await model.historyPage(for: ring, offset: pageOffset) } ?? nil
                pageFailed = page == nil
            }
            .task(id: ring) {
                // A changed ring (another metric, goal or period) must never show the old ring's numbers meanwhile.
                if loadedRing != ring {
                    history = nil
                    progress = nil
                }
                loadedRing = ring
                // One access request first, then the readings one after another (never three sheets at once).
                loading = true
                selected = nil
                await model.requestAccess(for: ring)
                progress = await withTimeout { await model.periodProgress(for: ring) } ?? nil
                history = await withTimeout { await model.history(for: ring) } ?? nil
                loading = false
            }
            .task(id: selected) {
                guard !loading || selected != nil else { return }
                let chosen = selected
                if let next = await withTimeout({ await model.periodProgress(for: ring, interval: chosen) }) ?? nil {
                    withAnimation { progress = next }
                }
            }
        } else {
            ContentUnavailableView("Ring deleted", systemImage: "circle.dashed")
        }
    }
}

/// The ring's value building up through its current period, with the goal and an even pace to it.
struct ProgressChartCard: View {
    let ring: Ring
    let progress: PeriodProgress
    let calendar: Calendar
    /// Shown for a past period: goes back to the one in progress.
    var onShowCurrent: (() -> Void)?

    var body: some View {
        let goal = ring.metric.toDisplay(ring.goal)
        let points = progress.points.map { (date: $0.date, value: ring.metric.toDisplay($0.total)) }
        let lineColor = ring.tint(progress.points.last?.total ?? 0)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "chart.xyaxis.line")
                    .font(.headline)
                    .foregroundStyle(ring.color.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if let onShowCurrent {
                    Button("Now", systemImage: "arrow.uturn.backward", action: onShowCurrent)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(ring.color.color)
                }
            }

            Chart {
                ForEach(points, id: \.date) { point in
                    AreaMark(x: .value("Time", point.date), y: .value("Total", point.value))
                        .foregroundStyle(.linearGradient(colors: [lineColor.opacity(0.3), lineColor.opacity(0.02)],
                                                         startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.date), y: .value("Total", point.value),
                             series: .value("Series", "Total"))
                        .foregroundStyle(lineColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                if let last = points.last {
                    PointMark(x: .value("Time", last.date), y: .value("Total", last.value))
                        .foregroundStyle(lineColor)
                        .symbolSize(60)
                }
                if !ring.period.isRolling {
                    // Even pace from nothing at the start to the goal at the end.
                    // An explicit colour: a series without one gets Swift Charts' default blue.
                    let paceColor = ring.color.color.opacity(0.55)
                    LineMark(x: .value("Time", progress.interval.start), y: .value("Total", 0.0),
                             series: .value("Series", "Pace"))
                        .foregroundStyle(paceColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    LineMark(x: .value("Time", progress.interval.end), y: .value("Total", goal),
                             series: .value("Series", "Pace"))
                        .foregroundStyle(paceColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                        .annotation(position: .bottom, alignment: .trailing, spacing: 4) {
                            Text("Even pace")
                                .font(.caption2)
                                .foregroundStyle(ring.color.color)
                        }
                }
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(ring.isLimit ? RingDisplay.warningGradient.end : Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(ring.isLimit ? LocalizedStringKey("Limit \(ring.metric.format(ring.goal))")
                                          : LocalizedStringKey("Goal \(ring.metric.format(ring.goal))"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXScale(domain: progress.interval.start...progress.interval.end)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: progress.bucket == .hour ? 5 : 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: axisFormat)
                }
            }
            .chartYAxisLabel(ring.metric.unitName())
            .frame(height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)

            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var axisFormat: Date.FormatStyle {
        var style: Date.FormatStyle
        if progress.bucket == .hour {
            style = .dateTime.hour()
        } else if progress.interval.duration <= 8 * 86_400 {
            style = .dateTime.weekday(.abbreviated)
        } else {
            style = .dateTime.day().month(.abbreviated)
        }
        style.timeZone = calendar.timeZone
        return style
    }

    private var title: String {
        if progress.isPast { return ring.period.label(for: progress.interval, calendar: calendar) }
        return ring.period.isRolling ? String(localized: "The last \(ring.period.nominalDays) days") : ring.period.title
    }

    /// "Ahead of an even pace by 1,200 steps" and the like.
    private var summary: String {
        let total = progress.points.last?.total ?? 0
        if progress.isPast {
            let result = ring.progressText(total)
            if ring.isLimit {
                return ring.isMet(total) ? String(localized: "Ended at \(result): under the limit.")
                                         : String(localized: "Ended at \(result).")
            }
            return ring.isMet(total) ? String(localized: "Ended at \(result): goal reached.")
                                     : String(localized: "Ended at \(result).")
        }
        guard let pace = progress.paceNow else {
            return String(localized: "Your total over the window, day by day.")
        }
        let difference = ring.metric.format(abs(total - pace))
        if ring.isLimit {
            return total <= pace
                ? String(localized: "Under an even pace for your limit by \(difference).")
                : String(localized: "Over an even pace for your limit by \(difference).")
        }
        return total >= pace
            ? String(localized: "Ahead of an even pace to your goal by \(difference).")
            : String(localized: "Behind an even pace to your goal by \(difference).")
    }
}

/// Shown instead of chart, streak and history when Health has no data at all for the ring's metric.
struct NoDataCard: View {
    let ring: Ring

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No data", systemImage: "heart.text.square")
                .font(.headline)
                .foregroundStyle(ring.color.color)
            Text("No \(ring.metric.title.lowercased()) data in Health. If you track it, check that Everyring may read it: open the Health app, tap your profile picture, then Apps → Everyring.")
                .font(.callout)
            if let url = URL(string: "x-apple-health://") {
                Link(destination: url) {
                    Label("Open Health", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(ring.color.color)
            }
        }
        .card()
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
                 : ring.isLimit ? "Periods in a row in which you logged something and stayed under the limit."
                                : "Periods in a row in which you closed the ring.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
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

// MARK: History

private struct PageKey: Hashable {
    var ring: Ring
    var offset: Int
}

struct HistoryCard: View {
    let ring: Ring
    let page: HistoryPage?
    var failed = false
    @Binding var offset: Int
    let calendar: Calendar
    var selected: DateInterval?
    /// A period (or, for rolling rings, the window ending on a day) was tapped; `isCurrent` for the one in progress.
    var onSelect: (DateInterval, Bool) -> Void = { _, _ in }

    /// How far back you can page: two years of months, or ten years.
    private var oldestOffset: Int { HistoryPage.unit(for: ring.period) == .year ? -9 : -23 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("History", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(ring.color.color)
                Spacer()
                pager
            }
            if let page {
                switch ring.period {
                case .rollingDays(let n):
                    RollingChart(ring: ring, days: page.days, selectedEnd: selected?.end) { day in
                        let window = ring.period.interval(containing: day, calendar: calendar)
                        onSelect(window, calendar.isDateInToday(day))
                    }
                    Text("The value of the last \(n) days, as it stood at the end of each day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .today:
                    DayGrid(ring: ring, records: page.periods, range: page.range, calendar: calendar,
                            selected: selected, onSelect: onSelect)
                default:
                    PeriodList(ring: ring, records: page.periods, calendar: calendar,
                               selected: selected, onSelect: onSelect)
                }
            } else if failed {
                Text("Couldn’t read Health data. Check Everyring’s access in the Health app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .card()
    }

    private var pager: some View {
        let isYear = HistoryPage.unit(for: ring.period) == .year
        return HStack(spacing: 4) {
            Button {
                offset -= 1
            } label: {
                Image(systemName: "chevron.backward")
                    .frame(width: 32, height: 32)
            }
            .disabled(offset <= oldestOffset)
            .accessibilityLabel(isYear ? "Previous year" : "Previous month")

            // Always one line: the short month name if the full one doesn't fit, then a slightly smaller font.
            ViewThatFits(in: .horizontal) {
                Text(page?.title(calendar: calendar) ?? "")
                Text(page?.title(calendar: calendar, short: true) ?? "")
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(minWidth: 80)

            Button {
                offset += 1
            } label: {
                Image(systemName: "chevron.forward")
                    .frame(width: 32, height: 32)
            }
            .disabled(offset >= 0)
            .accessibilityLabel(isYear ? "Next year" : "Next month")
        }
        .buttonStyle(.borderless)
        .tint(ring.color.color)
        .layoutPriority(1)
    }
}

/// A rolling ring's window value per day, with the goal line.
struct RollingChart: View {
    let ring: Ring
    let days: [DayValue]
    /// The end of the window shown in the period chart, to mark its day.
    var selectedEnd: Date?
    /// A day was tapped: show the window ending that day.
    var onSelectDay: (Date) -> Void = { _ in }
    @State private var rawSelection: Date?

    var body: some View {
        let display = days.map { DayValue(day: $0.day, value: ring.metric.toDisplay($0.value)) }
        let goal = ring.metric.toDisplay(ring.goal)
        Chart {
            ForEach(display) { day in
                AreaMark(x: .value("Day", day.day, unit: .day), y: .value("Value", day.value))
                    .foregroundStyle(.linearGradient(colors: [ring.color.color.opacity(0.35), ring.color.color.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", day.day, unit: .day), y: .value("Value", day.value))
                    .foregroundStyle(ring.color.color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Goal", goal))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Goal \(ring.metric.format(ring.goal))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            if let selectedEnd, let day = days.first(where: { $0.day < selectedEnd && selectedEnd.timeIntervalSince($0.day) <= 86_400 + 3_600 }) {
                RuleMark(x: .value("Day", day.day, unit: .day))
                    .foregroundStyle(ring.color.color.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartXSelection(value: $rawSelection)
        .onChange(of: rawSelection) { _, date in
            // Tapping (or dragging across) the chart picks the window ending on that day.
            guard let date, let day = days.min(by: { abs($0.day.timeIntervalSince(date)) < abs($1.day.timeIntervalSince(date)) })
            else { return }
            onSelectDay(day.day)
        }
        .chartYAxisLabel(ring.metric.unitName())
        .frame(height: 200)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let above = days.filter { ring.isMet($0.value) }.count
        return String(localized: "Chart of the last \(days.count) days. Above the goal on \(above) of them.")
    }
}

/// Daily rings as a calendar: one mini ring per day, weeks in rows starting on the week start.
struct DayGrid: View {
    let ring: Ring
    let records: [PeriodRecord]
    let range: DateInterval
    let calendar: Calendar
    var selected: DateInterval?
    var onSelect: (DateInterval, Bool) -> Void = { _, _ in }

    var body: some View {
        let byDay = Dictionary(records.map { ($0.interval.start, $0) }, uniquingKeysWith: { a, _ in a })
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            ForEach(gridDays, id: \.self) { day in
                if day < range.start || day >= range.end {
                    Color.clear.frame(height: 30)
                        .accessibilityHidden(true)
                } else if let record = byDay[day] {
                    let isSelected = selected == nil ? record.isCurrent : selected == record.interval
                    Button {
                        onSelect(record.interval, record.isCurrent)
                    } label: {
                        VStack(spacing: 2) {
                            RingStackView(rings: [ring.display(record.value)])
                                .frame(width: 30, height: 30)
                            dayNumber(day, bold: record.isCurrent || isSelected)
                        }
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? ring.color.color.opacity(0.15) : .clear, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityText(record))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                } else {
                    // A day still to come.
                    VStack(spacing: 2) {
                        Circle()
                            .strokeBorder(ring.color.color.opacity(0.12), lineWidth: 3.75)
                            .frame(width: 30, height: 30)
                        dayNumber(day, bold: false)
                            .opacity(0.5)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
    }

    private func dayNumber(_ day: Date, bold: Bool) -> some View {
        Text(calendar.component(.day, from: day), format: .number)
            .font(.caption2.monospacedDigit())
            .fontWeight(bold ? .bold : .regular)
            .foregroundStyle(bold ? .primary : .secondary)
    }

    /// Whole weeks (starting on the week start) covering the month.
    private var gridDays: [Date] {
        guard let first = calendar.dateInterval(of: .weekOfYear, for: range.start)?.start,
              let last = calendar.dateInterval(of: .weekOfYear, for: range.end.addingTimeInterval(-1))?.end
        else { return [] }
        var days: [Date] = []
        var day = first
        while day < last {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private func accessibilityText(_ record: PeriodRecord) -> String {
        let label = ring.period.label(for: record.interval, calendar: calendar)
        let state = record.closed ? String(localized: "closed") : String(localized: "not closed")
        return "\(label), \(ring.progressText(record.value)), \(state)"
    }
}

/// Weeks, months or custom periods as a list with mini rings.
struct PeriodList: View {
    let ring: Ring
    let records: [PeriodRecord]
    let calendar: Calendar
    var selected: DateInterval?
    var onSelect: (DateInterval, Bool) -> Void = { _, _ in }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(records) { record in
                let isSelected = selected == nil ? record.isCurrent : selected == record.interval
                Button {
                    onSelect(record.interval, record.isCurrent)
                } label: {
                HStack(spacing: 12) {
                    RingStackView(rings: [ring.display(record.value)])
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.isCurrent ? ring.period.title : ring.period.label(for: record.interval, calendar: calendar))
                            .font(.subheadline.weight(record.isCurrent ? .semibold : .regular))
                        Text(ring.progressText(record.value))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if record.closed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ring.color.color)
                            .accessibilityLabel("Closed")
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .background(isSelected ? ring.color.color.opacity(0.15) : .clear, in: .rect(cornerRadius: 12))
                .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                if record.id != records.last?.id { Divider() }
            }
        }
    }
}

extension View {
    /// The rounded panel used on the detail screen.
    func card() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 20))
    }
}

/// Runs `operation`, but gives up after `seconds` so a Health read that never answers can't leave a spinner forever.
func withTimeout<T: Sendable>(seconds: Double = 20, _ operation: @escaping @MainActor () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
