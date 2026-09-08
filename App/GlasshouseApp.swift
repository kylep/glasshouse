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

    /// The Collect tab's value. Nothing ever navigates here.
    private let collectTab = 3

    /// Selecting Collect runs a collection instead of changing screen.
    ///
    /// A tab item cannot be a Button — `Tab` takes a label, not an action — so
    /// the press is caught in the binding's setter and the write is dropped.
    /// Refusing the write is what keeps the current screen on screen; there is
    /// no flicker to undo because the selection never changes.
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selection },
            set: { tapped in
                guard tapped == collectTab else {
                    selection = tapped
                    return
                }
                Task { await logging.collectNow() }
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: tabSelection) {
                Tab("Dashboard", systemImage: "chart.xyaxis.line", value: 0) {
                    DashboardView(logging: logging, selectedTab: $selection)
                }
                Tab("Signals", systemImage: "waveform", value: 1) {
                    RootView(store: store, logging: logging)
                }
                Tab("Settings", systemImage: "gearshape", value: 4) {
                    SettingsView(logging: logging, store: store)
                }
                // A tab that is a button. Its content is never displayed,
                // because `tabSelection` refuses to select it — see above.
                Tab(value: collectTab) {
                    EmptyView()
                } label: {
                    CollectTabLabel(
                        state: logging.collection,
                        isEnabled: logging.policies.isAnythingEnabled
                    )
                }
            }
            .animation(.easeInOut(duration: 0.45), value: logging.collection)
            // `safeAreaInset` on a TabView draws into the tab bar's own space
            // rather than above it, so the button's label ran straight through
            // the Dashboard and Settings icons. iOS 26 has an API built for
            // exactly this — the slot the Music mini-player sits in — which
            // reserves its own row. The inset is kept only for iOS 18, where
            // that API does not exist and the tab bar is a plain opaque strip
            // it does not collide with.

            .task {
                // Land on the Dashboard when there is something to see there.
                if logging.hasAnyData { selection = 0 }
            }
        }
    }
}
