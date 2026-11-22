import Foundation

/// A Health metric a ring can measure. Goals are stored in the metric's `baseUnit` and formatted for the user's locale.
enum HealthMetric: Codable, Hashable, Sendable {
    // Activity
    case steps, activeEnergy, exerciseMinutes, standHours, flightsClimbed
    /// Minutes in the moderate (× 1) and vigorous (× 2) heart rate zones, as the Heart Minutes app counts them.
    case heartMinutes
    // Distance
    case walkingRunningDistance, cyclingDistance, swimmingDistance, wheelchairDistance
    // Workouts, optionally only some kinds or all but some (nil = all workouts). The label stays `kind` so rings
    // saved when it held a single kind still decode.
    case workouts(WorkoutMeasure, kind: WorkoutFilter?)
    // Recovery and mind
    case sleep, mindfulMinutes, timeInDaylight
    /// Time in one sleep stage (as recorded by Apple Watch or a sleep app).
    case sleepStage(SleepStage)
    // Nutrition
    case water
    /// More cumulative quantities (resting energy, nutrients, more distances, …).
    case quantity(QuantityKind)
    /// Counted Health events (toothbrushing, handwashing).
    case events(EventKind)
    /// Fats, cholesterol, sodium, vitamins, minerals and alcoholic drinks.
    case nutrient(NutrientKind)
    /// Symptoms, reproductive health, insulin, falls, heart notifications (see `SensitiveKind`).
    case sensitive(SensitiveKind)

    enum BaseUnit: String, Codable, Sendable {
        case count, kilocalories, minutes, hours, meters, liters, grams, milligrams, micrograms, internationalUnits
    }

    var baseUnit: BaseUnit {
        switch self {
        case .steps, .flightsClimbed: .count
        case .activeEnergy: .kilocalories
        case .exerciseMinutes, .heartMinutes, .mindfulMinutes, .timeInDaylight: .minutes
        case .standHours, .sleep, .sleepStage: .hours
        case .walkingRunningDistance, .cyclingDistance, .swimmingDistance, .wheelchairDistance: .meters
        case .workouts(let measure, _):
            switch measure {
            case .count: .count
            case .minutes: .minutes
            case .distance: .meters
            }
        case .water: .liters
        case .quantity(let kind): kind.baseUnit
        case .events: .count
        case .nutrient(let kind): kind.baseUnit
        case .sensitive(let kind): kind.baseUnit
        }
    }

    var title: String {
        switch self {
        case .steps: String(localized: "Steps")
        case .activeEnergy: String(localized: "Active energy")
        case .exerciseMinutes: String(localized: "Exercise minutes")
        case .heartMinutes: String(localized: "Heart Minutes")
        case .standHours: String(localized: "Stand hours")
        case .flightsClimbed: String(localized: "Flights climbed")
        case .walkingRunningDistance: String(localized: "Walking + running distance")
        case .cyclingDistance: String(localized: "Cycling distance")
        case .swimmingDistance: String(localized: "Swimming distance")
        case .wheelchairDistance: String(localized: "Wheelchair distance")
        case .workouts(let measure, let filter):
            WorkoutFilter.title(measure: measure, filter: filter)
        case .sleep: String(localized: "Sleep")
        case .sleepStage(let stage): stage.title
        case .mindfulMinutes: String(localized: "Mindful minutes")
        case .timeInDaylight: String(localized: "Time in daylight")
        case .water: String(localized: "Water")
        case .quantity(let kind): kind.title
        case .events(let kind): kind.title
        case .nutrient(let kind): kind.title
        case .sensitive(let kind): kind.title
        }
    }
}

/// Sleep stages Health records.
enum SleepStage: String, Codable, CaseIterable, Sendable {
    case core, deep, rem

    var title: String {
        switch self {
        case .core: String(localized: "Core sleep")
        case .deep: String(localized: "Deep sleep")
        case .rem: String(localized: "REM sleep")
        }
    }
}

/// What a workout ring adds up.
enum WorkoutMeasure: String, Codable, CaseIterable, Sendable {
    case count, minutes, distance
}

