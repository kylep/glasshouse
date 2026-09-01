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
                Tab("This phone", systemImage: "iphone.gen3") {
                    RootView(store: store)
                }
                Tab("Other apps", systemImage: "square.stack.3d.up") {
                    AttributionView()
                }
                Tab("Record", systemImage: "record.circle") {
                    RecordingView(store: store)
                }
            }
        }
    }
}
