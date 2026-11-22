import Charts
import DeviceActivity
import ManagedSettings
import SwiftUI

/// Shows Apple's own Screen Time history for a Screen Time ring's apps on the ring's page: the last four weeks day by
/// day and the apps used most. Runs in a sealed extension: it can draw the numbers but not hand them to the app, so
/// the ring, widgets and watch only count from when the ring was made (see ScreenTimeLog).
@main
struct EveryringScreenTimeReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        HistoryReport { history in
            HistoryView(history: history, style: ScreenTimeReportStyle.load())
        }
    }
}

extension DeviceActivityReport.Context {
    /// Must match the app's `DeviceActivityReport.Context.history`.
    static let history = Self("everyring.history")
}

struct ScreenTimeHistory {
    struct Day: Identifiable {
        var date: Date
        var minutes: Double
        var id: Date { date }
    }

    struct App: Identifiable {
        var token: ApplicationToken?
        var name: String
        var minutes: Double
        var id: String { name }
    }

    var days: [Day] = []
    var apps: [App] = []
}

struct HistoryReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .history
    let content: (ScreenTimeHistory) -> HistoryView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ScreenTimeHistory {
        var byDay: [Date: Double] = [:]
        var byApp: [String: (token: ApplicationToken?, minutes: Double)] = [:]
        let calendar = Calendar.current
        for await device in data {
            for await segment in device.activitySegments {
                let day = calendar.startOfDay(for: segment.dateInterval.start)
                byDay[day, default: 0] += segment.totalActivityDuration / 60
                for await category in segment.categories {
                    for await app in category.applications {
                        let name = app.application.localizedDisplayName ?? app.application.bundleIdentifier ?? "?"
                        let previous = byApp[name]?.minutes ?? 0
                        byApp[name] = (app.application.token, previous + app.totalActivityDuration / 60)
                    }
                }
            }
        }
        var history = ScreenTimeHistory()
        history.days = byDay.map { ScreenTimeHistory.Day(date: $0.key, minutes: $0.value) }.sorted { $0.date < $1.date }
        history.apps = byApp.map { ScreenTimeHistory.App(token: $0.value.token, name: $0.key, minutes: $0.value.minutes) }
            .filter { $0.minutes >= 1 }
            .sorted { $0.minutes > $1.minutes }
            .prefix(5).map { $0 }
        return history
    }
}

struct HistoryView: View {
    let history: ScreenTimeHistory
    let style: ScreenTimeReportStyle?

    private var deep: Color { style.map { Color($0.deep) } ?? .accentColor }
    private var light: Color { style.map { Color($0.light) } ?? .accentColor }
    private static let warning = Color(red: 0.77, green: 0.16, blue: 0.18)

    private var average: Double {
        history.days.isEmpty ? 0 : history.days.map(\.minutes).reduce(0, +) / Double(history.days.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 4 weeks")
                    .font(.headline)
                Spacer()
                Text("≈ \(Self.duration(average)) a day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(history.days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", day.minutes))
                        .foregroundStyle(color(for: day.minutes))
                        .cornerRadius(2)
                }
                if let goal = style?.dailyMinutes {
                    RuleMark(y: .value("Goal", goal))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.gray.opacity(0.3))
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) { Text(Self.duration(minutes)) }
                    }
                }
            }
            .frame(height: 160)

            if !history.apps.isEmpty {
                Text("Most used")
                    .font(.subheadline.weight(.semibold))
                ForEach(history.apps) { app in
                    HStack {
                        if let token = app.token {
                            Label(token).labelStyle(.titleAndIcon)
                        } else {
                            Text(app.name)
                        }
                        Spacer()
                        Text(Self.duration(app.minutes))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding()
    }

    /// Light for small days, deep for big ones; over a limit in the warning colour.
    private func color(for minutes: Double) -> Color {
        if let style, style.isLimit, let goal = style.dailyMinutes, minutes > goal { return Self.warning }
        let top = max(history.days.map(\.minutes).max() ?? 1, 1)
        return light.mix(with: deep, by: min(minutes / top, 1))
    }

    private static func duration(_ minutes: Double) -> String {
        Duration.seconds(minutes.rounded() * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }
}
