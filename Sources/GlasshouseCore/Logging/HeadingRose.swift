import Foundation

/// Bins compass headings into sectors, for a polar histogram.
///
/// Kept in Core and unit-tested because circular arithmetic is quietly easy to
/// get wrong: the wrap at 360° puts values either side of north into the same
/// sector, and a naive `Int(degrees / width)` puts 359.9° in a bucket of its
/// own that should not exist.
public enum HeadingRose {
    public struct Sector: Sendable, Hashable, Identifiable {
        public var id: Int { index }

        public let index: Int
        /// Centre of the sector, in degrees clockwise from north.
        public let centre: Double
        public let count: Int
        /// Share of all readings, 0...1.
        public let share: Double
        /// "N", "NE", and so on, when the sector count is 8 or 16.
        public let label: String
    }

    /// Sorts headings into `sectors` equal bins around the compass.
    ///
    /// Sixteen is the default: eight is too coarse to show a street, and
    /// thirty-two is noise at the sample rates this app collects.
    public static func bin(_ headings: [Double], sectors: Int = 16) -> [Sector] {
        precondition(sectors > 0, "a rose needs at least one sector")

        let width = 360.0 / Double(sectors)
        var counts = Array(repeating: 0, count: sectors)

        for heading in headings where heading.isFinite {
            // Normalise first: readings arrive as 0..<360, but a negative or
            // over-wound value should still land somewhere sensible rather than
            // crashing or being dropped.
            let normalised = heading.truncatingRemainder(dividingBy: 360)
            let positive = normalised < 0 ? normalised + 360 : normalised

            // Offset by half a sector so that due north sits in the MIDDLE of
            // the first bin rather than on its edge — otherwise headings of 359°
            // and 1°, two degrees apart, fall in opposite bins.
            let shifted = (positive + width / 2).truncatingRemainder(dividingBy: 360)
            let index = min(sectors - 1, Int(shifted / width))
            counts[index] += 1
        }

        let total = counts.reduce(0, +)
        return counts.enumerated().map { index, count in
            Sector(
                index: index,
                centre: Double(index) * width,
                count: count,
                share: total > 0 ? Double(count) / Double(total) : 0,
                label: compassLabel(index: index, sectors: sectors)
            )
        }
    }

    static func compassLabel(index: Int, sectors: Int) -> String {
        let sixteen = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                       "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        switch sectors {
        case 16: return sixteen[index]
        case 8: return sixteen[index * 2]
        case 4: return ["N", "E", "S", "W"][index]
        default: return ""
        }
    }
}
