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
        case .count, .minutes, .hours: nil
        }
    }

    private var isSwimming: Bool {
        switch self {
        case .swimmingDistance, .workouts(.distance, kind: .swimming): true
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
        case .count, .minutes, .hours:
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
        guard let unit = displayUnit(locale: locale) else { return baseUnit == .hours && !isCountOfHours ? 0...1 : 0...0 }
        let oneDecimal: [Dimension] = [UnitLength.kilometers, UnitLength.miles, UnitVolume.liters]
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

    /// The unit's name, e.g. "km", "kilometers", "steps", "min".
    func unitName(style: UnitStyle = .short, locale: Locale = .current) -> String {
        if let unit = displayUnit(locale: locale) {
            let formatter = MeasurementFormatter()
            formatter.locale = locale
            formatter.unitStyle = style == .wide ? .long : .short
            return formatter.string(from: unit)
        }
        switch baseUnit {
        case .minutes: return style == .wide ? String(localized: "minutes") : String(localized: "min")
        case .hours: return style == .wide ? String(localized: "hours") : String(localized: "hr")
        default:
            switch self {
            case .steps: return String(localized: "steps")
            case .flightsClimbed: return String(localized: "flights")
            default: return String(localized: "workouts")
            }
        }
    }

    /// E.g. "6,512 steps", "14.2 km", "512 kcal", "45 min", "7 hr 30 min", "1.5 L".
    func format(_ value: Double, style: UnitStyle = .short, locale: Locale = .current) -> String {
        switch baseUnit {
        case .count:
            return String(localized: "\(number(value, locale: locale)) \(unitName(style: style, locale: locale))")
        case .meters, .kilocalories, .liters:
            let unit = displayUnit(locale: locale)!
            let digits = fractionDigits(locale: locale)
            return Measurement(value: max(0, toDisplay(value, locale: locale)), unit: unit)
                .formatted(.measurement(width: style == .wide ? .wide : .abbreviated, usage: .asProvided,
                                        numberFormatStyle: .number.precision(.fractionLength(digits)))
                    .locale(locale))
        case .hours where isCountOfHours:
            return String(localized: "\(number(value, locale: locale)) \(unitName(style: style, locale: locale))")
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
        metric.formatProgress(value, goal: goal)
    }

    /// What VoiceOver reads: "Running, 14 of 20 kilometers, This week · 3 days left, 70 percent".
    func accessibilityText(_ value: Double, now: Date = .now, calendar: Calendar = .current) -> String {
        let percent = Int((fraction(value) * 100).rounded(.down))
        let progress = metric.formatProgress(value, goal: goal, style: .wide)
        let status = period.status(now: now, calendar: calendar)
        return String(localized: "\(name), \(progress), \(status), \(percent) percent")
    }
}
