import SwiftUI
import GlasshouseCore

struct RootView: View {
    let store: SensorStore

    var body: some View {
        NavigationStack {
            List {
                replayBanner
                summary

                section("Reading you right now",
                        note: "iOS never asked about any of these. There is no dialog, nothing in Settings, and no way to switch them off.",
                        store.readingWithoutAsking)

                section("Reading you, because you allowed it", note: nil,
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        if store.isRefreshing {
                            ProgressView()
                        } else {
                            Label("Read again", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(store.isRefreshing)
                }
            }
        }
    }

    // MARK: - Pieces

    /// Shown above everything whenever a recording is driving the app.
    ///
    /// Not a nicety. An app whose argument is that people are misled about
    /// their own data cannot present a recording as the present moment.
    @ViewBuilder
    private var replayBanner: some View {
        if let replay = store.replaying {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("These are recorded readings, not live",
                          systemImage: "play.rectangle")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Text("From \(replay.name), captured on \(replay.recordedOn == .device ? "a phone" : "a simulator") · \(replay.sensors) sensors")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let notes = replay.notes {
                        Text(notes).font(.caption).italic().foregroundStyle(.secondary)
                    }

                    Button("Go back to live sensors") {
                        Task { await store.stopReplaying() }
                    }
                    .font(.callout)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.orange.opacity(0.12))
        }
    }

    @ViewBuilder
    private var summary: some View {
        Section {
            let silent = store.readingWithoutAsking.count
            let total = store.snapshots.count

            VStack(alignment: .leading, spacing: 8) {
                Text(silent == 0
                     ? "Nothing is reading you yet."
                     : "^[\(silent) thing](inflect: true) about you \(silent == 1 ? "is" : "are") readable right now, and iOS never asked.")
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

                // Nothing here polls. Every value is a single reading taken at
                // a moment, and saying when makes that honest rather than
                // leaving stale numbers looking live.
                if let last = store.lastRefresh {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text("Read \(last.formatted(date: .omitted, time: .standard)) — pull down or tap ↻ to read again")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
                if snapshot.capability.gate != .asksOnce {
                    Text(snapshot.capability.gate.shortLabel)
                        .font(.caption2)
                        .foregroundStyle(snapshot.capability.gate == .neverAsks ? .orange : .secondary)
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
    RootView(store: SensorStore())
}
