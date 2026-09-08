import SwiftUI
import GlasshouseCore

/// Charts of what has been recorded.
///
/// Empty until something is logging, and says so with the way to start rather
/// than an apologetic blank screen.
struct DashboardView: View {
    let logging: LoggingCoordinator
    @Binding var selectedTab: Int

    var body: some View {
        NavigationStack {
            List {
                if logging.chartsWithData.isEmpty {
                    emptyState
                } else {
                    ForEach(logging.chartsWithData, id: \.sensor) { featured in
                        Section {
                            SignalChartView(
                                featured: featured,
                                points: logging.series(for: featured.sensor, field: featured.field)
                            )
                        }
                    }
                }
            }
            .navigationTitle("Dashboard")
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nothing is being recorded yet.")
                    .font(.headline)

                Text("""
                    Logging is off for every signal. Turn one on in Settings › \
                    Recording and its history will appear here — a chart needs \
                    at least two readings before it has a shape.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Open recording settings") { selectedTab = 4 }
                    .font(.callout)
            }
            .padding(.vertical, 4)
        }
    }
}
