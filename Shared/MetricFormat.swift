import Foundation

/// How long unit names are: "km" or "kilometers".
enum UnitStyle: Sendable {
    case short, wide

    fileprivate func measurementWidth<U: Dimension>() -> Measurement<U>.FormatStyle.UnitWidth {
        self == .wide ? .wide : .abbreviated
    }
}

/// Locale-aware formatting of ring values. Values are in the metric's `baseUnit`.
extension HealthMetric {
    /// E.g. "6,512 steps", "14.2 km", "512 kcal", "45 min", "7 hr 30 min", "1.5 L".
    func format(_ value: Double, style: UnitStyle = .short, locale: Locale = .current) -> String {
        switch baseUnit {
        case .count:
            let n = Int(max(0, value).rounded(.down)).formatted(.number.locale(locale))
            switch self {
            case .steps: return String(localized: "\(n) steps")
            case .flightsClimbed: return String(localized: "\(n) flights")
            default: return String(localized: "\(n) workouts")
            }
        case .kilocalories:
            return Measurement(value: value, unit: UnitEnergy.kilocalories)
                .formatted(.measurement(width: style.measurementWidth(), usage: .workout,
                                        numberFormatStyle: .number.precision(.fractionLength(0)))
                    .locale(locale))
        case .meters:
            let usage: MeasurementFormatUnitUsage<UnitLength> = self == .swimmingDistance ? .asProvided : .road
            let digits = value >= 100_000 ? 0...0 : 0...1
            return Measurement(value: value, unit: UnitLength.meters)
                .formatted(.measurement(width: style.measurementWidth(), usage: usage,
                                        numberFormatStyle: .number.precision(.fractionLength(digits)))
                    .locale(locale))
        case .liters:
            return Measurement(value: value, unit: UnitVolume.liters)
                .formatted(.measurement(width: style.measurementWidth(), usage: .general,
                                        numberFormatStyle: .number.precision(.fractionLength(0...1)))
                    .locale(locale))
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
}

extension Ring {
    /// Fraction of the goal reached; may exceed 1.
    func fraction(_ value: Double) -> Double {
        goal > 0 ? max(0, value) / goal : 0
    }

    /// "6,512 steps of 10,000 steps" style, shown under the ring name.
    func progressText(_ value: Double) -> String {
        String(localized: "\(metric.format(value)) of \(metric.format(goal))")
    }

    /// What VoiceOver reads: "Running, 14 kilometers of 20 kilometers, This week · 3 days left, 70 percent".
    func accessibilityText(_ value: Double, now: Date = .now, calendar: Calendar = .current) -> String {
        let percent = Int((fraction(value) * 100).rounded(.down))
        let progress = metric.format(value, style: .wide)
        let goalText = metric.format(goal, style: .wide)
        let status = period.status(now: now, calendar: calendar)
        return String(localized: "\(name), \(progress) of \(goalText), \(status), \(percent) percent")
    }
}
