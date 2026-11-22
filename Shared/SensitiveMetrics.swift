import Foundation

/// Health types that are medical, reproductive or otherwise sensitive: symptoms, sexual activity and cycle tracking,
/// insulin, inhaler use, falls and heart, breathing and hearing notifications.
///
/// For testing only for now: the metric list shows them only in builds with the `SENSITIVE_METRICS` compilation
/// condition (set in project.yml). Remove it before an App Store release unless it is decided they may stay: Everyring
/// can't vouch for their precision and must not look like medical advice.
enum SensitiveKind: String, Codable, CaseIterable, Sendable {
    // Symptoms (counted entries; entries marked "not present" don't count)
    case abdominalCramps, acne, appetiteChanges, bladderIncontinence, bloating, breastPain, chestTightnessOrPain
    case chills, constipation, coughing, diarrhea, dizziness, drySkin, fainting, fatigue, fever, generalizedBodyAche
    case hairLoss, headache, heartburn, hotFlashes, lossOfSmell, lossOfTaste, lowerBackPain, memoryLapse, moodChanges
    case nausea, nightSweats, pelvicPain, rapidPoundingOrFlutteringHeartbeat, runnyNose, shortnessOfBreath
    case sinusCongestion, skippedHeartbeat, sleepChanges, soreThroat, vaginalDryness, vomiting, wheezing
    // Reproductive health
    case sexualActivity, menstrualFlow, intermenstrualBleeding, contraceptive, lactation, ovulationTest, pregnancyTest
    // Medical
    case insulinDelivery, inhalerUsage, timesFallen
    case highHeartRateEvent, lowHeartRateEvent, irregularHeartRhythmEvent, lowCardioFitnessEvent, sleepApneaEvent
    case walkingSteadinessEvent, environmentalAudioExposureEvent, headphoneAudioExposureEvent

    static let symptoms: [SensitiveKind] = [
        .abdominalCramps, .acne, .appetiteChanges, .bladderIncontinence, .bloating, .breastPain, .chestTightnessOrPain,
        .chills, .constipation, .coughing, .diarrhea, .dizziness, .drySkin, .fainting, .fatigue, .fever,
        .generalizedBodyAche, .hairLoss, .headache, .heartburn, .hotFlashes, .lossOfSmell, .lossOfTaste, .lowerBackPain,
        .memoryLapse, .moodChanges, .nausea, .nightSweats, .pelvicPain, .rapidPoundingOrFlutteringHeartbeat, .runnyNose,
        .shortnessOfBreath, .sinusCongestion, .skippedHeartbeat, .sleepChanges, .soreThroat, .vaginalDryness, .vomiting,
        .wheezing,
    ]

    var category: HealthMetric.Category {
        switch self {
        case .sexualActivity, .menstrualFlow, .intermenstrualBleeding, .contraceptive, .lactation, .ovulationTest,
             .pregnancyTest: .reproductive
        case .insulinDelivery, .inhalerUsage, .timesFallen, .highHeartRateEvent, .lowHeartRateEvent,
             .irregularHeartRhythmEvent, .lowCardioFitnessEvent, .sleepApneaEvent, .walkingSteadinessEvent,
             .environmentalAudioExposureEvent, .headphoneAudioExposureEvent: .medical
        default: .symptoms
        }
    }

    var isSymptom: Bool { category == .symptoms }

    var baseUnit: HealthMetric.BaseUnit { self == .insulinDelivery ? .internationalUnits : .count }