/// Workout kinds a workout ring can be limited to. Mapped to `HKWorkoutActivityType` in the HealthKit layer.
enum WorkoutKind: String, Codable, CaseIterable, Sendable {
    case running, walking, hiking, cycling, swimming, rowing, elliptical
    case strength, hiit, yoga, pilates, dance, crossTraining
    case coreTraining, flexibility, mixedCardio, stairs
    case tennis, badminton, tableTennis, pickleball, soccer, basketball, golf
    case climbing, martialArts, boxing
    case downhillSkiing, snowboarding, crossCountrySkiing, paddling, skating

    var title: String {
        switch self {
        case .running: String(localized: "Running")
        case .walking: String(localized: "Walking")
        case .hiking: String(localized: "Hiking")
        case .cycling: String(localized: "Cycling")
        case .swimming: String(localized: "Swimming")
        case .rowing: String(localized: "Rowing")
        case .elliptical: String(localized: "Elliptical")
        case .strength: String(localized: "Strength")
        case .hiit: String(localized: "HIIT")
        case .yoga: String(localized: "Yoga")
        case .pilates: String(localized: "Pilates")
        case .dance: String(localized: "Dance")
        case .crossTraining: String(localized: "Cross training")
        case .coreTraining: String(localized: "Core training")
        case .flexibility: String(localized: "Flexibility")
        case .mixedCardio: String(localized: "Mixed cardio")
        case .stairs: String(localized: "Stairs")
        case .tennis: String(localized: "Tennis")
        case .badminton: String(localized: "Badminton")
        case .tableTennis: String(localized: "Table tennis")
        case .pickleball: String(localized: "Pickleball")
        case .soccer: String(localized: "Football")
        case .basketball: String(localized: "Basketball")
        case .golf: String(localized: "Golf")
        case .climbing: String(localized: "Climbing")
        case .martialArts: String(localized: "Martial arts")
        case .boxing: String(localized: "Boxing")
        case .downhillSkiing: String(localized: "Downhill skiing")
        case .snowboarding: String(localized: "Snowboarding")
        case .crossCountrySkiing: String(localized: "Cross-country skiing")
        case .paddling: String(localized: "Paddling")
        case .skating: String(localized: "Skating")
        }
    }

    /// Kinds where a distance goal makes sense.
    var hasDistance: Bool {
        switch self {
        case .running, .walking, .hiking, .cycling, .swimming, .rowing, .downhillSkiing, .snowboarding,
             .crossCountrySkiing, .paddling, .skating: true
        default: false
        }
    }
}

/// Which workouts a workout ring counts: only some kinds, or all but some.
struct WorkoutFilter: Codable, Hashable, Sendable {
    /// In `WorkoutKind.allCases` order, never empty (no filter is `nil`).
    private(set) var kinds: [WorkoutKind]
    /// Count every workout except `kinds`.
    var excludes: Bool

    /// `nil` (all workouts) when `kinds` is empty and nothing is excluded or included.
    static func make(_ kinds: some Sequence<WorkoutKind>, excludes: Bool = false) -> WorkoutFilter? {
        let set = Set(kinds)
        let ordered = WorkoutKind.allCases.filter(set.contains)
        return ordered.isEmpty ? nil : WorkoutFilter(kinds: ordered, excludes: excludes)
    }

    static func only(_ kind: WorkoutKind) -> WorkoutFilter { WorkoutFilter(kinds: [kind], excludes: false) }

    private init(kinds: [WorkoutKind], excludes: Bool) {
        self.kinds = kinds
        self.excludes = excludes
    }

    /// The one kind counted, if that's what the filter is.
    var single: WorkoutKind? { !excludes && kinds.count == 1 ? kinds[0] : nil }

    func includes(_ kind: WorkoutKind) -> Bool { kinds.contains(kind) != excludes }

    /// The filter for a distance ring: kinds without a distance can't be counted, so they are dropped.
    static func adapted(_ filter: WorkoutFilter?, to measure: WorkoutMeasure) -> WorkoutFilter? {
        guard let filter, measure == .distance else { return filter }
        return make(filter.kinds.filter(\.hasDistance), excludes: filter.excludes)
    }

    /// "Strength", "Running and Cycling" or "3 types".
    var listed: String {
        kinds.count <= 2 ? kinds.map(\.title).formatted(.list(type: .and)) : String(localized: "\(kinds.count) types")
    }

    /// "Strength", "Running and Cycling", "3 types", "All except Walking"; "All workouts" for no filter.
    static func summary(_ filter: WorkoutFilter?) -> String {
        guard let filter else { return String(localized: "All workouts") }
        return filter.excludes ? String(localized: "All except \(filter.listed)") : filter.listed
    }

