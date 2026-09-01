import SwiftUI

@main
struct GlasshouseApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("This phone", systemImage: "iphone.gen3") {
                    RootView()
                }
                Tab("Other apps", systemImage: "square.stack.3d.up") {
                    AttributionView()
                }
                Tab("Record", systemImage: "record.circle") {
                    RecordingView()
                }
            }
        }
    }
}
