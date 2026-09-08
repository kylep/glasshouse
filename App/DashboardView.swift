import SwiftUI
import GlasshouseCore

/// Charts of what has been recorded.
///
/// Empty until something is logging, and says so with the way to start rather
/// than an apologetic blank screen.
struct DashboardView: View {
    let logging: LoggingCoordinator
    @Binding var selectedTab: Int

    /// A day by default: long enough to hold a night of readings, short enough
    /// that a sparkline still shows today's movement.
    @State private var window: ChartWindow = .day

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
                    // First row rather than a pinned inset: `safeAreaInset` on
                    // a List displaces the large title instead of sitting below
                    // it, which left an empty band where "Dashboard" should be.
                    Section {
                        Picker("Range", selection: $window) {
                            ForEach(ChartWindow.dashboardChoices) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 0, leading: 16, bottom: 4, trailing: 16))

                    Section {
                        ForEach(logging.chartsWithData, id: \.sensor) { featured in
                            NavigationLink {
                                ChartDetailView(
                                    logging: logging,
                                    featured: featured,
                                    // Opening a chart keeps the range the row
                                    // was drawn at. Resetting it would show a
                                    // different shape than the one tapped.
                                    initialWindow: window
                                )
                            } label: {
                                SparklineRow(
                                    featured: featured,
                                    points: logging.series(
                                        for: featured.sensor,
                                        field: featured.field,
                                        since: window.start(from: Date().timeIntervalSince1970)
                                    )
                                )
                            }
                        }
                    } footer: {
                        Text("Tap a signal for its full chart and longer ranges.")
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