    var title: String {
        switch self {
        case .abdominalCramps: String(localized: "Abdominal cramps")
        case .acne: String(localized: "Acne")
        case .appetiteChanges: String(localized: "Appetite changes")
        case .bladderIncontinence: String(localized: "Bladder incontinence")
        case .bloating: String(localized: "Bloating")
        case .breastPain: String(localized: "Breast pain")
        case .chestTightnessOrPain: String(localized: "Chest tightness or pain")
        case .chills: String(localized: "Chills")
        case .constipation: String(localized: "Constipation")
        case .coughing: String(localized: "Coughing")
        case .diarrhea: String(localized: "Diarrhea")
        case .dizziness: String(localized: "Dizziness")
        case .drySkin: String(localized: "Dry skin")
        case .fainting: String(localized: "Fainting")
        case .fatigue: String(localized: "Fatigue")
        case .fever: String(localized: "Fever")
        case .generalizedBodyAche: String(localized: "Body and muscle ache")
        case .hairLoss: String(localized: "Hair loss")
        case .headache: String(localized: "Headache")
        case .heartburn: String(localized: "Heartburn")
        case .hotFlashes: String(localized: "Hot flashes")
        case .lossOfSmell: String(localized: "Loss of smell")
        case .lossOfTaste: String(localized: "Loss of taste")
        case .lowerBackPain: String(localized: "Lower back pain")
        case .memoryLapse: String(localized: "Memory lapse")
        case .moodChanges: String(localized: "Mood changes")
        case .nausea: String(localized: "Nausea")
        case .nightSweats: String(localized: "Night sweats")
        case .pelvicPain: String(localized: "Pelvic pain")
        case .rapidPoundingOrFlutteringHeartbeat: String(localized: "Rapid, pounding or fluttering heartbeat")
        case .runnyNose: String(localized: "Runny nose")
        case .shortnessOfBreath: String(localized: "Shortness of breath")
        case .sinusCongestion: String(localized: "Sinus congestion")
        case .skippedHeartbeat: String(localized: "Skipped heartbeat")
        case .sleepChanges: String(localized: "Sleep changes")
        case .soreThroat: String(localized: "Sore throat")
        case .vaginalDryness: String(localized: "Vaginal dryness")
        case .vomiting: String(localized: "Vomiting")
        case .wheezing: String(localized: "Wheezing")
        case .sexualActivity: String(localized: "Sexual activity")
        case .menstrualFlow: String(localized: "Period days")
        case .intermenstrualBleeding: String(localized: "Spotting")
        case .contraceptive: String(localized: "Contraceptives")
        case .lactation: String(localized: "Lactation")
        case .ovulationTest: String(localized: "Ovulation tests")
        case .pregnancyTest: String(localized: "Pregnancy tests")
        case .insulinDelivery: String(localized: "Insulin delivery")
        case .inhalerUsage: String(localized: "Inhaler usage")
        case .timesFallen: String(localized: "Times fallen")
        case .highHeartRateEvent: String(localized: "High heart rate notifications")
        case .lowHeartRateEvent: String(localized: "Low heart rate notifications")
        case .irregularHeartRhythmEvent: String(localized: "Irregular rhythm notifications")
        case .lowCardioFitnessEvent: String(localized: "Low cardio fitness notifications")
        case .sleepApneaEvent: String(localized: "Breathing disturbance notifications")
        case .walkingSteadinessEvent: String(localized: "Walking steadiness notifications")
        case .environmentalAudioExposureEvent: String(localized: "Noise notifications")
        case .headphoneAudioExposureEvent: String(localized: "Headphone notifications")
        }
    }

    var symbol: String {
        switch category {
        case .reproductive:
            switch self {
            case .sexualActivity: "heart"
            case .menstrualFlow, .intermenstrualBleeding: "drop"
            case .contraceptive: "pills"
            case .lactation: "figure.and.child.holdinghands"
            default: "testtube.2"
            }
        case .medical:
            switch self {
            case .insulinDelivery: "syringe"
            case .inhalerUsage: "lungs"
            case .timesFallen: "figure.fall"
            case .sleepApneaEvent: "lungs"
            case .walkingSteadinessEvent: "figure.walk"
            case .environmentalAudioExposureEvent: "ear"
            case .headphoneAudioExposureEvent: "headphones"
            default: "heart.text.square"
            }
        default:
            switch self {
            case .headache: "brain.head.profile"
            case .fever, .chills, .hotFlashes, .nightSweats: "thermometer.medium"
            case .coughing, .runnyNose, .sinusCongestion, .soreThroat, .shortnessOfBreath, .wheezing: "lungs"
            case .rapidPoundingOrFlutteringHeartbeat, .skippedHeartbeat, .chestTightnessOrPain: "heart"
            case .fatigue, .sleepChanges: "zzz"
            case .moodChanges, .memoryLapse: "brain"
            default: "staroflife"
            }
        }
    }

    /// A typical daily amount, scaled by the period length to suggest a goal (symptoms and notifications: a limit).
    var dailyBaseline: Double {
        switch self {
        case .insulinDelivery: 40
        case .inhalerUsage: 2
        case .sexualActivity: 1.0 / 7 * 2
        default: 1.0 / 7
        }
    }

    /// Symptoms, falls and notifications are things to have few of.
    var defaultGoalKind: GoalKind {
        switch self {
        case .insulinDelivery, .inhalerUsage, .contraceptive, .sexualActivity, .lactation, .ovulationTest, .pregnancyTest,
             .menstrualFlow: .reach
        default: .limit
        }
    }

    var defaultPeriod: RingPeriod {
        switch self {
        case .insulinDelivery, .inhalerUsage, .contraceptive: .today
        default: .thisWeek
        }
    }

    var defaultColor: RingColor {
        switch category {
        case .reproductive: .magenta
        case .medical: self == .insulinDelivery ? .lagoon : .tangerine
        default: .violet
        }
    }

    var countNoun: String {
        switch self {
        case .menstrualFlow: String(localized: "days")
        case .inhalerUsage: String(localized: "puffs")
        default: String(localized: "times")
        }
    }
}

extension HealthMetric.Category {
    /// Medical, reproductive and symptom types: only offered in builds with `SENSITIVE_METRICS`.
    var isSensitive: Bool {
        switch self {
        case .symptoms, .reproductive, .medical: true
        default: false
        }
    }

    static var showsSensitive: Bool {
        #if SENSITIVE_METRICS
        true
        #else
        false
        #endif
    }

    /// The categories the metric list offers.
    static var offered: [Self] { allCases.filter { !$0.isSensitive || showsSensitive } }
}
