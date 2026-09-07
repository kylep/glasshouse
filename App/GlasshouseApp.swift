import SwiftUI

@main
struct GlasshouseApp: App {
    /// One store across the tabs, so loading a recording in Record visibly
    /// changes what This phone shows. Two independent stores would let the app
    /// display live readings on one screen while claiming to replay on another.
    @State private var store = SensorStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Signals", systemImage: "waveform") {
                    RootView(store: store)
                }
                Tab("Report", systemImage: "doc.text.magnifyingglass") {
                    AttributionView()
                }
                Tab("Record", systemImage: "record.circle") {
                    RecordingView(store: store)
                }
                Tab("Settings", systemImage: "gearshape") {
                    SettingsView()
                }
            }
        }
    }
}
