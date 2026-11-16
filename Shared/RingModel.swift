import Foundation

/// A Health metric a ring can measure. Goals are stored in the metric's `baseUnit` and formatted for the user's locale.
enum HealthMetric: Codable, Hashable, Sendable {
    // Activity
    case steps, activeEnergy, exerciseMinutes, standHours, flightsClimbed
    // Distance
    case walkingRunningDistance, cyclingDistance, swimmingDistance, wheelchairDistance
    // Workouts, optionally only one kind (nil = all workouts)
    case workouts(WorkoutMeasure, kind: WorkoutKind?)
    // Recovery and mind
    case sleep, mindfulMinutes, timeInDaylight
    // Nutrition
    case water
    /// More cumulative quantities (resting energy, nutrients, more distances, …).
    case quantity(QuantityKind)
    /// Counted Health events (toothbrushing, handwashing).
    case events(EventKind)

    enum BaseUnit: String, Codable, Sendable {
        case count, kilocalories, minutes, hours, meters, liters, grams, milligrams
    }

    var baseUnit: BaseUnit {
        switch self {
        case .steps, .flightsClimbed: .count
        case .activeEnergy: .kilocalories
        case .exerciseMinutes, .mindfulMinutes, .timeInDaylight: .minutes
        case .standHours, .sleep: .hours
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
        }
    }

    var title: String {
        switch self {
        case .steps: String(localized: "Steps")
        case .activeEnergy: String(localized: "Active energy")
        case .exerciseMinutes: String(localized: "Exercise minutes")
        case .standHours: String(localized: "Stand hours")
        case .flightsClimbed: String(localized: "Flights climbed")
        case .walkingRunningDistance: String(localized: "Walking + running distance")
        case .cyclingDistance: String(localized: "Cycling distance")
        case .swimmingDistance: String(localized: "Swimming distance")
        case .wheelchairDistance: String(localized: "Wheelchair distance")
        case .workouts(let measure, let kind):
            switch (measure, kind) {
            case (.count, nil): String(localized: "Workouts")
            case (.minutes, nil): String(localized: "Workout minutes")
            case (.distance, nil): String(localized: "Workout distance")
            case (.count, let kind?): String(localized: "\(kind.title) workouts")
            case (.minutes, let kind?): String(localized: "\(kind.title) minutes")
            case (.distance, let kind?): String(localized: "\(kind.title) distance")
            }
        case .sleep: String(localized: "Sleep")
        case .mindfulMinutes: String(localized: "Mindful minutes")
        case .timeInDaylight: String(localized: "Time in daylight")
        case .water: String(localized: "Water")
        case .quantity(let kind): kind.title
        case .events(let kind): kind.title
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

/// Everyring's own ring palette (deliberately not Apple's Activity colours). Colour values live in the drawing code.
enum RingColor: String, Codable, CaseIterable, Sendable {
    case sunrise, tangerine, magenta, violet, indigo, lagoon, fern, citrus
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