    /// "Workouts", "Strength workouts", "Running and Cycling distance", "Workout minutes except Walking".
    static func title(measure: WorkoutMeasure, filter: WorkoutFilter?) -> String {
        switch (measure, filter) {
        case (.count, nil): String(localized: "Workouts")
        case (.minutes, nil): String(localized: "Workout minutes")
        case (.distance, nil): String(localized: "Workout distance")
        case (.count, let f?) where f.excludes: String(localized: "Workouts except \(f.listed)")
        case (.minutes, let f?) where f.excludes: String(localized: "Workout minutes except \(f.listed)")
        case (.distance, let f?) where f.excludes: String(localized: "Workout distance except \(f.listed)")
        case (.count, let f?): String(localized: "\(f.listed) workouts")
        case (.minutes, let f?): String(localized: "\(f.listed) minutes")
        case (.distance, let f?): String(localized: "\(f.listed) distance")
        }
    }

    private enum CodingKeys: String, CodingKey { case kinds, excludes }

    init(from decoder: Decoder) throws {
        // Rings saved before filters existed hold a single kind.
        if let single = try? decoder.singleValueContainer().decode(WorkoutKind.self) {
            self.init(kinds: [single], excludes: false)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kinds = try c.decode([WorkoutKind].self, forKey: .kinds)
        let excludes = try c.decodeIfPresent(Bool.self, forKey: .excludes) ?? false
        guard let filter = Self.make(kinds, excludes: excludes) else {
            throw DecodingError.dataCorruptedError(forKey: .kinds, in: c, debugDescription: "No workout kinds")
        }
        self = filter
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kinds, forKey: .kinds)
        try c.encode(excludes, forKey: .excludes)
    }
}

/// Everyring's own ring palette (deliberately not Apple's Activity colours). Colour values live in the drawing code.
enum RingColor: String, Codable, CaseIterable, Sendable {
    case sunrise, tangerine, magenta, violet, indigo, lagoon, fern, citrus
}

/// A colour picked freely for a ring (sRGB, 0–1).
struct RingTint: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

/// What a ring of several days measures against its goal.
enum GoalAggregation: String, Codable, CaseIterable, Sendable {
    /// The period's total (steps this week). The goal is for the whole period.
    case total
    /// The average per day over the period (8 hours of sleep a night over the last 30 days). The goal is per day.
    case dailyAverage
    /// The number of days that reach `dailyTarget` (or, for a limit, stay under it): "10,000 steps on 5 days a week".
    /// The goal is a number of days.
    case daysReaching
}

/// How a ring looks once its goal is reached, on the home screen, in widgets and on the watch.
enum ClosedAppearance: String, Codable, CaseIterable, Sendable {
    /// As always.
    case show
    /// Pale and matte, so rings still to do stand out.
    case fade
    /// Not drawn at all: the other rings close up and grow, as if it was never there.
    case hide

    var title: String {
        switch self {
        case .show: String(localized: "Show")
        case .fade: String(localized: "Fade")
        case .hide: String(localized: "Hide")
        }
    }
}

/// Which part of an activity metric a ring counts.
enum ActivityScope: String, Codable, CaseIterable, Sendable {
    /// Everything, all day.
    case all
    /// Only what was logged while a workout ran.
    case duringWorkouts
    /// Only background activity: everything except what was logged during workouts.
    case outsideWorkouts
}

/// Which days of a period of several days count.
enum DayFilter: String, Codable, CaseIterable, Sendable {
    /// `custom`: the days in `Ring.customDays`.
    case everyDay, weekdays, weekends, custom

    var title: String {
        switch self {
        case .everyDay: String(localized: "Every day")
        case .weekdays: String(localized: "Weekdays")
        case .weekends: String(localized: "Weekends")
        case .custom: String(localized: "Custom")
        }
    }

    /// Whether the day that contains `date` counts (weekends as the calendar's locale defines them). `custom` needs
    /// the ring's days: use `Ring.counts(_:calendar:)`.
    func includes(_ date: Date, calendar: Calendar) -> Bool {
        switch self {
        case .everyDay, .custom: true
        case .weekdays: !calendar.isDateInWeekend(date)
        case .weekends: calendar.isDateInWeekend(date)
        }
    }
}

