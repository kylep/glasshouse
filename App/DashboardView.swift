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
                    if logging.awaitingFirstPoints.isEmpty {
                        emptyState
                    } else {
                        waitingState
                    }
                } else {
                    ForEach(logging.chartsWithData, id: \.sensor) { featured in
                        Section {
                            // The card is a summary; the range controls live on
                            // the detail screen. Putting pickers on every card
                            // would have controls competing with content in a
                            // scrolling list.
                            NavigationLink {
                                ChartDetailView(logging: logging, featured: featured)
                            } label: {
                                SignalChartView(
                                    featured: featured,
                                    points: logging.series(
                                        for: featured.sensor,
                                        field: featured.field,
                                        // Last 24h on the card. Plotting all of
                                        // history in a thumbnail compresses
                                        // recent movement into a flat line.
                                        since: Date().timeIntervalSince1970 - 86_400
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Dashboard")
        }
    }

    /// Recording is on but there is not yet enough to draw.
    ///
    /// Distinguishing this from "nothing is switched on" matters: the app
    /// previously reported the latter in both cases, which read as the toggle
    /// having failed.
    private var waitingState: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recording. Waiting for a second reading.")
                    .font(.headline)
                Text("A chart needs two points before it has a shape.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(logging.awaitingFirstPoints, id: \.featured.sensor) { entry in
                    HStack {
                        Text(CapabilityLedger[entry.featured.sensor]?.displayName
                             ?? entry.featured.sensor.rawValue)
                        Spacer()
                        Text(entry.count == 0 ? "no readings yet" : "1 reading")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding(.vertical, 4)
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
