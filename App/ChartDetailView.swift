import SwiftUI
import GlasshouseCore

/// One signal's chart on its own screen, reachable from its recording settings.
struct ChartDetailView: View {
    let logging: LoggingCoordinator
    let featured: ChartableSignals.Featured

    @State private var window: ChartWindow

    init(logging: LoggingCoordinator, featured: ChartableSignals.Featured, initialWindow: ChartWindow = .month) {
        self.logging = logging
        self.featured = featured
        _window = State(initialValue: initialWindow)
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $window) {
                    ForEach(ChartWindow.allCases) { Text($0.label).tag($0) }
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
            since: window.start(from: Date().timeIntervalSince1970)
        )
    }

    private func format(_ value: Double) -> String {
        FieldValue.join(FieldValue.rounded(value), featured.unit)
    }
}