/// Whether a ring's goal is something to reach or a limit to stay under.
enum GoalKind: String, Codable, CaseIterable, Sendable {
    /// Reach at least the goal (steps, exercise). Closes at 100 % and may wrap around.
    case reach
    /// Stay under the goal (calories eaten, sugar). Turns a warning colour past 100 %.
    case limit
}

struct Ring: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var color: RingColor
    /// SF Symbol name.
    var symbol: String
    var metric: HealthMetric
    /// In `metric.baseUnit`.
    var goal: Double
    var period: RingPeriod
    var goalKind: GoalKind = .reach
    /// A freely picked colour that replaces `color` when set.
    var customTint: RingTint?
    /// Total, daily average or days reaching a target; only counts for periods of several days.
    var aggregation: GoalAggregation = .total
    /// For a daily average: leave out days without any data (a night without the watch) instead of counting them as 0.
    var averageSkipsEmptyDays = false
    /// For days reaching: what a day must reach (or stay under, for a limit), in `metric.baseUnit`.
    var dailyTarget: Double = 0
    /// Which days of a period of several days count.
    var days: DayFilter = .everyDay
    /// For `days == .custom`: the weekdays that count, as `Calendar` weekday numbers (1 = Sunday … 7 = Saturday).
    var customDays: [Int] = []
    /// Activity metrics: leave out what was logged during workouts of these kinds (empty: leave out nothing).
    var leftOutWorkouts: [WorkoutKind] = []
    /// Activity metrics: everything, only what was logged during workouts, or only background activity.
    var activity: ActivityScope = .all
    /// Only data from these apps and devices (bundle identifiers; empty: all sources).
    var sources: [String] = []
    /// Workout rings: only workouts at least this long (0: all).
    var minimumWorkoutMinutes = 0
    /// Workout rings: only workouts at most this long (0: no limit).
    var maximumWorkoutMinutes = 0
    /// How the ring looks once its goal is reached (a limit never closes, so always shows).
    var whenClosed: ClosedAppearance = .show

    init(id: UUID = UUID(), name: String, color: RingColor, symbol: String, metric: HealthMetric, goal: Double,
         period: RingPeriod, goalKind: GoalKind = .reach, customTint: RingTint? = nil,
         aggregation: GoalAggregation = .total, averageSkipsEmptyDays: Bool = false, dailyTarget: Double = 0,
         days: DayFilter = .everyDay, customDays: [Int] = [], leftOutWorkouts: [WorkoutKind] = [],
         activity: ActivityScope = .all, sources: [String] = [],
         minimumWorkoutMinutes: Int = 0, maximumWorkoutMinutes: Int = 0,
         whenClosed: ClosedAppearance = .show) {
        self.id = id
        self.name = name
        self.color = color
        self.symbol = symbol
        self.metric = metric
        self.goal = goal
        self.period = period
        self.goalKind = goalKind
        self.customTint = customTint
        self.aggregation = aggregation
        self.averageSkipsEmptyDays = averageSkipsEmptyDays
        self.dailyTarget = dailyTarget
        self.days = days
        self.customDays = customDays
        self.leftOutWorkouts = leftOutWorkouts
        self.activity = activity
        self.sources = sources
        self.minimumWorkoutMinutes = minimumWorkoutMinutes
        self.maximumWorkoutMinutes = maximumWorkoutMinutes
        self.whenClosed = whenClosed
    }

    /// Keys of earlier builds, read only to carry their settings over.
    private enum LegacyKeys: String, CodingKey { case onlyDuringWorkouts }

    private enum CodingKeys: String, CodingKey {
        case id, name, color, symbol, metric, goal, period, goalKind, customTint, aggregation, averageSkipsEmptyDays
        case dailyTarget, days, customDays, leftOutWorkouts, activity, sources, minimumWorkoutMinutes, maximumWorkoutMinutes
        case whenClosed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decode(RingColor.self, forKey: .color)
        symbol = try c.decode(String.self, forKey: .symbol)
        metric = try c.decode(HealthMetric.self, forKey: .metric)
        goal = try c.decode(Double.self, forKey: .goal)
        period = try c.decode(RingPeriod.self, forKey: .period)
        // Rings saved before limits existed are goals to reach.
        goalKind = try c.decodeIfPresent(GoalKind.self, forKey: .goalKind) ?? .reach
        customTint = try c.decodeIfPresent(RingTint.self, forKey: .customTint)
        aggregation = try c.decodeIfPresent(GoalAggregation.self, forKey: .aggregation) ?? .total
        averageSkipsEmptyDays = try c.decodeIfPresent(Bool.self, forKey: .averageSkipsEmptyDays) ?? false
        dailyTarget = try c.decodeIfPresent(Double.self, forKey: .dailyTarget) ?? 0
        days = try c.decodeIfPresent(DayFilter.self, forKey: .days) ?? .everyDay
        customDays = try c.decodeIfPresent([Int].self, forKey: .customDays) ?? []
        leftOutWorkouts = try c.decodeIfPresent([WorkoutKind].self, forKey: .leftOutWorkouts) ?? []
        // Build 14 only had "only during workouts".
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        let legacyDuring = try legacy.decodeIfPresent(Bool.self, forKey: .onlyDuringWorkouts) == true
        activity = try c.decodeIfPresent(ActivityScope.self, forKey: .activity) ?? (legacyDuring ? .duringWorkouts : .all)
        sources = try c.decodeIfPresent([String].self, forKey: .sources) ?? []
        minimumWorkoutMinutes = try c.decodeIfPresent(Int.self, forKey: .minimumWorkoutMinutes) ?? 0
        maximumWorkoutMinutes = try c.decodeIfPresent(Int.self, forKey: .maximumWorkoutMinutes) ?? 0
        whenClosed = try c.decodeIfPresent(ClosedAppearance.self, forKey: .whenClosed) ?? .show
    }

    /// Whether the ring's value must stay under its goal. A days-reaching ring always counts days up to its goal; its
    /// limit applies to each day's target instead.
    var isLimit: Bool { goalKind == .limit && !isDaysReaching }

    /// Whether the ring shows a daily average (its goal is per day). A one-day period is its own average.
    var isAverage: Bool { aggregation == .dailyAverage && period.nominalDays > 1 }

    /// Whether the ring counts days that reach `dailyTarget` (its goal is a number of days).
    var isDaysReaching: Bool { aggregation == .daysReaching && period.nominalDays > 1 }

    /// The days that count: only periods of several days can leave days out.
    var effectiveDays: DayFilter { period.nominalDays > 1 ? days : .everyDay }

    /// Whether the day that contains `date` counts for the ring.
    func counts(_ date: Date, calendar: Calendar) -> Bool {
        switch effectiveDays {
        case .custom: customDays.contains(calendar.component(.weekday, from: date))
        case let filter: filter.includes(date, calendar: calendar)
        }
    }

    /// How many days of a week count (7 for every day).
    func countedDaysPerWeek(calendar: Calendar) -> Int {
        switch effectiveDays {
        case .everyDay: 7
        case .custom: Set(customDays).count
        case .weekdays, .weekends:
            // Weekends as the locale defines them: count them in any one week.
            (0..<7).filter { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) ?? .now
                return effectiveDays.includes(day, calendar: calendar)
            }.count
        }
    }

    /// Whether a day's value meets `dailyTarget` (reached, or for a limit: logged and stayed under).
    func dayMeetsTarget(_ value: Double) -> Bool {
        guard dailyTarget > 0 else { return false }
        return goalKind == .limit ? value > 0 && value <= dailyTarget : value >= dailyTarget
    }

    /// Whether a finished period met the ring: reached the goal, or (for a limit) logged something and stayed
    /// within it. A goal of zero or less is never met.
    func isMet(_ value: Double) -> Bool {
        guard goal > 0 else { return false }
        return isLimit ? value > 0 && value <= goal : value >= goal
    }

    /// Whether the period in progress already counts towards the streak. A limit is only met once its period is over.
    func isMetInProgress(_ value: Double) -> Bool {
        isLimit ? false : isMet(value)
    }

    /// A limit ring past its limit.
    func isOverLimit(_ value: Double) -> Bool {
        isLimit && goal > 0 && value > goal
    }
}

struct RingSet: Codable, Hashable, Identifiable, Sendable {
    static let maxRings = 5

    var id = UUID()
    var name: String
    var rings: [Ring] {
        didSet { if rings.count > Self.maxRings { rings = Array(rings.prefix(Self.maxRings)) } }
    }

    init(id: UUID = UUID(), name: String, rings: [Ring]) {
        self.id = id
        self.name = name
        self.rings = Array(rings.prefix(Self.maxRings))
    }

    var canAddRing: Bool { rings.count < Self.maxRings }
}
