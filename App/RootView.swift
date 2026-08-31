import SwiftUI
import GlasshouseCore
import GlasshouseSensors

/// Phase 0 shell. Deliberately minimal: it exists to prove the generated
/// project builds, links both library targets, and runs. The sensor list
/// replaces it in Phase 5.
struct RootView: View {
    private let environment = RuntimeEnvironment.current

    var body: some View {
        NavigationStack {
            List {
                Section("Runtime") {
                    LabeledContent("Environment", value: environment.rawValue)
                    LabeledContent("Live sensors", value: yesNo(environment.supportsLiveSensors))
                    LabeledContent("Entitlements enforced", value: yesNo(environment.enforcesEntitlements))
                    LabeledContent("Live adapters", value: yesNo(GlasshouseSensors.canInstallLiveAdapters))
                }

                Section {
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("What this means")
                }
            }
            .navigationTitle("Glasshouse")
        }
    }

    private var explanation: String {
        switch environment {
        case .device:
            "Running on real hardware. Sensors report actual readings, and the "
            + "system enforces the entitlements this build was signed with."
        case .simulator:
            "Running in the Simulator. Most sensors report no data at all, and "
            + "nothing enforces entitlements — a build can appear to work here "
            + "while using capabilities it could never be signed for."
        case .host:
            "Running on macOS. This is the unit-test environment; no sensor "
            + "adapters are installed."
        }
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}

#Preview {
    RootView()
}
