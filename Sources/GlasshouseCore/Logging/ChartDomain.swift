import Foundation

/// Y-axis bounds for a line chart.
///
/// Exists because `.automatic(includesZero: false)` renders a flat series with
/// the axis upside down — a constant 60% volume drew "60" at the top of the
/// chart and "61" at the bottom. Swift Charts is given a zero-width domain and
/// has to invent one, and what it invents is backwards.
public enum ChartDomain {
    /// Padded bounds that are always low-to-high, never empty.
    public static func y(for values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }

        if low == high {
            // Proportional padding, with a floor so a constant zero still gets
            // a visible band rather than collapsing again.
            let padding = Swift.max(Swift.abs(low) * 0.05, 0.5)
            return clampBelowZero(low - padding, high + padding, observed: low)
        }

        // A margin so the line does not sit against the frame edge, which is
        // what `.automatic` was giving and is worth keeping.
        let margin = (high - low) * 0.1
        return clampBelowZero(low - margin, high + margin, observed: low)
    }

    /// Keeps padding from inventing negative values a signal cannot have.
    ///
    /// Counts are the common case: an empty clipboard drew an axis running down
    /// to -0.4 items. If the data itself never went below zero, neither should
    /// the axis — but a signal that genuinely does go negative, like a UTC
    /// offset or acceleration, keeps its room.
    private static func clampBelowZero(
        _ lower: Double, _ upper: Double, observed: Double
    ) -> ClosedRange<Double> {
        guard observed >= 0, lower < 0 else { return lower...upper }
        return 0...upper
    }
}
