import Foundation

/// Time-interval arithmetic for category samples (sleep, mindful sessions), kept free of HealthKit so it can be tested.
enum IntervalMath {
    /// Overlapping or touching intervals merged, sorted by start. Removes double counting when several sources (iPhone,
    /// Watch, a sleep app) record the same time.
    static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// Total time of `intervals` inside `window`, without double counting.
    static func covered(_ intervals: [DateInterval], within window: DateInterval) -> TimeInterval {
        merged(intervals).reduce(0) { total, interval in
            total + (interval.intersection(with: window)?.duration ?? 0)
        }
    }

    /// Merged intervals grouped into sessions: a gap longer than `maxGap` starts a new session.
    static func sessions(_ intervals: [DateInterval], maxGap: TimeInterval) -> [[DateInterval]] {
        var result: [[DateInterval]] = []
        for interval in merged(intervals) {
            if let lastEnd = result.last?.last?.end, interval.start.timeIntervalSince(lastEnd) <= maxGap {
                result[result.count - 1].append(interval)
            } else {
                result.append([interval])
            }
        }
        return result
    }

    /// Sleep for a period: whole nights count on the day you wake up. Asleep intervals are grouped into nights (gaps up
    /// to `maxGap` awake still belong to the same night); a night counts when it ends inside `window`. Awake gaps are
    /// not counted.
    static func asleep(_ intervals: [DateInterval], attributedTo window: DateInterval,
                       maxGap: TimeInterval = 2 * 3600) -> TimeInterval {
        sessions(intervals, maxGap: maxGap)
            .filter { night in
                guard let end = night.last?.end else { return false }
                return end > window.start && end <= window.end
            }
            .reduce(0) { total, night in total + night.reduce(0) { $0 + $1.duration } }
    }
}
