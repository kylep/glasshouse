import SwiftUI
import GlasshouseCore
import GlasshouseSensors

/// A stub, deliberately labelled as one.
///
/// It shows what the app can tell you about itself — the build, the signing
/// tier, and how much of the ledger is actually implemented — rather than
/// pretending to be a settings screen with nothing in it. An empty page with a
/// title is worse than a page that says what it will become.
struct SettingsView: View {
    let logging: LoggingCoordinator
    let store: SensorStore

    private let environment = RuntimeEnvironment.current

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        RecordingSettingsView(logging: logging, store: store)
                    } label: {
                        Label("Recording", systemImage: "record.circle")
                    }
                    NavigationLink {
                        AttributionView()
                    } label: {
                        Label("Other apps", systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink {
                        RecordingView(store: store)
                    } label: {
                        Label("Snapshots", systemImage: "camera.aperture")
                    }
                } footer: {
                    Text("Recording keeps a history of individual signals. Snapshots capture every sensor at once, for replaying later.")
                }

                Section("This build") {
                    LabeledContent("Version", value: Self.version)
                    LabeledContent("Running on", value: environment.rawValue)
                    LabeledContent("Signing tier", value: "free personal team")
                    LabeledContent("Entitlements enforced",
                                   value: environment.enforcesEntitlements ? "yes" : "no")
                }

                Section {
                    LabeledContent("Catalogued", value: "\(CapabilityLedger.all.count)")
                    LabeledContent("Reachable on this tier",
                                   value: "\(CapabilityLedger.reachable(with: .free).count)")
                    LabeledContent("With an adapter",
                                   value: "\(ImplementedCapabilities.ids.count)")
                    LabeledContent("iOS never asks about",
                                   value: "\(CapabilityLedger.neverAsked.count)")
                } header: {
                    Text("Sensors")
                } footer: {
                    Text("Every one records its exact permission key, entitlement, signing tier, measured Simulator behaviour, and a source with a verification date.")
                }

                Section {
                    Text("Nothing collected here leaves this device. There is no network stack in this build, and a test fails the build if one appears.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Where your data goes")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private static var version: String {
        let bundle = Bundle.main
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
