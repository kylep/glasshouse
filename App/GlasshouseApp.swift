import SwiftUI

@main
struct GlasshouseApp: App {
    /// One store across the tabs, so loading a recording in Record visibly
    /// changes what This phone shows. Two independent stores would let the app
    /// display live readings on one screen while claiming to replay on another.
    @State private var store = SensorStore()
    @State private var logging = LoggingCoordinator()

    /// Signals until there is history worth showing. A Dashboard that opens
    /// empty on first launch teaches nothing about what the app does.
    @State private var selection = 1

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selection) {
                Tab("Dashboard", systemImage: "chart.xyaxis.line", value: 0) {
                    DashboardView(logging: logging, selectedTab: $selection)
                }
                Tab("Signals", systemImage: "waveform", value: 1) {
                    RootView(store: store, logging: logging)
                }
                Tab("Settings", systemImage: "gearshape", value: 4) {
                    SettingsView(logging: logging, store: store)
                }
            }
            // Above the tab bar rather than inside it, so it is reachable from
            // every screen without becoming a destination.
            .safeAreaInset(edge: .bottom) {
                CollectNowButton(logging: logging)
            }
            .task {
                // Land on the Dashboard when there is something to see there.
                if logging.hasAnyData { selection = 0 }
            }
        }
    }
}
