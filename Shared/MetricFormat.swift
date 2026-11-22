import Foundation

/// How long unit names are: "km" or "kilometers".
enum UnitStyle: Sendable {
    case short, wide
}

/// Locale-aware units and formatting of ring values. Values are stored in the metric's `baseUnit`; the user sees and
/// enters them in the display unit for their locale (km or mi, m or yd, kcal or kJ, L or fl oz).
extension HealthMetric {
    private var baseDimension: Dimension? {
        switch baseUnit {
        case .meters: UnitLength.meters
        case .kilocalories: UnitEnergy.kilocalories
        case .liters: UnitVolume.liters
        case .grams: UnitMass.grams
        case .milligrams: UnitMass.milligrams
        case .micrograms: UnitMass.micrograms
        case .count, .minutes, .hours, .internationalUnits: nil
        }
    }

    private var isSwimming: Bool {
        switch self {
        case .swimmingDistance: true
        case .workouts(.distance, let filter): filter?.single == .swimming
        default: false
        }
    }

    /// The unit values are shown and entered in, or `nil` for counts and durations.
    func displayUnit(locale: Locale = .current) -> Dimension? {
        let imperial = locale.measurementSystem != .metric
        switch baseUnit {
        case .meters:
            if isSwimming { return imperial ? UnitLength.yards : UnitLength.meters }
            return imperial ? UnitLength.miles : UnitLength.kilometers
        case .kilocalories:
            let kilojouleRegions: Set<String> = ["AU", "NZ"]
            return kilojouleRegions.contains(locale.region?.identifier ?? "") ? UnitEnergy.kilojoules : UnitEnergy.kilocalories
        case .liters:
            return locale.measurementSystem == .us ? UnitVolume.fluidOunces : UnitVolume.liters
        case .grams:
            // Nutrition labels use grams everywhere.
            return UnitMass.grams
        case .milligrams:
            return UnitMass.milligrams
        case .micrograms:
            return UnitMass.micrograms
        case .count, .minutes, .hours, .internationalUnits:
            return nil
        }
    }

    /// A base-unit value in the display unit.
    func toDisplay(_ value: Double, locale: Locale = .current) -> Double {
        guard let base = baseDimension, let unit = displayUnit(locale: locale) else { return value }
        return Measurement(value: value, unit: base).converted(to: unit).value
    }

    /// A display-unit value back in the base unit.
    func fromDisplay(_ value: Double, locale: Locale = .current) -> Double {
        guard let base = baseDimension, let unit = displayUnit(locale: locale) else { return value }
        return Measurement(value: value, unit: unit).converted(to: base).value
    }

    private func fractionDigits(locale: Locale) -> ClosedRange<Int> {
        guard let unit = displayUnit(locale: locale) else {
            return (baseUnit == .hours && !isCountOfHours) || baseUnit == .internationalUnits ? 0...1 : 0...0
        }
        // Small nutrient amounts (0.9 mg copper, 2.4 µg B12) need a decimal too.
        let oneDecimal: [Dimension] = [UnitLength.kilometers, UnitLength.miles, UnitVolume.liters, UnitMass.grams,
                                       UnitMass.milligrams, UnitMass.micrograms]
        return oneDecimal.contains(unit) ? 0...1 : 0...0
    }

    /// Stand hours count hours (whole hours in which you stood), not a duration like sleep.
    private var isCountOfHours: Bool { self == .standHours }

