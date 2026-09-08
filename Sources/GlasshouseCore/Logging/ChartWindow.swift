import Foundation

/// How far back a chart looks.
///
/// Shared by the Dashboard and the detail chart so the two cannot drift apart —
/// a row that says "24 hours" must mean the same thing as the chart it opens.
public enum ChartWindow: String, CaseIterable, Sendable, Identifiable {
    case hour
    case day
    case week
    case month

    public var id: String { rawValue }

    /// Short enough for a segmented control.
    public var label: String {
        switch self {
        case .hour: "1h"
        case .day: "24h"
        case .week: "7d"
        case .month: "30d"
        }
    }

    public var seconds: Double {
        switch self {
        case .hour: 3_600
        case .day: 86_400
        case .week: 604_800
        // Deliberately capped rather than unbounded. Beyond a month the axis
        // compresses recent movement into nothing, and default retention is a
        // week, so "everything" would rarely mean more than this anyway.
        case .month: 2_592_000
        }
    }

    public func start(from now: Double) -> Double { now - seconds }

    /// The Dashboard's choices. An hour is omitted: at the sampling rates this
    /// app records, an hour usually holds one reading, which is not a chart.
    public static let dashboardChoices: [ChartWindow] = [.day, .week, .month]
}
