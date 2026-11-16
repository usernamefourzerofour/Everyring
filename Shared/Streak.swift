import Foundation

/// Current and best streak for a ring.
///
/// Fixed periods: consecutive periods in which the ring was closed. Rolling periods: consecutive days on which the
/// window ending that day reached the goal. The period (or day) in progress never breaks a streak; it adds to it as
/// soon as the goal is reached.
struct Streak: Codable, Hashable, Sendable {
    var current: Int
    var best: Int

    static let zero = Streak(current: 0, best: 0)

    /// - Parameters:
    ///   - finished: whether each finished period was closed, **newest first**.
    ///   - inProgress: whether the period in progress is already closed.
    init(finished: [Bool], inProgress: Bool) {
        let trailing = finished.prefix { $0 }.count
        current = trailing + (inProgress ? 1 : 0)

        var best = 0, run = 0
        for closed in finished.reversed() {
            run = closed ? run + 1 : 0
            best = max(best, run)
        }
        if inProgress { best = max(best, run + 1) }
        self.best = max(best, current)
    }

    init(current: Int, best: Int) {
        self.current = current
        self.best = best
    }

    /// A ring counts as closed when it reaches the goal. A goal of zero or less never closes.
    static func isClosed(value: Double, goal: Double) -> Bool {
        goal > 0 && value >= goal
    }

    /// Computes the streak from a value per period.
    ///
    /// - Parameters:
    ///   - lookback: how many finished periods to look at. The best streak is the best within this range.
    ///   - value: the ring's value for an interval (sum of the Health metric).
    static func compute(period: RingPeriod, goal: Double, now: Date = .now, calendar: Calendar = .current,
                        lookback: Int, value: (DateInterval) -> Double) -> Streak {
        let current = period.interval(now: now, calendar: calendar)
        let finished = period.history(now: now, count: lookback, calendar: calendar)
            .map { isClosed(value: value($0), goal: goal) }
        return Streak(finished: finished, inProgress: isClosed(value: value(current), goal: goal))
    }

    /// Streak for a ring, taking its goal kind into account.
    init(ring: Ring, finished: [Double], inProgress: Double) {
        self.init(finished: finished.map(ring.isMet), inProgress: ring.isMetInProgress(inProgress))
    }
}
