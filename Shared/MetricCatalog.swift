import Foundation

/// Groups, defaults and suggested goals for the metric picker and new rings.
extension HealthMetric {
    enum Category: String, CaseIterable, Identifiable, Sendable {
        case activity, distance, workouts, recovery, nutrition, hygiene

        var id: Self { self }

        var title: String {
            switch self {
            case .activity: String(localized: "Activity")
            case .distance: String(localized: "Distance")
            case .workouts: String(localized: "Workouts")
            case .recovery: String(localized: "Recovery and mind")
            case .nutrition: String(localized: "Nutrition")
            case .hygiene: String(localized: "Hygiene")
            }
        }

        var metrics: [HealthMetric] {
            let more = QuantityKind.allCases.filter { $0.category == self }.map(HealthMetric.quantity)
            switch self {
            case .activity: return [.steps, .activeEnergy, .exerciseMinutes, .standHours, .flightsClimbed] + more
            case .distance:
                return [.walkingRunningDistance, .cyclingDistance, .swimmingDistance, .wheelchairDistance] + more
            case .workouts: return [.workouts(.count, kind: nil), .workouts(.minutes, kind: nil), .workouts(.distance, kind: nil)]
            case .recovery: return [.sleep, .mindfulMinutes, .timeInDaylight]
            case .nutrition: return [.water] + more
            case .hygiene: return EventKind.allCases.map(HealthMetric.events)
            }
        }
    }

    var category: Category {
        switch self {
        case .steps, .activeEnergy, .exerciseMinutes, .standHours, .flightsClimbed: .activity
        case .walkingRunningDistance, .cyclingDistance, .swimmingDistance, .wheelchairDistance: .distance
        case .workouts: .workouts
        case .sleep, .mindfulMinutes, .timeInDaylight: .recovery
        case .water: .nutrition
        case .quantity(let kind): kind.category
        case .events: .hygiene
        }
    }

    var defaultSymbol: String {
        switch self {
        case .steps: "figure.walk"
        case .activeEnergy: "flame"
        case .exerciseMinutes: "bolt.heart"
        case .standHours: "figure.stand"
        case .flightsClimbed: "figure.stairs"
        case .walkingRunningDistance: "shoeprints.fill"
        case .cyclingDistance: "figure.outdoor.cycle"
        case .swimmingDistance: "figure.pool.swim"
        case .wheelchairDistance: "figure.roll"
        case .workouts(_, let kind): kind?.symbol ?? "dumbbell"
        case .sleep: "bed.double"
        case .mindfulMinutes: "brain.head.profile"
        case .timeInDaylight: "sun.max"
        case .water: "drop"
        case .quantity(let kind): kind.symbol
        case .events(let kind): kind.symbol
        }
    }

    var defaultPeriod: RingPeriod {
        switch self {
        case .steps, .activeEnergy, .standHours, .flightsClimbed, .timeInDaylight, .water: .today
        case .exerciseMinutes, .sleep: .rollingDays(7)
        case .walkingRunningDistance, .cyclingDistance, .swimmingDistance, .wheelchairDistance, .workouts, .mindfulMinutes:
            .thisWeek
        case .quantity(let kind): kind.defaultPeriod
        case .events: .today
        }
    }

    /// A typical daily amount, scaled by the period length to suggest a goal.
    private var dailyBaseline: Double {
        switch self {
        case .steps: 8_000
        case .activeEnergy: 500
        case .exerciseMinutes: 30
        case .standHours: 12
        case .flightsClimbed: 10
        case .walkingRunningDistance: 5_000
        case .cyclingDistance: 7_000
        case .swimmingDistance: 300
        case .wheelchairDistance: 3_000
        case .workouts(.count, _): 3.0 / 7
        case .workouts(.minutes, _): 30
        case .workouts(.distance, _): 4_000
        case .sleep: 8
        case .mindfulMinutes: 10
        case .timeInDaylight: 30
        case .water: 2
        case .quantity(let kind): kind.dailyBaseline
        case .events(let kind): kind.dailyBaseline
        }
    }

    /// A round goal for `period`, in the base unit (rounded in the display unit, so "20 km" or "15 mi").
    func suggestedGoal(for period: RingPeriod, locale: Locale = .current) -> Double {
        let display = toDisplay(dailyBaseline * Double(period.nominalDays), locale: locale)
        var goal = Self.roundNicely(display)
        if baseUnit == .count || baseUnit == .minutes { goal = max(1, goal.rounded()) }
        return fromDisplay(goal, locale: locale)
    }