    /// The bare number in the display unit, e.g. "8.8" or "6,512".
    func number(_ value: Double, locale: Locale = .current) -> String {
        let display = max(0, toDisplay(value, locale: locale))
        let digits = fractionDigits(locale: locale)
        // Never round up to the goal before it is reached.
        let factor = pow(10, Double(digits.upperBound))
        return ((display * factor).rounded(.down) / factor)
            .formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    /// The unit's name, e.g. "km", "kilometers", "steps", "min"; "step", "workout" for exactly one (`singular`).
    func unitName(style: UnitStyle = .short, locale: Locale = .current, singular: Bool = false) -> String {
        if let unit = displayUnit(locale: locale) {
            let formatter = MeasurementFormatter()
            formatter.locale = locale
            formatter.unitStyle = style == .wide ? .long : .short
            return formatter.string(from: unit)
        }
        switch baseUnit {
        case .minutes: return style == .wide ? String(localized: "minutes") : String(localized: "min")
        case .hours:
            if style == .wide { return singular ? String(localized: "hour") : String(localized: "hours") }
            return String(localized: "hr")
        default:
            let times = singular ? String(localized: "time") : String(localized: "times")
            switch self {
            case .steps: return singular ? String(localized: "step") : String(localized: "steps")
            case .flightsClimbed: return singular ? String(localized: "flight") : String(localized: "flights")
            case .quantity(let kind): return kind.countNoun(singular: singular) ?? times
            case .nutrient(let kind): return kind.countNoun(singular: singular) ?? times
            case .events: return times
            case .sensitive(let kind):
                return kind.baseUnit == .internationalUnits ? String(localized: "IU") : kind.countNoun(singular: singular)
            default: return singular ? String(localized: "workout") : String(localized: "workouts")
            }
        }
    }

    /// A rate per day: like `format`, but small counts keep one decimal ("0.3 workouts", "2.5 times") instead of
    /// rounding down to a whole number.
    func formatPerDay(_ value: Double, style: UnitStyle = .short, locale: Locale = .current) -> String {
        let isCount = baseUnit == .count || isCountOfHours
        guard isCount, value < 10 else { return format(value, style: style, locale: locale) }
        let text = max(0, value).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        let one = 1.formatted(.number.locale(locale))
        return String(localized: "\(text) \(unitName(style: style, locale: locale, singular: text == one))")
    }

    /// "1 step", "2 steps": a number with its count noun.
    private func counted(_ value: Double, style: UnitStyle, locale: Locale) -> String {
        let text = number(value, locale: locale)
        let one = 1.formatted(.number.locale(locale))
        return String(localized: "\(text) \(unitName(style: style, locale: locale, singular: text == one))")
    }

    /// E.g. "6,512 steps", "14.2 km", "512 kcal", "45 min", "7 hr 30 min", "1.5 L".
    func format(_ value: Double, style: UnitStyle = .short, locale: Locale = .current) -> String {
        switch baseUnit {
        case .count, .internationalUnits:
            return counted(value, style: style, locale: locale)
        case .meters, .kilocalories, .liters, .grams, .milligrams, .micrograms:
            let unit = displayUnit(locale: locale)!
            let digits = fractionDigits(locale: locale)
            return Measurement(value: max(0, toDisplay(value, locale: locale)), unit: unit)
                .formatted(.measurement(width: style == .wide ? .wide : .abbreviated, usage: .asProvided,
                                        numberFormatStyle: .number.precision(.fractionLength(digits)))
                    .locale(locale))
        case .hours where isCountOfHours:
            return counted(value, style: style, locale: locale)
        case .minutes, .hours:
            let seconds = (baseUnit == .hours ? value * 3600 : value * 60).rounded(.down)
            let allowed: Set<Duration.UnitsFormatStyle.Unit> =
                baseUnit == .hours && seconds >= 60 ? [.hours, .minutes] : [.minutes]
            let width: Duration.UnitsFormatStyle.UnitWidth = style == .wide ? .wide : .abbreviated
            let zero: Duration.UnitsFormatStyle.ZeroValueUnitsDisplayStrategy = seconds < 60 ? .show(length: 1) : .hide
            return Duration.seconds(max(0, seconds))
                .formatted(.units(allowed: allowed, width: width, zeroValueUnits: zero)
                    .locale(locale))
        }
    }

    /// Value and goal in the same unit: "6,512 of 10,000 steps", "8.8 of 62.1 mi", "6 hr 30 min of 8 hr".
    func formatProgress(_ value: Double, goal: Double, style: UnitStyle = .short, locale: Locale = .current) -> String {
        let goalText = format(goal, style: style, locale: locale)
        let isDuration = baseUnit == .hours && !isCountOfHours
        let valueText = isDuration ? format(value, style: style, locale: locale) : number(value, locale: locale)
        return String(localized: "\(valueText) of \(goalText)")
    }
}

extension Ring {
    /// Fraction of the goal reached; may exceed 1.
    func fraction(_ value: Double) -> Double {
        goal > 0 ? max(0, value) / goal : 0
    }

    /// "6,512 of 10,000 steps", shown under the ring name.
    func progressText(_ value: Double) -> String {
        if isDaysReaching {
            return String(localized: "\(Int(value.rounded())) of \(Int(goal.rounded())) days")
        }
        let text = metric.formatProgress(value, goal: goal)
        return isAverage ? String(localized: "\(text) a day") : text
    }

    /// The goal as listed: "10,000 steps", "8 hr a day", or "10,000 steps on 5 days".
    var goalText: String {
        if isDaysReaching {
            let target = metric.format(dailyTarget)
            let days = Int(goal.rounded())
            return goalKind == .limit ? String(localized: "Under \(target) on \(days) days")
                                      : String(localized: "\(target) on \(days) days")
        }
        return isAverage ? String(localized: "\(metric.format(goal)) a day") : metric.format(goal)
    }

    /// A value of the ring as text: in the metric's unit, or a number of days for a days-reaching ring.
    func formatValue(_ value: Double) -> String {
        guard isDaysReaching else { return metric.format(value) }
        let days = Int(value.rounded())
        return days == 1 ? String(localized: "1 day") : String(localized: "\(days) days")
    }

    /// A value of the ring in the unit it's shown in (km, mi, kcal, …; days for a days-reaching ring), for charts.
    func toDisplay(_ value: Double) -> Double {
        isDaysReaching ? value : metric.toDisplay(value)
    }

    /// The unit of the ring's values, for chart axes.
    var valueUnitName: String {
        isDaysReaching ? String(localized: "days") : metric.unitName()
    }

    /// What VoiceOver reads: "Running, 14 of 20 kilometers, This week · 3 days left, 70 percent".
    func accessibilityText(_ value: Double, now: Date = .now, calendar: Calendar = .current) -> String {
        let percent = Int((fraction(value) * 100).rounded(.down))
        let total = metric.formatProgress(value, goal: goal, style: .wide)
        let progress: String
        if isDaysReaching {
            // "3 of 5 days with 10,000 steps" / "3 of 5 days under 2,000 kilocalories"
            let target = metric.format(dailyTarget, style: .wide)
            progress = goalKind == .limit ? String(localized: "\(progressText(value)) under \(target)")
                                          : String(localized: "\(progressText(value)) with \(target)")
        } else {
            progress = isAverage ? String(localized: "\(total) a day on average") : total
        }
        let status = period.status(now: now, calendar: calendar)
        if isOverLimit(value) {
            return String(localized: "\(name), \(progress), \(status), \(percent) percent, over the limit")
        }
        return String(localized: "\(name), \(progress), \(status), \(percent) percent")
    }
}
