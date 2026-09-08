import Foundation

/// Decides what should be read, and when.
///
/// Pure logic, deliberately: the timer, the clock and the database all live in
/// the app layer, so the scheduling rules are testable on macOS without any of
/// them. Getting "is it time to read the barometer again" wrong is the kind of
/// bug that only shows up hours later on a device.
public struct LoggingPlan: Sendable {
    public let policies: LoggingPolicies

    public init(policies: LoggingPolicies) {
        self.policies = policies
    }

    /// Signals due for a reading at `now`, given when each was last read.
    ///
    /// A signal with no recorded last-read is due immediately: switching on
    /// logging should produce a first point straight away rather than after a
    /// silent interval, which reads as broken.
    public func due(at now: Double, lastRead: [SensorID: Double]) -> [SensorID] {
        policies.polling.compactMap { entry in
            guard let previous = lastRead[entry.id] else { return entry.id }
            return now - previous >= Double(entry.seconds) ? entry.id : nil
        }
        .sorted()
    }

    /// How long until the next signal is due, or nil if nothing is polling.
    ///
    /// Used to pick a timer interval instead of waking every second. Never
    /// returns less than one second, so a misconfigured interval cannot spin.
    public func secondsUntilNextDue(at now: Double, lastRead: [SensorID: Double]) -> Double? {
        let waits: [Double] = policies.polling.map { entry in
            guard let previous = lastRead[entry.id] else { return 0 }
            return max(0, Double(entry.seconds) - (now - previous))
        }
        guard let soonest = waits.min() else { return nil }
        return max(1, soonest)
    }

    /// Retention work outstanding, as (signal, its retention).
    ///
    /// Every enabled signal is included regardless of capture mode: an
    /// on-demand signal still accumulates readings, and its retention should
    /// still be honoured.
    public var retentionWork: [(id: SensorID, retention: Retention)] {
        policies.enabled
            .map { ($0, policies[$0].retention) }
            .filter { $0.1.seconds != nil }
    }
}