    /// Rounds to one or two significant steps: 3 → 3, 21.7 → 20, 56 → 55, 213 → 200, 10 400 → 10 000.
    static func roundNicely(_ value: Double) -> Double {
        guard value > 0, value.isFinite else { return 0 }
        let magnitude = pow(10, floor(log10(value)))
        let step = magnitude >= 10 ? magnitude / 2 : magnitude / 10
        return max(step, (value / step).rounded() * step)
    }

    /// Metrics that can be limited to one workout kind.
    var isWorkout: Bool {
        if case .workouts = self { true } else { false }
    }
}

extension WorkoutKind {
    var symbol: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .strength: "figure.strengthtraining.traditional"
        case .hiit: "figure.highintensity.intervaltraining"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .dance: "figure.dance"
        case .crossTraining: "figure.cross.training"
        case .coreTraining: "figure.core.training"
        case .flexibility: "figure.flexibility"
        case .mixedCardio: "figure.mixed.cardio"
        case .stairs: "figure.stair.stepper"
        case .tennis: "figure.tennis"
        case .badminton: "figure.badminton"
        case .tableTennis: "figure.table.tennis"
        case .pickleball: "figure.pickleball"
        case .soccer: "figure.soccer"
        case .basketball: "figure.basketball"
        case .golf: "figure.golf"
        case .climbing: "figure.climbing"
        case .martialArts: "figure.martial.arts"
        case .boxing: "figure.boxing"
        case .downhillSkiing: "figure.skiing.downhill"
        case .snowboarding: "figure.snowboarding"
        case .crossCountrySkiing: "figure.skiing.crosscountry"
        case .paddling: "oar.2.crossed"
        case .skating: "figure.skating"
        }
    }
}

extension RingPeriod {
    /// The period's length in days, for scaling suggested goals (a month counts as 30).
    var nominalDays: Int {
        switch self {
        case .today: 1
        case .thisWeek: 7
        case .thisMonth: 30
        case .everyDays(let n, _): max(1, n)
        case .everyWeeks(let n, _): 7 * max(1, n)
        case .rollingDays(let n): max(1, n)
        }
    }

    /// How many finished periods the streak looks back over (about two months of days, half a year of weeks, a year
    /// of months).
    var streakLookback: Int {
        switch self {
        case .today, .rollingDays: 60
        case .thisWeek: 26
        case .thisMonth: 12
        case .everyDays(let n, _): min(60, max(12, 180 / max(1, n)))
        case .everyWeeks(let n, _): min(26, max(12, 26 / max(1, n)))
        }
    }

    /// "4 days", "1 week", "3 months", "2 periods": what a streak of `count` is counted in.
    func streakUnits(_ count: Int) -> String {
        switch self {
        case .today, .rollingDays:
            count == 1 ? String(localized: "1 day") : String(localized: "\(count) days")
        case .thisWeek:
            count == 1 ? String(localized: "1 week") : String(localized: "\(count) weeks")
        case .thisMonth:
            count == 1 ? String(localized: "1 month") : String(localized: "\(count) months")
        case .everyDays, .everyWeeks:
            count == 1 ? String(localized: "1 period") : String(localized: "\(count) periods")
        }
    }
}

extension Ring {
    /// SF Symbols offered in the ring editor.
    static let symbols = [
        "figure.walk", "figure.run", "figure.hiking", "figure.outdoor.cycle", "figure.pool.swim", "figure.roll",
        "figure.stairs", "figure.stand", "figure.strengthtraining.traditional", "figure.yoga", "figure.dance",
        "figure.rower", "figure.highintensity.intervaltraining", "dumbbell", "flame", "bolt.heart", "heart",
        "shoeprints.fill", "bed.double", "moon.zzz", "brain.head.profile", "sun.max", "drop", "leaf", "mountain.2",
        "timer", "star", "trophy",
    ]

    /// A new ring for `metric` with suggested defaults, in a colour not already used by `usedColors` if possible.
    static func new(metric: HealthMetric = .steps, usedColors: [RingColor] = [], locale: Locale = .current) -> Ring {
        let period = metric.defaultPeriod
        let color = RingColor.allCases.first { !usedColors.contains($0) } ?? .sunrise
        return Ring(name: metric.title, color: color, symbol: metric.defaultSymbol, metric: metric,
                    goal: metric.suggestedGoal(for: period, locale: locale), period: period)
    }
}
