import SwiftUI
import GlasshouseCore

struct RootView: View {
    @State private var store = SensorStore()

    var body: some View {
        NavigationStack {
            List {
                summary

                section("Reading you right now",
                        note: "No permission was asked for any of these.",
                        store.readingWithoutAsking)

                section("Reading you, with permission", note: nil,
                        store.readingWithPermission)

                permissionSection

                section("Not available here",
                        note: RuntimeEnvironment.current == .simulator
                            ? "The Simulator has no such hardware. These need a real phone."
                            : "This device doesn't have the hardware.",
                        store.unavailableHere)

                section("No app is allowed to read these",
                        note: "The sensor exists. The API doesn't.",
                        store.impossible)

                section("Not built yet", note: nil, store.notBuiltYet)

                if !store.anomalies.isEmpty {
                    section("Unexplained",
                            note: "These claim to work and should work here, but reported nothing. Probably a bug.",
                            store.anomalies)
                }
            }
            .navigationTitle("Glasshouse")
            .refreshable { await store.refresh() }
            .task { if store.snapshots.isEmpty { await store.refresh() } }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var summary: some View {
        Section {
            let silent = store.readingWithoutAsking.count
            let total = store.snapshots.count

            VStack(alignment: .leading, spacing: 8) {
                Text(silent == 0
                     ? "Nothing is reading you yet."
                     : "^[\(silent) thing](inflect: true) about you \(silent == 1 ? "is" : "are") readable right now, without anything asking.")
                    .font(.headline)

                Text("Glasshouse knows of \(total) ways an app can read this phone. Nothing here leaves the device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if RuntimeEnvironment.current == .simulator {
                    Label("Running in the Simulator, where most sensors report nothing.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if !store.awaitingPermission.isEmpty {
            Section {
                ForEach(store.awaitingPermission, id: \.capability.id) { snapshot in
                    NavigationLink {
                        SensorDetailView(sensorID: snapshot.capability.id, store: store)
                    } label: {
                        SensorRow(snapshot: snapshot)
                    }
                }
            } header: {
                Text("Waiting to be asked")
            } footer: {
                Text("Tap one to see what it would reveal, then decide.")
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, note: String?, _ snapshots: [SensorSnapshot]) -> some View {
        if !snapshots.isEmpty {
            Section {
                ForEach(snapshots, id: \.capability.id) { snapshot in
                    NavigationLink {
                        SensorDetailView(sensorID: snapshot.capability.id, store: store)
                    } label: {
                        SensorRow(snapshot: snapshot)
                    }
                }
            } header: {
                Text(title)
            } footer: {
                if let note { Text(note) }
            }
        }
    }
}

struct SensorRow: View {
    let snapshot: SensorSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(snapshot.capability.displayName)
                Spacer()
                if !snapshot.capability.promptsUser {
                    Text("no prompt")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let first = snapshot.sample?.fields.first {
                Text("\(first.label): \(first.value.plainDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(snapshot.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    RootView()
}
