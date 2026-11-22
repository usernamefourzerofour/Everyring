import Charts
import SwiftUI
#if os(iOS)
import DeviceActivity
import FamilyControls
#endif

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
    /// Activity rings: the shown period's workouts.
    @State private var workoutLog: [LoggedWorkout]?
    /// Activity rings: how much of the shown period came from workouts.
    @State private var activitySplit: ActivitySplit?
    /// Sleep rings: the shown period's nights.
    @State private var nightLog: [LoggedNight]?

    var body: some View {
        if let ring = model.ring(id: ringID) {
            let value = model.value(for: ring)
            // A period picked in the history: the ring and its texts show that period too, not only the chart.
            let past = selected != nil && progress?.isPast == true ? progress : nil
            let shown = past?.points.last?.total ?? value
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    RingStackView(rings: [ring.display(shown)])
                        .frame(maxWidth: 240)
                        .animation(.smooth(duration: 0.6), value: shown)
                        .overlay {
                            VStack(spacing: 2) {
                                Image(systemName: ring.symbol)
                                    .font(.title)
                                    .foregroundStyle(ring.tint(shown))
                                Text(ring.fraction(shown), format: .percent.precision(.fractionLength(0)))
                                    .font(.title2.monospacedDigit().weight(.semibold))
                                    .contentTransition(.numericText(value: shown))
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(past.map { ring.accessibilityText(shown, calendar: model.calendar)
                            + ", " + ring.period.label(for: $0.interval, calendar: model.calendar) }
                            ?? model.accessibilityText(for: ring))

                    VStack(spacing: 6) {
                        Text(ring.progressText(shown))
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .contentTransition(.numericText(value: shown))
                        if let past {
                            Text(ring.period.label(for: past.interval, calendar: model.calendar))
                                .foregroundStyle(ring.accent)
                                .fontWeight(.medium)
                        } else {
                            Text(ring.period.status(calendar: model.calendar))
                                .foregroundStyle(.secondary)
                        }
                        let interval = past?.interval ?? ring.period.interval(now: .now, calendar: model.calendar)
                        if let pace = DailyPace.make(for: ring, value: shown, interval: interval, now: .now,
                                                     calendar: model.calendar) {
                            Text("≈ \(ring.metric.formatPerDay(pace.average)) per day")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let text = paceText(pace, ring: ring) {
                                Text(text)
                                    .font(.subheadline)
                                    .foregroundStyle(ring.accent)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }

                    #if os(iOS)
                    if ring.metric == .screenTime {
                        // Screen Time: the period and the History calendar come straight from Screen Time, app by
                        // app and also before the ring was made (drawn by the report extension).
                        ScreenTimePeriodCard(ring: ring)
                        StreakCard(ring: ring, streak: history?.streak, loading: loading)
                        ScreenTimeCalendarCard(ring: ring)
                    }
                    #endif

                    if ring.metric == .screenTime {
                        EmptyView()
                    } else if let history, !history.hasData {
                        NoDataCard(ring: ring)
                    } else {
                    if let progress {
                        ProgressChartCard(ring: ring, progress: progress, calendar: model.calendar,
                                          onShowCurrent: selected == nil ? nil : { withAnimation { selected = nil } })
                            .id("chart")
                    }

                    if ring.metric.supportsWorkoutLeaveOut {
                        WorkoutLogCard(ring: ring, workouts: workoutLog, split: activitySplit, calendar: model.calendar)
                    }
                    if ring.metric.isSleep {
                        NightsCard(ring: ring, nights: nightLog, calendar: model.calendar)
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
            .task(id: WorkoutLogKey(ring: ring, selected: selected)) {
                guard ring.metric.supportsWorkoutLeaveOut else { workoutLog = nil; return }
                workoutLog = nil
                let interval = selected ?? ring.period.interval(now: .now, calendar: model.calendar)
                activitySplit = nil
                workoutLog = await withTimeout { await model.workoutLog(for: ring, interval: interval) } ?? nil
                if workoutLog == nil { workoutLog = [] }
                activitySplit = await withTimeout { await model.activitySplit(for: ring, interval: interval) } ?? nil
            }
            .task(id: WorkoutLogKey(ring: ring, selected: selected)) {
                guard ring.metric.isSleep else { nightLog = nil; return }
                nightLog = nil
                let interval = selected ?? ring.period.interval(now: .now, calendar: model.calendar)
                nightLog = await withTimeout { await model.nightLog(for: ring, interval: interval) } ?? nil
                if nightLog == nil { nightLog = [] }
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
        let goal = ring.toDisplay(ring.goal)
        let points = progress.points.map { (date: $0.date, value: ring.toDisplay($0.total)) }
        let lineColor = ring.tint(progress.points.last?.total ?? 0)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "chart.xyaxis.line")
                    .font(.headline)
                    .foregroundStyle(ring.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if let onShowCurrent {
                    Button("Now", systemImage: "arrow.uturn.backward", action: onShowCurrent)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(ring.accent)
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
                // Days the ring leaves out (weekends for a weekdays ring), shaded behind everything.
                ForEach(progress.leftOutDays, id: \.start) { day in
                    RectangleMark(xStart: .value("Start", day.start), xEnd: .value("End", day.end))
                        .foregroundStyle(Color.secondary.opacity(0.12))
                }
                if progress.paceNow != nil {
                    // Even pace from nothing at the start to the goal at the end, flat over days that don't count.
                    // An explicit colour: a series without one gets Swift Charts' default blue.
                    let paceColor = ring.accent.opacity(0.55)
                    ForEach(progress.pacePoints) { point in
                        LineMark(x: .value("Time", point.date), y: .value("Total", ring.toDisplay(point.total)),
                                 series: .value("Series", "Pace"))
                            .foregroundStyle(paceColor)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    }
                    if let last = progress.pacePoints.last {
                        PointMark(x: .value("Time", last.date), y: .value("Total", ring.toDisplay(last.total)))
                            .symbolSize(0)
                            .annotation(position: .bottom, alignment: .trailing, spacing: 4) {
                                Text("Even pace")
                                    .font(.caption2)
                                    .foregroundStyle(ring.accent)
                            }
                    }
                }
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(ring.isLimit ? RingDisplay.warningGradient.end : Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(ring.isLimit ? LocalizedStringKey("Limit \(ring.formatValue(ring.goal))")
                                          : LocalizedStringKey("Goal \(ring.formatValue(ring.goal))"))
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
            .chartYAxisLabel(ring.valueUnitName)
            .frame(height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)

            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !progress.leftOutDays.isEmpty {
                Label("Shaded days don't count.", systemImage: "square.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(ShadedDayLabelStyle())
            }
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
            if ring.isAverage {
                return String(localized: "Your average per day so far, day by day.")
            }
            if ring.isDaysReaching {
                return String(localized: "Days that reached your target, day by day.")
            }
            return String(localized: "Your total over the window, day by day.")
        }
        if !ring.isLimit && ring.isMet(total) {
            return String(localized: "Goal reached.")
        }
        // Counts of things (workouts, days) are whole: "behind by 0.9 workouts" reads as 1 workout.
        let wholes = ring.metric.baseUnit == .count || ring.isDaysReaching
        let gap = wholes ? abs(total - pace).rounded() : abs(total - pace)
        if wholes ? gap == 0 : ring.metric.number(gap) == ring.metric.number(0) {
            return String(localized: "Right on an even pace.")
        }
        let difference = ring.formatValue(gap)
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
        #if os(iOS)
        if ring.metric == .screenTime {
            ScreenTimeNoDataCard(ring: ring)
        } else {
            healthBody
        }
        #else
        healthBody
        #endif
    }

    private var healthBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No data", systemImage: "heart.text.square")
                .font(.headline)
                .foregroundStyle(ring.accent)
            Text("No \(ring.metric.title.lowercased()) data in Health. If you track it, check that Everyring may read it: open the Health app, tap your profile picture, then Apps → Everyring.")
                .font(.callout)
            if let url = URL(string: "x-apple-health://") {
                Link(destination: url) {
                    Label("Open Health", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(ring.accent)
            }
        }
        .card()
    }
}

#if os(iOS)
/// A Screen Time ring with no minutes yet: says how the minutes arrive and checks each step on the way.
struct ScreenTimeNoDataCard: View {
    let ring: Ring

    var body: some View {
        let manager = ScreenTimeManager.shared
        let selection = ScreenTimeManager.selection(of: ring)
        let picked = (selection?.applicationTokens.count ?? 0) + (selection?.categoryTokens.count ?? 0)
            + (selection?.webDomainTokens.count ?? 0)
        VStack(alignment: .leading, spacing: 12) {
            Label("No minutes yet", systemImage: "hourglass")
                .font(.headline)
                .foregroundStyle(ring.accent)
            Text("Minutes arrive in steps of 5 as you use the chosen apps, so the first shows after 5 minutes. Days before the ring was made stay empty.")
                .font(.callout)
            VStack(alignment: .leading, spacing: 6) {
                check(manager.isAuthorized, "Screen Time access")
                check(picked > 0, "Apps chosen: \(picked)")
                check(manager.isMonitoring(ring), "Followed by iOS")
            }
            .font(.subheadline)
            if !manager.isAuthorized || picked == 0 {
                Text("Tap Edit to allow Screen Time access and choose the apps this ring follows.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = manager.lastError {
                Text(error)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .card()
    }

    private func check(_ ok: Bool, _ title: LocalizedStringKey) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
        }
    }
}
#endif

#if os(iOS)
extension DeviceActivityReport.Context {
    /// Must match the report extension's contexts (EveryringScreenTimeReport).
    static let period = Self("everyring.period")
    static let calendar = Self("everyring.calendar")
}

extension Ring {
    /// What the Screen Time report draws with: the ring's colours, its daily limit and the month to show.
    func screenTimeReportStyle(month: Date? = nil) -> ScreenTimeReportStyle {
        let (deep, light) = gradient
        let environment = EnvironmentValues()
        let daily: Double? = switch aggregation {
        case _ where period.nominalDays <= 1: goal
        case .dailyAverage: goal
        case .daysReaching: dailyTarget
        default: nil
        }
        return ScreenTimeReportStyle(deep: deep.resolve(in: environment), light: light.resolve(in: environment),
                                     dailyMinutes: daily, isLimit: goalKind == .limit, calendarMonth: month,
                                     marksOverLimit: marksOverLimit)
    }

    /// The Screen Time filter for this ring's apps over `interval`, day by day or hour by hour.
    @MainActor func screenTimeFilter(_ interval: DateInterval, hourly: Bool) -> DeviceActivityFilter {
        let selection = ScreenTimeManager.selection(of: self)
        return DeviceActivityFilter(
            segment: hourly ? .hourly(during: interval) : .daily(during: interval),
            users: .all,
            devices: .init([.iPhone, .iPad]),
            applications: selection?.applicationTokens ?? [],
            categories: selection?.categoryTokens ?? [],
            webDomains: selection?.webDomainTokens ?? [])
    }
}

/// The ring's current period from Screen Time, broken down by app.
struct ScreenTimePeriodCard: View {
    let ring: Ring

    var body: some View {
        let interval = ring.period.interval(now: .now, calendar: .current)
        let hourly = ring.period.nominalDays <= 1
        VStack(alignment: .leading, spacing: 8) {
            Label(ring.period.isRolling ? String(localized: "The last \(ring.period.nominalDays) days") : ring.period.title,
                  systemImage: "chart.bar.xaxis")
                .font(.headline)
                .foregroundStyle(ring.accent)
            DeviceActivityReport(.period, filter: ring.screenTimeFilter(interval, hourly: hourly))
                .frame(height: 340)
        }
        .card()
        .onAppear { ring.screenTimeReportStyle(month: ScreenTimeReportStyle.load()?.calendarMonth).save() }
    }
}

/// A calendar of day rings from Screen Time, also for the days before the ring was made.
struct ScreenTimeCalendarCard: View {
    let ring: Ring
    @State private var offset = 0
    /// Two Screen Time reports on one page sometimes leave the second one blank: this one starts a moment after the
    /// page, and can be reloaded by hand.
    @State private var showsReport = false
    @State private var reload = 0
    private let calendar = Calendar.current

    private var month: Date {
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        return calendar.date(byAdding: .month, value: offset, to: thisMonth) ?? thisMonth
    }

    var body: some View {
        let shown = month
        let end = calendar.date(byAdding: .month, value: 1, to: shown) ?? shown
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("History", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(ring.accent)
                Spacer()
                // Screen Time keeps about a month of history.
                Button { move(-1) } label: { Image(systemName: "chevron.backward") }
                    .disabled(offset <= -1)
                Text(shown, format: .dateTime.month(.wide).year())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Button { move(1) } label: { Image(systemName: "chevron.forward") }
                    .disabled(offset >= 0)
                Button { reload += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Reload")
            }
            if showsReport {
                DeviceActivityReport(.calendar, filter: ring.screenTimeFilter(DateInterval(start: shown, end: end), hourly: false))
                    .id("\(offset)-\(reload)")
                    .frame(height: 300)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            }
            Label("History comes straight from Screen Time, also from before the ring was added. The ring, widgets and watch count from when it was added.",
                  systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
        .onAppear { ring.screenTimeReportStyle(month: month).save() }
        .task {
            try? await Task.sleep(for: .milliseconds(700))
            showsReport = true
        }
    }

    private func move(_ step: Int) {
        let next = calendar.date(byAdding: .month, value: offset + step,
                                 to: calendar.dateInterval(of: .month, for: .now)?.start ?? .now) ?? .now
        // The report reads the month when it draws: save it before the filter changes.
        ring.screenTimeReportStyle(month: next).save()
        offset += step
    }
}
#endif

struct StreakCard: View {
    let ring: Ring
    let streak: Streak?
    let loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Streak", systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(ring.accent)
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

/// What is left to do in the rest of the period: today only on its last day, otherwise per day (with a decimal for
/// small counts: "0.5 workouts per day").
private func paceText(_ pace: DailyPace, ring: Ring) -> String? {
    guard let left = pace.perDayLeft, let remaining = pace.remaining else { return nil }
    if pace.daysLeft == 1 {
        let total = ring.metric.format(remaining)
        return ring.isLimit ? String(localized: "\(total) left today within your limit")
                            : String(localized: "\(total) more today to reach your goal")
    }
    let perDay = ring.metric.formatPerDay(left)
    return ring.isLimit ? String(localized: "\(perDay) per day left within your limit")
                        : String(localized: "\(perDay) per day to reach your goal")
}

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
                    .foregroundStyle(ring.accent)
                Spacer()
                pager
            }
            if let page {
                // A calendar of mini rings for every ring (monthly rings page by year: their list has the rings).
                if !page.dayValues.isEmpty {
                    DayGrid(ring: ring, days: page.dayValues, range: page.range, calendar: calendar,
                            selected: selected, selection: selection(for:), onSelect: onSelect)
                    if ring.period.nominalDays > 1 {
                        Text(ring.period.isRolling
                             ? LocalizedStringKey("Each ring shows the last \(ring.period.nominalDays) days as they stood at the end of that day.")
                             : "Each ring shows the period so far, as it stood at the end of that day.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                switch ring.period {
                case .rollingDays:
                    RollingChart(ring: ring, days: page.days, selectedEnd: selected?.end) { day in
                        let window = ring.period.interval(containing: day, calendar: calendar)
                        onSelect(window, calendar.isDateInToday(day))
                    }
                case .today:
                    EmptyView()
                default:
                    if !page.dayValues.isEmpty { Divider() }
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

    /// What tapping a day in the calendar picks: that day, the rolling window ending that day, or the period it's in.
    private func selection(for day: Date) -> (interval: DateInterval, isCurrent: Bool) {
        let now = Date.now
        if ring.period.isRolling {
            let isToday = calendar.isDate(day, inSameDayAs: now)
            return (isToday ? ring.period.interval(now: now, calendar: calendar)
                            : ring.period.interval(containing: day, calendar: calendar), isToday)
        }
        let interval = ring.period.interval(containing: day, calendar: calendar)
        return (interval, interval.contains(now))
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
        .tint(ring.accent)
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
        let display = days.map { DayValue(day: $0.day, value: ring.toDisplay($0.value)) }
        let goal = ring.toDisplay(ring.goal)
        Chart {
            ForEach(display) { day in
                AreaMark(x: .value("Day", day.day, unit: .day), y: .value("Value", day.value))
                    .foregroundStyle(.linearGradient(colors: [ring.accent.opacity(0.35), ring.accent.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", day.day, unit: .day), y: .value("Value", day.value))
                    .foregroundStyle(ring.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Goal", goal))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Goal \(ring.formatValue(ring.goal))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            if let selectedEnd, let day = days.first(where: { $0.day < selectedEnd && selectedEnd.timeIntervalSince($0.day) <= 86_400 + 3_600 }) {
                RuleMark(x: .value("Day", day.day, unit: .day))
                    .foregroundStyle(ring.accent.opacity(0.5))
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
        .chartYAxisLabel(ring.valueUnitName)
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
    /// The ring's value at the end of each day.
    let days: [DayValue]
    let range: DateInterval
    let calendar: Calendar
    var selected: DateInterval?
    /// The period a day stands for (the day, the window ending it, or the period containing it).
    var selection: (Date) -> (interval: DateInterval, isCurrent: Bool)
    var onSelect: (DateInterval, Bool) -> Void = { _, _ in }

    var body: some View {
        let byDay = Dictionary(days.map { ($0.day, $0.value) }, uniquingKeysWith: { a, _ in a })
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
                } else if let value = byDay[day] {
                    let (interval, isCurrent) = selection(day)
                    let isToday = calendar.isDateInToday(day)
                    let isSelected = selected.map { $0 == interval } ?? false
                    // Days the ring leaves out (weekends for a weekdays ring) are drawn faint.
                    let counts = ring.counts(day, calendar: calendar)
                    Button {
                        onSelect(interval, isCurrent)
                    } label: {
                        VStack(spacing: 2) {
                            RingStackView(rings: [ring.display(value)])
                                .frame(width: 30, height: 30)
                                .opacity(counts ? 1 : 0.35)
                            dayNumber(day, bold: isToday || isSelected)
                        }
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? ring.accent.opacity(0.15) : .clear, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityText(day: day, value: value, counts: counts))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                } else {
                    // A day still to come.
                    VStack(spacing: 2) {
                        Circle()
                            .strokeBorder(ring.accent.opacity(0.12), lineWidth: 3.75)
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

    private func accessibilityText(day: Date, value: Double, counts: Bool) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        style.timeZone = calendar.timeZone
        let state = ring.isMet(value) ? String(localized: "closed") : String(localized: "not closed")
        let text = "\(day.formatted(style)), \(ring.progressText(value)), \(state)"
        return counts ? text : text + ", " + String(localized: "doesn't count")
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
                        Text(record.isCurrent ? ring.period.currentLabel(for: record.interval, calendar: calendar)
                                              : ring.period.label(for: record.interval, calendar: calendar))
                            .font(.subheadline.weight(record.isCurrent ? .semibold : .regular))
                        Text(ring.progressText(record.value))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if record.closed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ring.accent)
                            .accessibilityLabel("Closed")
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .background(isSelected ? ring.accent.opacity(0.15) : .clear, in: .rect(cornerRadius: 12))
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

private struct WorkoutLogKey: Hashable {
    var ring: Ring
    var selected: DateInterval?
}

/// Activity rings (steps, energy, exercise minutes, distance): the period's workouts and what was logged during each,
/// so you can see where the numbers came from (and what "leave out workouts" removes).
struct WorkoutLogCard: View {
    let ring: Ring
    /// `nil` while loading.
    let workouts: [LoggedWorkout]?
    /// How much came from workouts; `nil` while loading or if it couldn't be read.
    var split: ActivitySplit?
    let calendar: Calendar
    @State private var showsAll = false
    /// The workout whose timeline is showing.
    @State private var expanded: LoggedWorkout.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Workouts", systemImage: "figure.run")
                .font(.headline)
                .foregroundStyle(ring.accent)
            if let split, split.total > 0 {
                ActivitySplitView(ring: ring, split: split)
                Divider()
            }
            if let workouts {
                if workouts.isEmpty {
                    Text("No workouts logged in this period.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    let shown = showsAll ? workouts : Array(workouts.prefix(8))
                    ForEach(shown) { workout in
                        let isExpanded = expanded == workout.id
                        Button {
                            // Opens and closes at once: a sliding chart overlapped the rows above it.
                            expanded = isExpanded ? nil : workout.id
                        } label: {
                            WorkoutRow(workout: workout, ring: ring, calendar: calendar, isExpanded: isExpanded)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(isExpanded ? LocalizedStringKey("Hides the chart") : "Shows a chart of the workout")
                        if isExpanded {
                            WorkoutTimelineView(ring: ring, workout: workout, calendar: calendar)
                        }
                        if workout.id != shown.last?.id { Divider() }
                    }
                    if workouts.count > shown.count {
                        Button("Show all \(workouts.count)") { withAnimation { showsAll = true } }
                            .font(.subheadline.weight(.semibold))
                            .tint(ring.accent)
                    }
                    Text("\(ring.metric.title) logged while each workout ran. The rest comes from background activity.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .card()
    }
}

private struct WorkoutRow: View {
    let workout: LoggedWorkout
    let ring: Ring
    let calendar: Calendar
    var isExpanded = false

    var body: some View {
        let leftOut = workout.isLeftOut(by: ring)
        let logged = ring.metric.format(workout.value)
        HStack(spacing: 12) {
            Image(systemName: workout.symbol)
                .font(.title3)
                .foregroundStyle(leftOut ? AnyShapeStyle(.secondary) : AnyShapeStyle(ring.accent))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(when) · \(duration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(logged)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .strikethrough(leftOut)
                    .foregroundStyle(leftOut ? .secondary : .primary)
                if leftOut {
                    Text("Left out")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .animation(.snappy, value: isExpanded)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(leftOut
            ? String(localized: "\(workout.title), \(when), \(duration), \(logged), left out")
            : String(localized: "\(workout.title), \(when), \(duration), \(logged)"))
    }

    private var when: String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()
        style.timeZone = calendar.timeZone
        return workout.start.formatted(style)
    }

    private var duration: String {
        Duration.seconds(workout.duration.rounded()).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// Sleep rings: the period's nights, with time asleep and a bar of the sleep stages.
struct NightsCard: View {
    let ring: Ring
    /// `nil` while loading.
    let nights: [LoggedNight]?
    let calendar: Calendar
    @State private var showsAll = false
    /// The night whose chart is showing.
    @State private var expanded: LoggedNight.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Nights", systemImage: "moon.stars")
                .font(.headline)
                .foregroundStyle(ring.accent)
            if let nights {
                if nights.isEmpty {
                    Text("No sleep recorded in this period.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    let shown = showsAll ? nights : Array(nights.prefix(7))
                    ForEach(shown) { night in
                        let isExpanded = expanded == night.id
                        Button {
                            expanded = isExpanded ? nil : night.id
                        } label: {
                            NightRow(night: night, ring: ring, calendar: calendar, isExpanded: isExpanded)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(isExpanded ? LocalizedStringKey("Hides the chart") : "Shows a chart of the night")
                        if isExpanded {
                            NightDetailView(night: night, calendar: calendar)
                        }
                        if night.id != shown.last?.id { Divider() }
                    }
                    if nights.count > shown.count {
                        Button("Show all \(nights.count)") { withAnimation { showsAll = true } }
                            .font(.subheadline.weight(.semibold))
                            .tint(ring.accent)
                    }
                    if nights.contains(where: { !$0.stages.isEmpty }) {
                        StageLegend()
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .card()
    }
}

/// Colours for the stage bar: Everyring's own, not the Health app's.
enum StageStyle {
    static func color(_ stage: SleepStage) -> Color {
        switch stage {
        case .deep: Color(hex: 0x2F4FD8)
        case .core: Color(hex: 0x7A92FF)
        case .rem: Color(hex: 0x41C0D2)
        }
    }

    static let awake = Color(hex: 0xFFB86B)
    static let unspecified = Color.secondary.opacity(0.35)

    static func title(_ stage: SleepStage) -> String {
        switch stage {
        case .deep: String(localized: "Deep")
        case .core: String(localized: "Core")
        case .rem: String(localized: "REM")
        }
    }
}

private struct NightRow: View {
    let night: LoggedNight
    let ring: Ring
    let calendar: Calendar
    var isExpanded = false

    var body: some View {
        let value = night.hours(for: ring.metric)
        let met = ring.dayIsMet(value)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayText)
                        .font(.subheadline.weight(.semibold))
                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ring.metric.format(value))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(met == false ? AnyShapeStyle(.secondary) : AnyShapeStyle(ring.accent))
                    if met == false {
                        Text(ring.goalKind == .limit ? LocalizedStringKey("Over goal") : "Under goal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(.snappy, value: isExpanded)
                    .accessibilityHidden(true)
            }
            StageBar(night: night, highlighted: highlightedStage)
                .frame(height: 8)
            StageDurations(night: night, highlighted: highlightedStage)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(value: value, met: met))
    }

    private var highlightedStage: SleepStage? {
        if case .sleepStage(let stage) = ring.metric { return stage }
        return nil
    }

    private var dayText: String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = calendar.timeZone
        return night.day(calendar: calendar).formatted(style)
    }

    private var timeText: String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = calendar.timeZone
        return "\(night.interval.start.formatted(style)) – \(night.interval.end.formatted(style))"
    }

    private func accessibilityText(value: Double, met: Bool?) -> String {
        var parts = [dayText, timeText, ring.metric.format(value, style: .wide)]
        for stage in SleepStage.allCases {
            if let time = night.stages[stage] {
                parts.append("\(stage.title) \(HealthMetric.sleep.format(time / 3600, style: .wide))")
            }
        }
        if met == false {
            parts.append(ring.goalKind == .limit ? String(localized: "over goal") : String(localized: "under goal"))
        }
        return parts.joined(separator: ", ")
    }
}

/// The night's stages as one bar: deep, core, REM, asleep without a stage, then awake, in proportion. A stage ring
/// shows its own stage in full colour and the rest faded.
private struct StageBar: View {
    let night: LoggedNight
    var highlighted: SleepStage?

    var body: some View {
        let parts = segments
        let total = max(1, parts.reduce(0) { $0 + $1.time })
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle()
                        .fill(part.color.opacity(highlighted == nil || part.stage == highlighted ? 1 : 0.3))
                        .frame(width: max(2, geo.size.width * part.time / total - 1.5))
                }
            }
        }
        .clipShape(.capsule)
        .accessibilityHidden(true)
    }

    private var segments: [(time: TimeInterval, color: Color, stage: SleepStage?)] {
        var result: [(time: TimeInterval, color: Color, stage: SleepStage?)] = []
        for stage in [SleepStage.deep, .core, .rem] {
            if let time = night.stages[stage], time > 0 { result.append((time, StageStyle.color(stage), stage)) }
        }
        if night.unspecified > 60 { result.append((night.unspecified, StageStyle.unspecified, nil)) }
        if night.awake > 60 { result.append((night.awake, StageStyle.awake, nil)) }
        return result
    }
}

private struct StageLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach([SleepStage.deep, .core, .rem], id: \.self) { stage in
                item(StageStyle.color(stage), StageStyle.title(stage))
            }
            item(StageStyle.awake, String(localized: "Awake"))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func item(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }
}

/// A workout unfolded: heart rate and the ring's metric minute by minute.
private struct WorkoutTimelineView: View {
    @Environment(RingsModel.self) private var model
    let ring: Ring
    let workout: LoggedWorkout
    let calendar: Calendar
    @State private var timeline: WorkoutTimeline?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let timeline, !timeline.isEmpty {
                if !timeline.heartRate.isEmpty {
                    heartRateChart(timeline)
                }
                if timeline.perMinute.contains(where: { $0.value > 0 }) {
                    perMinuteChart(timeline)
                }
            } else if loaded {
                Text("No data recorded during this workout.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding(.vertical, 4)
        .task(id: workout.id) {
            timeline = await withTimeout { await model.workoutTimeline(for: ring, workout: workout) } ?? nil
            loaded = true
        }
    }

    private func heartRateChart(_ timeline: WorkoutTimeline) -> some View {
        HeartRateChart(points: timeline.heartRate, domain: workout.start...workout.end, calendar: calendar)
    }

    /// The ring's metric adding up through the workout, from zero at the start to the workout's total.
    private func perMinuteChart(_ timeline: WorkoutTimeline) -> some View {
        let running = timeline.runningTotal(from: workout.start, to: workout.end)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ring.metric.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ring.accent)
                Spacer()
                if let last = running.last {
                    Text(ring.metric.format(last.value))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Chart(running) { point in
                AreaMark(x: .value("Time", point.date), y: .value("Value", ring.metric.toDisplay(point.value)))
                    .foregroundStyle(.linearGradient(colors: [ring.accent.opacity(0.3), ring.accent.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.date), y: .value("Value", ring.metric.toDisplay(point.value)))
                    .foregroundStyle(ring.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            .chartXScale(domain: workout.start...workout.end)
            .chartXAxis { timeAxis }
            .chartYAxisLabel(ring.metric.unitName())
            .frame(height: 90)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(ring.metric.title) through the workout, \(ring.metric.format(workout.value, style: .wide)) in all"))
        }
    }

    private var timeAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine()
            AxisValueLabel(format: timeFormat)
        }
    }

    private var timeFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = calendar.timeZone
        return style
    }

}

/// How much of the period came from workouts and how much from background activity, as a split bar with both amounts.
private struct ActivitySplitView: View {
    let ring: Ring
    let split: ActivitySplit

    var body: some View {
        let share = split.workoutShare
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if share > 0 {
                        Rectangle().fill(ring.accent)
                            .frame(width: max(3, (geo.size.width - 2) * share))
                    }
                    Rectangle().fill(ring.accent.opacity(0.25))
                }
            }
            .frame(height: 10)
            .clipShape(.capsule)
            HStack(alignment: .top) {
                part(color: ring.accent, title: "From workouts", value: split.duringWorkouts, share: share)
                Spacer()
                part(color: ring.accent.opacity(0.25), title: "Background activity", value: split.background, share: 1 - share)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(ring.metric.format(split.duringWorkouts, style: .wide)) from workouts, \(ring.metric.format(split.background, style: .wide)) from background activity"))
    }

    private func part(color: Color, title: LocalizedStringKey, value: Double, share: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.caption)
            }
            Text("\(ring.metric.format(value)) · \(share.formatted(.percent.precision(.fractionLength(0))))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
}

/// Each stage's time under the bar: "Deep 52m · Core 4h 31m · REM 2h 10m · Awake 12m".
private struct StageDurations: View {
    let night: LoggedNight
    var highlighted: SleepStage?

    var body: some View {
        let parts = items
        if !parts.isEmpty {
            // On one line when it fits, otherwise two columns.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { ForEach(parts, id: \.title) { item($0) } }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 4) {
                    ForEach(parts, id: \.title) { item($0) }
                }
            }
            .font(.caption2)
            .accessibilityHidden(true)
        }
    }

    private var items: [(title: String, time: TimeInterval, color: Color, stage: SleepStage?)] {
        var result: [(title: String, time: TimeInterval, color: Color, stage: SleepStage?)] = []
        for stage in [SleepStage.deep, .core, .rem] {
            if let time = night.stages[stage], time > 0 {
                result.append((StageStyle.title(stage), time, StageStyle.color(stage), stage))
            }
        }
        guard !result.isEmpty else { return [] }
        if night.awake >= 60 { result.append((String(localized: "Awake"), night.awake, StageStyle.awake, nil)) }
        return result
    }

    private func item(_ part: (title: String, time: TimeInterval, color: Color, stage: SleepStage?)) -> some View {
        let dimmed = highlighted != nil && part.stage != highlighted
        return HStack(spacing: 4) {
            Circle().fill(part.color).frame(width: 7, height: 7)
            Text(part.title).foregroundStyle(.secondary)
            Text(Duration.seconds(part.time.rounded()).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
                .monospacedDigit()
                .fontWeight(part.stage == highlighted && highlighted != nil ? .bold : .semibold)
        }
        .opacity(dimmed ? 0.5 : 1)
        .fixedSize()
    }
}

/// "▢ Shaded days don't count." with a swatch in the chart's shading.
private struct ShadedDayLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 12, height: 12)
            configuration.title
        }
    }
}

/// Heart rate as a line with a soft area, with average and highest above it. For workouts and nights.
struct HeartRateChart: View {
    let points: [WorkoutTimeline.Point]
    let domain: ClosedRange<Date>
    let calendar: Calendar

    static let color = Color(hex: 0xE8562E)

    var body: some View {
        let values = points.map(\.value)
        let low = (values.min() ?? 60) - 10
        let high = (values.max() ?? 180) + 10
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let peak = values.max()
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Heart rate", systemImage: "heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Self.color)
                Spacer()
                if let average, let peak {
                    Text("Avg \(Int(average.rounded())) · Max \(Int(peak.rounded())) bpm")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Chart(points) { point in
                AreaMark(x: .value("Time", point.date), yStart: .value("Low", low), yEnd: .value("Heart rate", point.value))
                    .foregroundStyle(.linearGradient(colors: [Self.color.opacity(0.25), Self.color.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.date), y: .value("Heart rate", point.value))
                    .foregroundStyle(Self.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: low...high)
            .chartXScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: TimeAxis.format(calendar))
                }
            }
            .frame(height: 110)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(average.map { average in
                String(localized: "Heart rate, average \(Int(average.rounded())), highest \(Int((peak ?? average).rounded())) beats per minute")
            } ?? "")
        }
    }
}

enum TimeAxis {
    /// "05.21": hours and minutes in the ring calendar's time zone.
    static func format(_ calendar: Calendar) -> Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = calendar.timeZone
        return style
    }
}

/// A night unfolded: the sleep stages through the night (awake at the top, deep at the bottom) and the heart rate.
private struct NightDetailView: View {
    @Environment(RingsModel.self) private var model
    let night: LoggedNight
    let calendar: Calendar
    @State private var heartRate: [WorkoutTimeline.Point]?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !night.segments.isEmpty {
                hypnogram
            }
            if let heartRate, !heartRate.isEmpty {
                HeartRateChart(points: heartRate, domain: night.interval.start...night.interval.end, calendar: calendar)
            }
        }
        .padding(.vertical, 4)
        .task(id: night.id) {
            heartRate = await withTimeout { await model.heartRate(during: night) } ?? nil
        }
    }

    private var phases: [LoggedNight.Phase] {
        let present = Set(night.segments.map(\.phase))
        return LoggedNight.Phase.allCases.filter { present.contains($0) || $0 != .asleep }
    }

    private var hypnogram: some View {
        let rows = phases
        return VStack(alignment: .leading, spacing: 6) {
            Label("Sleep stages", systemImage: "moon.zzz")
                .font(.caption.weight(.semibold))
                .foregroundStyle(StageStyle.color(.core))
            Chart(Array(night.segments.enumerated()), id: \.offset) { _, segment in
                let row = Double(rows.firstIndex(of: segment.phase) ?? 0)
                RectangleMark(xStart: .value("Start", segment.interval.start), xEnd: .value("End", segment.interval.end),
                              yStart: .value("Low", row - 0.38), yEnd: .value("High", row + 0.38))
                    .foregroundStyle(Self.color(segment.phase))
                    .clipShape(.rect(cornerRadius: 2))
            }
            .chartXScale(domain: night.interval.start...night.interval.end)
            .chartYScale(domain: -0.5...(Double(rows.count) - 0.5))
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(0..<rows.count).map(Double.init)) { value in
                    AxisValueLabel {
                        if let index = value.as(Double.self).map(Int.init), rows.indices.contains(index) {
                            Text(Self.title(rows[index]))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: TimeAxis.format(calendar))
                }
            }
            .frame(height: CGFloat(rows.count) * 26 + 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Sleep stages through the night"))
        }
    }

    static func color(_ phase: LoggedNight.Phase) -> Color {
        switch phase {
        case .deep: StageStyle.color(.deep)
        case .core: StageStyle.color(.core)
        case .rem: StageStyle.color(.rem)
        case .asleep: StageStyle.color(.core).opacity(0.6)
        case .awake: StageStyle.awake
        }
    }

    static func title(_ phase: LoggedNight.Phase) -> String {
        switch phase {
        case .deep: StageStyle.title(.deep)
        case .core: StageStyle.title(.core)
        case .rem: StageStyle.title(.rem)
        case .asleep: String(localized: "Asleep")
        case .awake: String(localized: "Awake")
        }
    }
}
