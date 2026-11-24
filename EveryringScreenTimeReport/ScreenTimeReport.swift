import Charts
import DeviceActivity
import ExtensionKit
import FamilyControls
import ManagedSettings
import SwiftUI

/// Draws Apple's own Screen Time data for a Screen Time ring's apps on the ring's page: the current period broken down
/// by app, and a History calendar of day rings. Runs in a sealed extension: it can draw the numbers but not hand them
/// to the app, so the ring, widgets and watch only count from when the ring was made (see ScreenTimeLog).
@main
struct EveryringScreenTimeReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        PeriodReport { PeriodView(breakdown: $0, style: ScreenTimeReportStyle.load()) }
        CalendarReport { CalendarView(days: $0, style: ScreenTimeReportStyle.load()) }
    }
}

extension DeviceActivityReport.Context {
    /// Must match the app's contexts (RingDetailView).
    static let period = Self("everyring.period")
    static let calendar = Self("everyring.calendar")
}

private let warningRed = Color(red: 0.77, green: 0.16, blue: 0.18)

private func duration(_ minutes: Double) -> String {
    Duration.seconds(minutes.rounded() * 60)
        .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
}

private extension ScreenTimeReportStyle {
    var deepColor: Color { Color(deep) }
    var lightColor: Color { Color(light) }
}

// MARK: - The period, app by app

struct PeriodBreakdown {
    struct Slot: Identifiable {
        var date: Date
        var app: String
        var minutes: Double
        var id: String { "\(date.timeIntervalSince1970)-\(app)" }
    }

    struct App: Identifiable {
        var token: ApplicationToken?
        var name: String
        var minutes: Double
        var id: String { name }
    }

    var slots: [Slot] = []
    /// The apps in the order of the stacks (most used first), "Other" last.
    var apps: [App] = []
    var hourly = false
    struct Site: Identifiable {
        var token: WebDomainToken?
        var name: String
        var minutes: Double
        var id: String { name }
    }

    /// The most visited websites, shown under Safari.
    var sites: [Site] = []
    /// What "Other" holds: the apps after the named ones, and the time tied to no app.
    var otherApps: [App] = []
    var unattributedMinutes = 0.0
    var total: Double { apps.map(\.minutes).reduce(0, +) }
}

struct PeriodReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .period
    let content: (PeriodBreakdown) -> PeriodView

    static let safari = "com.apple.mobilesafari"

    /// Apps with their own colour in the stacks; the rest are "Other".
    private static let named = 4

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> PeriodBreakdown {
        let unattributed = "\u{0}unattributed"
        var perSlot: [Date: [String: Double]] = [:]
        var perApp: [String: (token: ApplicationToken?, minutes: Double)] = [:]
        var hourly = false
        var perSite: [String: (token: WebDomainToken?, minutes: Double)] = [:]
        for await device in data {
            for await segment in device.activitySegments {
                if segment.dateInterval.duration < 2 * 3600 { hourly = true }
                let slot = segment.dateInterval.start
                var counted = 0.0
                var siteMinutes = 0.0
                defer {
                    // Websites and anything Screen Time doesn't put under an app: in "Other", so each bar adds up to
                    // the segment's whole time.
                    let rest = segment.totalActivityDuration / 60 - counted
                    if rest >= 0.5 {
                        perSlot[slot, default: [:]][unattributed, default: 0] += rest
                        perApp[unattributed] = (nil, (perApp[unattributed]?.minutes ?? 0) + rest)
                    }
                    // Safari is the sum of its websites. Screen Time's own Safari time also holds websites it lists
                    // as apps (youtube.com as "YouTube"), which would count twice, plus private browsing and time on
                    // no website, which it can't name. (After "Other" above, so that time doesn't land there.)
                    if let safari = perSlot[slot]?[PeriodReport.safari] {
                        perSlot[slot]?[PeriodReport.safari] = siteMinutes
                        perApp[PeriodReport.safari]?.minutes += siteMinutes - safari
                    }
                }
                for await category in segment.categories {
                    for await app in category.applications {
                        // One entry per app: the same app can come with and without a display name (another device,
                        // or the website of an app), so group by bundle identifier where there is one.
                        let name = app.application.bundleIdentifier ?? app.application.localizedDisplayName ?? "?"
                        let minutes = app.totalActivityDuration / 60
                        counted += minutes
                        perSlot[slot, default: [:]][name, default: 0] += minutes
                        perApp[name] = (perApp[name]?.token ?? app.application.token, (perApp[name]?.minutes ?? 0) + minutes)
                    }
                    // Websites: shown under Safari in the list (their time is part of the browser's, not extra).
                    for await site in category.webDomains {
                        let key = site.webDomain.domain ?? "?"
                        let minutes = site.totalActivityDuration / 60
                        siteMinutes += minutes
                        perSite[key] = (perSite[key]?.token ?? site.webDomain.token, (perSite[key]?.minutes ?? 0) + minutes)
                    }
                }
            }
        }
        let ranked = perApp.filter { $0.key != unattributed && $0.value.minutes >= 0.5 }.sorted { $0.value.minutes > $1.value.minutes }
        let named = Set(ranked.prefix(Self.named).map(\.key))
        let other = String(localized: "Other")
        var breakdown = PeriodBreakdown(hourly: hourly)
        breakdown.sites = perSite.filter { $0.value.minutes >= 1 }
            .sorted { $0.value.minutes > $1.value.minutes }
            .prefix(5)
            .map { .init(token: $0.value.token, name: $0.key, minutes: $0.value.minutes) }
        breakdown.apps = ranked.prefix(Self.named).map { .init(token: $0.value.token, name: $0.key, minutes: $0.value.minutes) }
        let rest = ranked.dropFirst(Self.named).map(\.value.minutes).reduce(0, +) + (perApp[unattributed]?.minutes ?? 0)
        if rest >= 1 { breakdown.apps.append(.init(token: nil, name: other, minutes: rest)) }
        // What "Other" is made of: the next apps, and the time Screen Time ties to no app.
        breakdown.otherApps = ranked.dropFirst(Self.named).prefix(8).filter { $0.value.minutes >= 1 }
            .map { .init(token: $0.value.token, name: $0.key, minutes: $0.value.minutes) }
        breakdown.unattributedMinutes = perApp[unattributed]?.minutes ?? 0
        for (slot, apps) in perSlot {
            for (name, minutes) in apps where minutes > 0 {
                breakdown.slots.append(.init(date: slot, app: named.contains(name) ? name : other, minutes: minutes))
            }
        }
        breakdown.slots.sort { $0.date < $1.date }
        return breakdown
    }
}

