import SwiftUI
import Charts
import GlasshouseCore

/// One recorded signal, drawn.
///
/// Swift Charts is an Apple framework, so this adds no dependency.
struct SignalChartView: View {
    let featured: ChartableSignals.Featured
    let points: [(at: Double, value: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(CapabilityLedger[featured.sensor]?.displayName ?? featured.sensor.rawValue)
                    .font(.headline)
                Spacer()
                Text("\(points.count) readings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    private var lineChart: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", Date(timeIntervalSince1970: point.at)),
                    y: .value(featured.field, point.value)
                )
                .interpolationMethod(.monotone)
            }
        }
        .chartYAxisLabel(featured.unit ?? "")
        // Not zero-based: for pressure or altitude a fixed zero flattens the
        // signal into a straight line, and the variation is the whole point.
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 160)
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
