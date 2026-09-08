import SwiftUI
import Charts
import GlasshouseCore

/// One recorded signal, drawn.
///
/// Swift Charts is an Apple framework, so this adds no dependency.
struct SignalChartView: View {
    let featured: ChartableSignals.Featured
    let points: [(at: Double, value: Double)]

    /// How many seconds back the axis should cover, independent of the data.
    ///
    /// Without this the axis spans only the readings themselves, so every range
    /// button drew an identical chart whenever all the data fell inside the
    /// shortest one — "24h" and "30d" looked the same and the picker appeared
    /// broken. Passing the window makes the empty part of a range visible,
    /// which is itself information: it shows when nothing was recorded.
    var spanning: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(CapabilityLedger[featured.sensor]?.displayName ?? featured.sensor.rawValue)
                    .font(.headline)
                Spacer()
                if let latest = points.last?.value, featured.kind == .line {
                    // The current value belongs on the card: a chart answers
                    // "what has it been doing", not "what is it now".
                    Text(format(latest))
                        .font(.callout)
                        .monospacedDigit()
                } else {
                    Text("\(points.count) readings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            switch featured.kind {
            case .line: lineChart
            case .rose: roseChart
            }

            Text(featured.reading)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func format(_ value: Double) -> String {
        FieldValue.join(FieldValue.rounded(value), featured.unit)
    }

    private var lineChart: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", Date(timeIntervalSince1970: point.at)),
                    y: .value(featured.field, point.value)
                )
                .interpolationMethod(.monotone)

                // Readings arrive in bursts, so stretches of the line are
                // interpolation across hours of silence. The dots mark where a
                // reading actually happened, which the line alone cannot say.
                PointMark(
                    x: .value("Time", Date(timeIntervalSince1970: point.at)),
                    y: .value(featured.field, point.value)
                )
                .symbolSize(18)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYAxisLabel(featured.unit ?? "")
        // Explicit, not `.automatic(includesZero: false)`: automatic inverts
        // the axis for a flat series, and it is never zero-based because for
        // pressure or altitude a fixed zero flattens the signal into a straight
        // line when the variation is the whole point.
        .chartYScale(domain: ChartDomain.y(for: points.map(\.value)))
        .frame(height: 160)
    }

    /// The window if one was given, otherwise whatever the readings cover.
    private var xDomain: ClosedRange<Date> {
        let now = Date()
        guard let spanning else {
            let times = points.map { Date(timeIntervalSince1970: $0.at) }
            guard let first = times.min(), let last = times.max(), first < last else {
                return now.addingTimeInterval(-3600)...now
            }
            return first...last
        }
        return now.addingTimeInterval(-spanning)...now
    }

    /// A polar histogram of compass headings.
    ///
    /// Drawn rather than charted because Swift Charts has no polar coordinate
    /// system: each sector is a wedge from the centre, its length proportional
    /// to how often the phone pointed that way.
    private var roseChart: some View {
        let sectors = HeadingRose.bin(points.map(\.value))
        let busiest = sectors.map(\.share).max() ?? 1

        return Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 18

            // Rings at 25% intervals, so a spike can be read as a proportion
            // rather than just "bigger than the others".
            for fraction in [0.25, 0.5, 0.75, 1.0] {
                let r = radius * fraction
                context.stroke(
                    Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)),
                    with: .color(.secondary.opacity(0.15)), lineWidth: 0.5
                )
            }

            let width = 360.0 / Double(sectors.count)
            for sector in sectors where sector.share > 0 {
                let length = radius * (sector.share / max(busiest, 0.0001))
                // Rotate so 0° is up: screen angles start at 3 o'clock and run
                // clockwise, compass bearings start at 12 and do the same.
                let start = Angle(degrees: sector.centre - width / 2 - 90)
                let end = Angle(degrees: sector.centre + width / 2 - 90)

                var wedge = Path()
                wedge.move(to: centre)
                wedge.addArc(center: centre, radius: length,
                             startAngle: start, endAngle: end, clockwise: false)
                wedge.closeSubpath()
                context.fill(wedge, with: .color(.accentColor.opacity(0.75)))
            }

            for (label, degrees) in [("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)] {
                let radians = (degrees - 90) * .pi / 180
                let point = CGPoint(
                    x: centre.x + cos(radians) * (radius + 10),
                    y: centre.y + sin(radians) * (radius + 10)
                )
                context.draw(Text(label).font(.caption2).foregroundStyle(.secondary), at: point)
            }
        }
        .frame(height: 200)
    }
}
