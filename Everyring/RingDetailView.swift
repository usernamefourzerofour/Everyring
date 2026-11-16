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

    var body: some View {
        if let ring = model.ring(id: ringID) {
            let value = model.value(for: ring)
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

                    StreakCard(ring: ring, streak: history?.streak, loading: loading)

                    HistoryCard(ring: ring, page: page, offset: $pageOffset, calendar: model.calendar)
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
            .task(id: PageKey(ring: ring, offset: pageOffset)) {
                page = await model.historyPage(for: ring, offset: pageOffset)
            }
            .task(id: ring) {
                loading = true
                history = await model.history(for: ring)
                loading = false
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
    @Binding var offset: Int
    let calendar: Calendar

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
                    RollingChart(ring: ring, days: page.days)
                    Text("The value of the last \(n) days, as it stood at the end of each day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .today:
                    DayGrid(ring: ring, records: page.periods, range: page.range, calendar: calendar)
                default:
                    PeriodList(ring: ring, records: page.periods, calendar: calendar)
                }
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

            Text(page?.title(calendar: calendar) ?? "")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 110)
                .contentTransition(.numericText())

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
    }
}

/// A rolling ring's window value per day, with the goal line.
struct RollingChart: View {
    let ring: Ring
    let days: [DayValue]

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
                    VStack(spacing: 2) {
                        RingStackView(rings: [ring.display(record.value)])
                            .frame(width: 30, height: 30)
                        dayNumber(day, bold: record.isCurrent)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityText(record))
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

    var body: some View {
        VStack(spacing: 0) {
            ForEach(records) { record in
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
                .accessibilityElement(children: .combine)
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