struct PeriodView: View {
    let breakdown: PeriodBreakdown
    let style: ScreenTimeReportStyle?

    /// A distinct colour per app, so the stacks tell apps apart whatever the ring's colour; "Other" grey.
    private static let palette: [Color] = [.blue, .orange, .purple, .teal]

    /// What "Other" is made of, indented under it.
    @ViewBuilder private var otherRows: some View {
        ForEach(breakdown.otherApps) { app in
            HStack(spacing: 8) {
                if let token = app.token {
                    Label(token).labelStyle(.titleAndIcon)
                } else {
                    Text(app.name)
                }
                Spacer()
                Text(duration(app.minutes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.footnote)
            .lineLimit(1)
            .padding(.leading, 34)
        }
        if breakdown.unattributedMinutes >= 1 {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.app")
                    .foregroundStyle(.secondary)
                Text("Not tied to an app")
                Spacer()
                Text(duration(breakdown.unattributedMinutes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.footnote)
            .lineLimit(1)
            .padding(.leading, 34)
            Label("Time Screen Time doesn't put under an app or website, such as the Home Screen, calls and system screens.",
                  systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 34)
        }
    }

    /// The most visited websites, indented (under Safari, whose time they are part of).
    private var siteRows: some View {
        ForEach(breakdown.sites) { site in
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                if let token = site.token {
                    Label(token).labelStyle(.titleOnly)
                } else {
                    Text(site.name)
                }
                Spacer()
                Text(duration(site.minutes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.footnote)
            .lineLimit(1)
            .padding(.leading, 34)
        }
    }

    private var shades: [Color] {
        breakdown.apps.enumerated().map { index, app in
            app.token == nil && app.name == String(localized: "Other")
                ? Color.gray.opacity(0.45)
                : Self.palette[index % Self.palette.count]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(breakdown.slots) { slot in
                    BarMark(x: .value("Time", slot.date, unit: breakdown.hourly ? .hour : .day),
                            y: .value("Minutes", slot.minutes))
                        .foregroundStyle(by: .value("App", slot.app))
                }
                if !breakdown.hourly, let goal = style?.dailyMinutes {
                    RuleMark(y: .value("Limit", goal))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(style?.isLimit == true ? warningRed : .secondary)
                }
            }
            .chartForegroundStyleScale(domain: breakdown.apps.map(\.name), range: shades)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.gray.opacity(0.3))
                    AxisValueLabel { if let m = value.as(Double.self) { Text(duration(m)) } }
                }
            }
            .frame(height: 170)

            ForEach(Array(breakdown.apps.enumerated()), id: \.element.id) { index, app in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(shades[index])
                        .frame(width: 12, height: 12)
                    if let token = app.token {
                        Label(token).labelStyle(.titleAndIcon)
                    } else {
                        Text(app.name)
                    }
                    Spacer()
                    Text(duration(app.minutes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .lineLimit(1)
                if app.token == nil && app.name == String(localized: "Other") {
                    otherRows
                }
                if app.name == PeriodReport.safari {
                    siteRows
                    Label("Safari counts time on websites only: private browsing and time on no website aren't included.",
                          systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 34)
                }
            }
            if !breakdown.apps.contains(where: { $0.name == PeriodReport.safari }), !breakdown.sites.isEmpty {
                Text("Websites")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                siteRows
                Label("Private browsing and time on no website aren't included.", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 34)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Opaque, in the card's colour: covers the app's "Fetching…" text underneath once this has drawn.
        .background(.background.secondary)
    }
}

// MARK: - History calendar

struct CalendarReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .calendar
    let content: ([Date: Double]) -> CalendarView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> [Date: Double] {
        var days: [Date: Double] = [:]
        let calendar = Calendar.current
        for await device in data {
            for await segment in device.activitySegments {
                days[calendar.startOfDay(for: segment.dateInterval.start), default: 0] += segment.totalActivityDuration / 60
            }
        }
        return days
    }
}

struct CalendarView: View {
    let days: [Date: Double]
    let style: ScreenTimeReportStyle?
    private let calendar = Calendar.current

    /// The weeks shown: the last five, ending with this one (Screen Time keeps about that much).
    static func weeks(calendar: Calendar = .current, now: Date = .now) -> [[Date]] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let first = calendar.date(byAdding: .weekOfYear, value: -4, to: thisWeek) else { return [] }
        return (0..<5).map { week in
            (0..<7).compactMap { calendar.date(byAdding: .day, value: week * 7 + $0, to: first) }
        }
    }

    private var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    var body: some View {
        let weeks = Self.weeks(calendar: calendar)
        // A plain grid (not lazy): the report is drawn once, in another process.
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                ForEach(weekdays.indices, id: \.self) { i in
                    Text(weekdays[i]).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            ForEach(weeks.indices, id: \.self) { w in
                GridRow {
                    ForEach(weeks[w], id: \.self) { day in
                        DayRing(day: day, minutes: days[day], style: style, top: days.values.max() ?? 1,
                                showsMonth: calendar.component(.day, from: day) == 1 || (w == 0 && day == weeks[0][0]))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background.secondary)
    }
}

/// One day: a small ring filled towards the daily limit (or the busiest day, without one), the date inside, and the
/// day's mark (see DayMark).
struct DayRing: View {
    let day: Date
    let minutes: Double?
    let style: ScreenTimeReportStyle?
    let top: Double
    /// The first day shown and the 1st of a month also name the month.
    var showsMonth = false

    var body: some View {
        let weekday = Calendar.current.component(.weekday, from: day)
        let goal = style?.weekdayMinutes[weekday] ?? style?.dailyMinutes ?? max(top, 1)
        let fraction = (minutes ?? 0) / goal
        let isLimit = style?.isLimit == true
        let past = !Calendar.current.isDateInToday(day) && day < .now
        // As in the app's History: a check for a goal reached (or a limit kept, once the day is over), a cross for a
        // limit passed.
        let mark: DayMark.Kind? = if isLimit && fraction > 1 { style?.marksOverLimit != false ? .over : nil }
            else if isLimit ? (past && (minutes ?? 0) > 0) : fraction >= 1 { .reached }
            else { nil }
        let deep = style?.deepColor ?? .accentColor, light = style?.lightColor ?? .accentColor
        let future = day > .now
        ZStack {
            Circle().stroke(deep.opacity(0.18), lineWidth: 4)
            if let minutes, minutes > 0 {
                Circle()
                    .trim(from: 0, to: min(fraction, 1))
                    .stroke(AngularGradient(colors: [light, deep], center: .center),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: -1) {
                Text(day, format: .dateTime.day())
                    .font(.caption2.weight(.medium))
                if showsMonth {
                    Text(day, format: .dateTime.month(.abbreviated))
                        .font(.system(size: 7, weight: .semibold))
                        .textCase(.uppercase)
                }
            }
            .foregroundStyle(future ? .tertiary : .primary)
        }
        .frame(width: 36, height: 36)
        .dayMark(mark, size: 13)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(day.formatted(.dateTime.day().month())), \(duration(minutes ?? 0))"))
    }
}
