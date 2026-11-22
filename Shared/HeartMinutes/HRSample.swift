import Foundation

// Ported from Heart Minutes (github.com/usernamefourzerofour/HeartMinutes): the heart rate measurements its Heart Minutes
// are calculated from. HealthKit-free so it can be tested; the HealthKit reading is in Everyring/HealthManager.swift.

/// Apple's own judgement of whether you were moving when the heart rate was measured
/// (HKMetadataKeyHeartRateMotionContext on Apple Watch measurements).
enum MotionContext: Equatable, Sendable {
    case unknown, sedentary, active

    var name: String {
        switch self {
        case .unknown: String(localized: "Unknown")
        case .sedentary: String(localized: "Resting")
        case .active: String(localized: "Active")
        }
    }
}

/// Minutes in one heart rate zone with the zone's colour (for a zone bar).
struct ZoneSlice: Codable, Equatable, Sendable {
    var name: String
    var minutes: Double
    var r: Double
    var g: Double
    var b: Double
}

struct HRSample: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let bpm: Double
    /// Measured during a workout (otherwise a background measurement).
    var inWorkout = false
    /// Whether Apple judged you active or resting.
    var motion: MotionContext = .unknown
    /// Start of the workout the measurement belongs to (so two measurements can be recognised as the same workout).
    var workoutStart: Date? = nil
    /// The source in Health (e.g. "my Apple Watch" or another app/device).
    var source: String? = nil
    /// Measured in a minute that counts in the Exercise ring (the green ring).
    var inExercise = false
    /// Lies in a short gap between two active measurements and therefore counts as active ("Fill short gaps").
    var bridgedActive = false

    /// The same measurement at another time (used to stretch a workout's measurements).
    func copy(at date: Date) -> HRSample {
        var s = HRSample(date: date, bpm: bpm, inWorkout: inWorkout, motion: motion)
        s.workoutStart = workoutStart
        s.source = source
        s.inExercise = inExercise
        s.bridgedActive = bridgedActive
        return s
    }

    /// Background measurements without an active/resting marking (it only comes from Apple Watch).
    struct UnmarkedInfo: Equatable {
        let count: Int
        let backgroundCount: Int
        /// The sources, most measurements first.
        let sources: [String]
        var fraction: Double { backgroundCount == 0 ? 0 : Double(count) / Double(backgroundCount) }
    }

    static func unmarkedBackground(_ samples: [HRSample]) -> UnmarkedInfo {
        var background = 0, unmarked = 0
        var perSource: [String: Int] = [:]
        for s in samples where !s.inWorkout {
            background += 1
            if s.motion == .unknown {
                unmarked += 1
                perSource[s.source ?? String(localized: "Unknown source"), default: 0] += 1
            }
        }
        let sources = perSource.sorted { $0.value > $1.value }.map(\.key)
        return UnmarkedInfo(count: unmarked, backgroundCount: background, sources: sources)
    }

    /// Marks the measurements that fall within one of the workout periods.
    static func markingWorkouts(_ samples: [HRSample], _ workouts: [DateInterval]) -> [HRSample] {
        guard !workouts.isEmpty else { return samples }
        // Both are sorted by time: walk through once instead of checking every workout for each measurement.
        let sorted = workouts.sorted { $0.start < $1.start }
        var w = 0
        return samples.map { s in
            var s = s
            while w < sorted.count && sorted[w].end < s.date { w += 1 }
            var i = w
            while i < sorted.count && sorted[i].start <= s.date {
                if sorted[i].contains(s.date) { s.inWorkout = true; s.workoutStart = sorted[i].start; break }
                i += 1
            }
            return s
        }
    }

    /// Marks measurements that lie in a minute that counts in the Exercise ring (the green ring).
    static func markingExercise(_ samples: [HRSample], _ minutes: [DateInterval]) -> [HRSample] {
        guard !minutes.isEmpty else { return samples }
        let sorted = minutes.sorted { $0.start < $1.start }
        var i = 0
        return samples.map { s in
            var s = s
            // Half-open minutes [start, end), so a measurement exactly on a minute boundary belongs to only one.
            while i < sorted.count && sorted[i].end <= s.date { i += 1 }
            if i < sorted.count && sorted[i].start <= s.date { s.inExercise = true }
            return s
        }
    }

    /// A pause where the line breaks (e.g. between two workouts when background is off).
    static let lineBreakGap: TimeInterval = 3600

    /// Series number per continuous stretch of the same type, so the line changes colour without connecting background
    /// and workout – and breaks at gaps over an hour.
    static func segments(_ samples: [HRSample]) -> [Int] {
        var segment = 0
        return samples.indices.map { i in
            if i > 0 && (samples[i].inWorkout != samples[i - 1].inWorkout
                         || samples[i].date.timeIntervalSince(samples[i - 1].date) > lineBreakGap) {
                segment += 1
            }
            return segment
        }
    }

    /// Filters by the settings for background and workout measurements.
    static func filtered(_ samples: [HRSample], background: Bool, workouts: Bool) -> [HRSample] {
        if background && workouts { return samples }
        return samples.filter { $0.inWorkout ? workouts : background }
    }
}

extension RandomAccessCollection where Element == HRSample {
    /// Average sampling rate in Hz: number of intervals / time span (requires sorted measurements).
    var samplingRateHz: Double? {
        guard count >= 2, let first = self.first, let last = self.last, last.date > first.date else { return nil }
        return Double(count - 1) / last.date.timeIntervalSince(first.date)
    }
}

extension Array where Element == HRSample {
    /// First index with date ≥ `date` (binary search; the measurements are sorted).
    func firstIndex(atOrAfter date: Date) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if self[mid].date < date { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// The measurements in [from, to] without walking the whole array.
    func slice(from: Date, to: Date) -> ArraySlice<HRSample> {
        let a = firstIndex(atOrAfter: from)
        var b = firstIndex(atOrAfter: to)
        while b < count && self[b].date == to { b += 1 }
        return self[a..<Swift.max(a, b)]
    }
}

