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
    var total: Double { apps.map(\.minutes).reduce(0, +) }
}

struct PeriodReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .period
    let content: (PeriodBreakdown) -> PeriodView

    /// Apps with their own colour in the stacks; the rest are "Other".
    private static let named = 4

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> PeriodBreakdown {
        var perSlot: [Date: [String: Double]] = [:]
        var perApp: [String: (token: ApplicationToken?, minutes: Double)] = [:]
        var hourly = false
        for await device in data {
            for await segment in device.activitySegments {
                if segment.dateInterval.duration < 2 * 3600 { hourly = true }
                let slot = segment.dateInterval.start
                for await category in segment.categories {
                    for await app in category.applications {
                        let name = app.application.localizedDisplayName ?? app.application.bundleIdentifier ?? "?"
                        let minutes = app.totalActivityDuration / 60
                        perSlot[slot, default: [:]][name, default: 0] += minutes
                        perApp[name] = (app.application.token, (perApp[name]?.minutes ?? 0) + minutes)
                    }
                }
            }
        }
        let ranked = perApp.sorted { $0.value.minutes > $1.value.minutes }
        let named = Set(ranked.prefix(Self.named).map(\.key))
        let other = String(localized: "Other")
        var breakdown = PeriodBreakdown(hourly: hourly)
        breakdown.apps = ranked.prefix(Self.named).map { .init(token: $0.value.token, name: $0.key, minutes: $0.value.minutes) }
        let rest = ranked.dropFirst(Self.named).map(\.value.minutes).reduce(0, +)
        if rest >= 1 { breakdown.apps.append(.init(token: nil, name: other, minutes: rest)) }
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

    /// One shade of the ring's colour per app, deep for the most used; "Other" grey.
    private var shades: [Color] {
        let deep = style?.deepColor ?? .accentColor, light = style?.lightColor ?? .accentColor
        let count = max(breakdown.apps.count, 1)
        return breakdown.apps.enumerated().map { index, app in
            if app.token == nil && index == breakdown.apps.count - 1 && app.name == String(localized: "Other") {
                return Color.gray.opacity(0.45)
            }
            return deep.mix(with: light, by: Double(index) / Double(max(count - 1, 1)) * 0.85)
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
            }
        }
        .padding(.vertical, 4)
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

    private var month: Date {
        style?.calendarMonth ?? calendar.dateInterval(of: .month, for: .now)?.start ?? .now
    }

    /// The month's days, with blanks before the first so it starts on the right weekday.
    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let first = calendar.component(.weekday, from: month)
        let blanks = (first - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: blanks)
            + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdays.indices, id: \.self) { i in
                    Text(weekdays[i]).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(cells.indices, id: \.self) { i in
                    if let day = cells[i] {
                        DayRing(day: day, minutes: days[day], style: style, top: days.values.max() ?? 1)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// One day: a small ring filled towards the daily limit (or the busiest day, without one), the date inside, and the
/// red ! at the tip on a day over the limit.
struct DayRing: View {
    let day: Date
    let minutes: Double?
    let style: ScreenTimeReportStyle?
    let top: Double

    var body: some View {
        let goal = style?.dailyMinutes ?? max(top, 1)
        let fraction = (minutes ?? 0) / goal
        let over = style?.isLimit == true && style?.marksOverLimit != false && fraction > 1
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
            Text(day, format: .dateTime.day())
                .font(.caption2.weight(.medium))
                .foregroundStyle(future ? .tertiary : .primary)
            if over {
                GeometryReader { geo in
                    let r = min(geo.size.width, geo.size.height) / 2 - 2
                    let tip = fraction - fraction.rounded(.down)
                    let angle = (tip * 2 - 0.5) * .pi
                    ZStack {
                        Circle().fill(.white).frame(width: 11, height: 11)
                        Circle().fill(warningRed).frame(width: 9, height: 9)
                        Image(systemName: "exclamationmark").font(.system(size: 6, weight: .black)).foregroundStyle(.white)
                    }
                    .position(x: geo.size.width / 2 + r * cos(angle), y: geo.size.height / 2 + r * sin(angle))
                }
            }
        }
        .frame(width: 36, height: 36)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day, format: .dateTime.day().month()) + Text(verbatim: ", ")
                            + Text(duration(minutes ?? 0)))
    }
}
