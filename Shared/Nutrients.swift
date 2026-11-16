import Foundation

/// Every other cumulative Health nutrition type: fats, cholesterol, sodium, vitamins, minerals and alcoholic drinks.
/// One table, so each type is one row of properties.
enum NutrientKind: String, Codable, CaseIterable, Sendable {
    // Nutrition
    case alcoholicBeverages, saturatedFat, monounsaturatedFat, polyunsaturatedFat, cholesterol, sodium
    // Minerals
    case potassium, calcium, iron, phosphorus, magnesium, zinc, copper, manganese, chloride
    case iodine, selenium, chromium, molybdenum
    // Vitamins
    case vitaminA, vitaminB6, vitaminB12, vitaminC, vitaminD, vitaminE, vitaminK
    case thiamin, riboflavin, niacin, folate, biotin, pantothenicAcid

    private struct Info {
        var title: String
        var unit: HealthMetric.BaseUnit
        /// A typical daily amount (adult reference intake, or a common limit).
        var daily: Double
        var category: HealthMetric.Category
        var symbol: String
        var isLimit = false
    }

    private var info: Info {
        switch self {
        case .alcoholicBeverages:
            Info(title: String(localized: "Alcoholic drinks"), unit: .count, daily: 1, category: .nutrition,
                 symbol: "wineglass", isLimit: true)
        case .saturatedFat:
            Info(title: String(localized: "Saturated fat"), unit: .grams, daily: 20, category: .nutrition,
                 symbol: "drop.circle", isLimit: true)
        case .monounsaturatedFat:
            Info(title: String(localized: "Monounsaturated fat"), unit: .grams, daily: 25, category: .nutrition,
                 symbol: "drop.circle")
        case .polyunsaturatedFat:
            Info(title: String(localized: "Polyunsaturated fat"), unit: .grams, daily: 15, category: .nutrition,
                 symbol: "drop.circle")
        case .cholesterol:
            Info(title: String(localized: "Cholesterol"), unit: .milligrams, daily: 300, category: .nutrition,
                 symbol: "heart.circle", isLimit: true)
        case .sodium:
            Info(title: String(localized: "Sodium"), unit: .milligrams, daily: 2_300, category: .nutrition,
                 symbol: "cube.transparent", isLimit: true)
        case .potassium: Self.mineral(String(localized: "Potassium"), .milligrams, 3_500)
        case .calcium: Self.mineral(String(localized: "Calcium"), .milligrams, 1_000)
        case .iron: Self.mineral(String(localized: "Iron"), .milligrams, 15)
        case .phosphorus: Self.mineral(String(localized: "Phosphorus"), .milligrams, 700)
        case .magnesium: Self.mineral(String(localized: "Magnesium"), .milligrams, 400)
        case .zinc: Self.mineral(String(localized: "Zinc"), .milligrams, 11)
        case .copper: Self.mineral(String(localized: "Copper"), .milligrams, 0.9)
        case .manganese: Self.mineral(String(localized: "Manganese"), .milligrams, 2.3)
        case .chloride: Self.mineral(String(localized: "Chloride"), .milligrams, 2_300)
        case .iodine: Self.mineral(String(localized: "Iodine"), .micrograms, 150)
        case .selenium: Self.mineral(String(localized: "Selenium"), .micrograms, 55)
        case .chromium: Self.mineral(String(localized: "Chromium"), .micrograms, 35)
        case .molybdenum: Self.mineral(String(localized: "Molybdenum"), .micrograms, 45)
        case .vitaminA: Self.vitamin(String(localized: "Vitamin A"), .micrograms, 900)
        case .vitaminB6: Self.vitamin(String(localized: "Vitamin B6"), .milligrams, 1.5)
        case .vitaminB12: Self.vitamin(String(localized: "Vitamin B12"), .micrograms, 2.4)
        case .vitaminC: Self.vitamin(String(localized: "Vitamin C"), .milligrams, 90)
        case .vitaminD: Self.vitamin(String(localized: "Vitamin D"), .micrograms, 15)
        case .vitaminE: Self.vitamin(String(localized: "Vitamin E"), .milligrams, 15)
        case .vitaminK: Self.vitamin(String(localized: "Vitamin K"), .micrograms, 120)
        case .thiamin: Self.vitamin(String(localized: "Thiamin (B1)"), .milligrams, 1.2)
        case .riboflavin: Self.vitamin(String(localized: "Riboflavin (B2)"), .milligrams, 1.3)
        case .niacin: Self.vitamin(String(localized: "Niacin (B3)"), .milligrams, 16)
        case .folate: Self.vitamin(String(localized: "Folate"), .micrograms, 400)
        case .biotin: Self.vitamin(String(localized: "Biotin"), .micrograms, 30)
        case .pantothenicAcid: Self.vitamin(String(localized: "Pantothenic acid (B5)"), .milligrams, 5)
        }
    }

    private static func mineral(_ title: String, _ unit: HealthMetric.BaseUnit, _ daily: Double) -> Info {
        Info(title: title, unit: unit, daily: daily, category: .minerals, symbol: "circle.hexagongrid.fill")
    }

    private static func vitamin(_ title: String, _ unit: HealthMetric.BaseUnit, _ daily: Double) -> Info {
        Info(title: title, unit: unit, daily: daily, category: .vitamins, symbol: "pills")
    }

    var title: String { info.title }
    var baseUnit: HealthMetric.BaseUnit { info.unit }
    var dailyBaseline: Double { info.daily }
    var category: HealthMetric.Category { info.category }
    var symbol: String { info.symbol }
    var defaultGoalKind: GoalKind { info.isLimit ? .limit : .reach }
    var countNoun: String? { self == .alcoholicBeverages ? String(localized: "drinks") : nil }
}
