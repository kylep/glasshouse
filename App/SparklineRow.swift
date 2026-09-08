import SwiftUI
import Charts
import GlasshouseCore

/// One signal as a single row: name, current value, and a compact trend.
///
/// The Dashboard is a summary that points at detail, not a stack of half-sized
/// charts competing for attention. Eight of these fit on a screen where two
/// full cards did, and nothing is lost — the full chart is one tap away.
struct SparklineRow: View {
    let featured: ChartableSignals.Featured
    let points: [(at: Double, value: Double)]

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CapabilityLedger[featured.sensor]?.displayName ?? featured.sensor.rawValue)
                    .font(.subheadline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trend
                .frame(width: 88, height: 30)

            Text(latest)
                .font(.callout)
                .monospacedDigit()
                .frame(minWidth: 62, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    /// Range for a line, or the dominant direction for a rose — the one number
    /// worth having when the chart itself is 88 points wide.
    private var subtitle: String {
        guard !points.isEmpty else { return "no readings" }

        if featured.kind == .rose {
            let sectors = HeadingRose.bin(points.map(\.value))
            let busiest = sectors.max { $0.count < $1.count }
            return "mostly \(busiest?.label ?? "—") · \(points.count) readings"
        }

        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return "" }
        return "\(short(low))–\(short(high)) · \(points.count) readings"
    }

    private var latest: String {
        guard let value = points.last?.value else { return "—" }
        if featured.kind == .rose {
            let sectors = HeadingRose.bin([value])
            return sectors.first { $0.count > 0 }?.label ?? "—"
        }
        return featured.unit.map { "\(short(value)) \($0)" } ?? short(value)
    }

    @ViewBuilder
    private var trend: some View {
        if points.count < 2 {
            // A single point has no trend, and drawing a dot in an empty frame
            // reads as a rendering failure rather than as "not enough data".
            Text("—")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else if featured.kind == .rose {
            MiniRose(sectors: HeadingRose.bin(points.map(\.value), sectors: 8))
        } else {
            // Readings are spaced evenly by position, NOT by timestamp.
            //
            // Real sampling is bursty — a handful of taps close together, then
            // hours of nothing. On a time axis at this size that collapses into
            // two vertical smears joined by a flat line, which looks broken and
            // shows no trend at all. Even spacing makes the glyph mean "your
            // last few readings, in order", which is what a sparkline is for.
            // The honest time axis lives in the detail chart, where there is
            // room to label it.
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    LineMark(
                        x: .value("reading", index),
                        y: .value("v", point.value)
                    )
                    .interpolationMethod(.monotone)
                }
            }
            // No axes at this size: gridlines and labels would be illegible and
            // the shape is the entire message.
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
        }
    }

    private func short(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude >= 1000 { return String(format: "%.0f", value) }
        if magnitude >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }
}

/// A compass rose small enough to sit in a table row.
private struct MiniRose: View {
    let sectors: [HeadingRose.Sector]

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let busiest = sectors.map(\.share).max() ?? 1
            let width = 360.0 / Double(sectors.count)

            for sector in sectors where sector.share > 0 {
                let length = radius * (sector.share / max(busiest, 0.0001))
                var wedge = Path()
                wedge.move(to: centre)
                wedge.addArc(
                    center: centre, radius: length,
                    startAngle: .degrees(sector.centre - width / 2 - 90),
                    endAngle: .degrees(sector.centre + width / 2 - 90),
                    clockwise: false
                )
                wedge.closeSubpath()
                context.fill(wedge, with: .color(.accentColor.opacity(0.8)))
            }
        }
    }
}
