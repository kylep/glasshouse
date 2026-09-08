import SwiftUI
import GlasshouseCore

/// One signal's chart on its own screen, reachable from its recording settings.
struct ChartDetailView: View {
    let logging: LoggingCoordinator
    let featured: ChartableSignals.Featured

    @State private var window: Window = .all

    /// How far back to plot. Ranges rather than a scrubber, because at these
    /// sample rates a scrubber would mostly be showing empty axis.
    enum Window: String, CaseIterable, Identifiable {
        case hour = "1h"
        case day = "24h"
        case week = "7d"
        case all = "30d"

        var id: String { rawValue }

        var seconds: Double? {
            switch self {
            case .hour: 3600
            case .day: 86_400
            case .week: 604_800
            // Capped rather than unbounded: beyond a month the axis
            // compresses recent detail into nothing.
            case .all: 2_592_000
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $window) {
                    ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if points.count < 2 {
                    Text("Not enough readings in this range yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    SignalChartView(featured: featured, points: points, spanning: window.seconds)
                }
            }

            if points.count >= 2, featured.kind == .line {
                Section("Range") {
                    LabeledContent("Lowest", value: format(points.map(\.value).min() ?? 0))
                    LabeledContent("Highest", value: format(points.map(\.value).max() ?? 0))
                    LabeledContent("Latest", value: format(points.last?.value ?? 0))
                }
            }
        }
        .navigationTitle(CapabilityLedger[featured.sensor]?.displayName ?? "Chart")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var points: [(at: Double, value: Double)] {
        logging.series(
            for: featured.sensor,
            field: featured.field,
            since: window.seconds.map { Date().timeIntervalSince1970 - $0 }
        )
    }

    private func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return featured.unit.map { "\(rounded) \($0)" } ?? "\(rounded)"
    }
}
