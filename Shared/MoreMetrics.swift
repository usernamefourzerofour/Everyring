import Foundation

/// More cumulative Health quantities a ring can sum. Kept as a table so a new type is one case with its properties.
enum QuantityKind: String, Codable, CaseIterable, Sendable {
    // Activity
    case restingEnergy, moveTime, standTime, wheelchairPushes
    // Distance and sports
    case rowingDistance, paddleDistance, skatingDistance, crossCountrySkiingDistance, downhillSnowDistance
    case swimmingStrokes
    // Nutrition
    case dietaryEnergy, protein, carbohydrates, fat, fiber, sugar, caffeine

    var baseUnit: HealthMetric.BaseUnit {
        switch self {
        case .restingEnergy, .dietaryEnergy: .kilocalories
        case .moveTime, .standTime: .minutes
        case .wheelchairPushes, .swimmingStrokes: .count
        case .rowingDistance, .paddleDistance, .skatingDistance, .crossCountrySkiingDistance, .downhillSnowDistance:
            .meters
        case .protein, .carbohydrates, .fat, .fiber, .sugar: .grams
        case .caffeine: .milligrams
        }
    }

    var title: String {
        switch self {
        case .restingEnergy: String(localized: "Resting energy")
        case .moveTime: String(localized: "Move time")
        case .standTime: String(localized: "Stand minutes")
        case .wheelchairPushes: String(localized: "Wheelchair pushes")
        case .rowingDistance: String(localized: "Rowing distance")
        case .paddleDistance: String(localized: "Paddling distance")
        case .skatingDistance: String(localized: "Skating distance")
        case .crossCountrySkiingDistance: String(localized: "Cross-country skiing distance")
        case .downhillSnowDistance: String(localized: "Downhill skiing distance")
        case .swimmingStrokes: String(localized: "Swimming strokes")
        case .dietaryEnergy: String(localized: "Calories eaten")
        case .protein: String(localized: "Protein")
        case .carbohydrates: String(localized: "Carbohydrates")
        case .fat: String(localized: "Fat")
        case .fiber: String(localized: "Fiber")
        case .sugar: String(localized: "Sugar")
        case .caffeine: String(localized: "Caffeine")
        }
    }

    var category: HealthMetric.Category {
        switch self {
        case .restingEnergy, .moveTime, .standTime, .wheelchairPushes: .activity
        case .rowingDistance, .paddleDistance, .skatingDistance, .crossCountrySkiingDistance, .downhillSnowDistance,
             .swimmingStrokes: .distance
        case .dietaryEnergy, .protein, .carbohydrates, .fat, .fiber, .sugar, .caffeine: .nutrition
        }
    }

    var symbol: String {
        switch self {
        case .restingEnergy: "flame.circle"
        case .moveTime: "figure.walk.motion"
        case .standTime: "figure.stand"
        case .wheelchairPushes: "figure.roll"
        case .rowingDistance: "figure.rower"
        case .paddleDistance: "oar.2.crossed"
        case .skatingDistance: "figure.skating"
        case .crossCountrySkiingDistance: "figure.skiing.crosscountry"
        case .downhillSnowDistance: "figure.skiing.downhill"
        case .swimmingStrokes: "figure.pool.swim"
        case .dietaryEnergy: "fork.knife"
        case .protein: "fish"
        case .carbohydrates: "carrot"
        case .fat: "drop.circle"
        case .fiber: "leaf"
        case .sugar: "cube"
        case .caffeine: "cup.and.saucer"
        }
    }

    var defaultPeriod: RingPeriod {
        switch category {
        case .distance: .thisWeek
        default: .today
        }
    }

    /// A typical daily amount in the base unit.
    var dailyBaseline: Double {
        switch self {
        case .restingEnergy: 1_600
        case .moveTime: 30
        case .standTime: 120
        case .wheelchairPushes: 1_000
        case .rowingDistance: 2_000
        case .paddleDistance: 2_000
        case .skatingDistance: 3_000
        case .crossCountrySkiingDistance: 5_000
        case .downhillSnowDistance: 10_000
        case .swimmingStrokes: 500
        case .dietaryEnergy: 2_200
        case .protein: 60
        case .carbohydrates: 250
        case .fat: 70
        case .fiber: 30
        case .sugar: 40
        case .caffeine: 200
        }
    }

    /// What counts are called ("pushes", "strokes"), for count metrics.
    var countNoun: String? {
        switch self {
        case .wheelchairPushes: String(localized: "pushes")
        case .swimmingStrokes: String(localized: "strokes")
        default: nil
        }
    }
}

/// Health events a ring can count.
enum EventKind: String, Codable, CaseIterable, Sendable {
    case toothbrushing, handwashing

    var title: String {
        switch self {
        case .toothbrushing: String(localized: "Toothbrushing")
        case .handwashing: String(localized: "Handwashing")
        }
    }

    var symbol: String {
        switch self {
        case .toothbrushing: "mouth"
        case .handwashing: "hands.and.sparkles"
        }
    }

    var dailyBaseline: Double {
        switch self {
        case .toothbrushing: 2
        case .handwashing: 6
        }
    }
}
