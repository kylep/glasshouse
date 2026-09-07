import SwiftUI
import GlasshouseCore

struct RootView: View {
    let store: SensorStore

    @State private var query = ""

    /// Sections the reader has collapsed.
    ///
    /// Tracks what is CLOSED rather than what is open, so a section added later
    /// appears expanded by default rather than silently hidden.
    @State private var collapsed: Set<String> = Self.collapsedByDefault

    /// Everything starts closed. Fifty-one rows is a wall of text; the
    /// section counts say more at a glance than the rows do, and opening one
    /// is a deliberate act.
    private static let collapsedByDefault: Set<String> = [
        "Reading you right now",
        "Reading you, because you allowed it",
        "Waiting to be asked",
        "You said no",
        "Not available here",
        "No app is allowed to read these",
        "Not built yet",
        "Unexplained",
    ]

    var body: some View {
        NavigationStack {
            List {
                replayBanner
                summary

                section("Reading you right now",
                        note: "iOS never asked about any of these. There is no dialog, nothing in Settings, and no way to switch them off.",
                        matching(store.readingWithoutAsking))

                section("Reading you, because you allowed it", note: nil,
                        matching(store.readingWithPermission))

                permissionSection

                section("You said no",
                        note: "Declining is a real answer, and these stay listed rather than disappearing. Settings › Privacy & Security reverses any of them.",
                        matching(store.denied))

                section("Not available here",
                        note: RuntimeEnvironment.current == .simulator
                            ? "The Simulator has no such hardware. These need a real phone."
                            : "This device doesn't have the hardware.",
                        matching(store.unavailableHere))

                section("No app is allowed to read these",
                        note: "The sensor exists. The API doesn't.",
                        matching(store.impossible))

                section("Not built yet", note: nil, matching(store.notBuiltYet))

                if !matching(store.anomalies).isEmpty {
                    section("Unexplained",
                            note: "These claim to work and should work here, but reported nothing. Probably a bug.",
                            matching(store.anomalies))
                }
            }
            .navigationTitle("Glasshouse")
            .searchable(text: $query, prompt: "Search — try \"who is near me\"")
            .overlay {
                if !query.isEmpty, noMatches {
                    ContentUnavailableView.search(text: query)
                }
            }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
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
            // Deliberately unfiltered: how much is readable right now is a fact
            // about the phone, and it should not change as someone types.
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
                        Image(systemName: store.isShowingCached ? "clock.arrow.circlepath" : "clock")
                        if store.isShowingCached {
                            // Never let a value from last launch look current.
                            Text("From your last visit, \(last.formatted(date: .omitted, time: .shortened)) — reading again now…")
                        } else {
                            Text("Read \(last.formatted(date: .omitted, time: .standard)) — pull down or tap ↻ to read again")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(store.isShowingCached ? Color.orange : Color.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if !matching(store.awaitingPermission).isEmpty {
            Section {
                if isExpanded("Waiting to be asked") {
                    ForEach(matching(store.awaitingPermission), id: \.capability.id) { snapshot in
                        NavigationLink {
                            SensorDetailView(sensorID: snapshot.capability.id, store: store)
                        } label: {
                            SensorRow(snapshot: snapshot)
                        }
                    }
                }
            } header: {
                sectionHeader("Waiting to be asked",
                              count: matching(store.awaitingPermission).count)
            } footer: {
                if isExpanded("Waiting to be asked") {
                    Text("Tap one to see what it would reveal, then decide.")
                }
            }
        }
    }

    /// Whether the search excluded everything.
    ///
    /// Checked explicitly so an empty result says so, rather than rendering a
    /// blank list that looks like the app failed to load.
    private var noMatches: Bool {
        store.snapshots.allSatisfy { !$0.capability.matches(query) }
    }

    /// Narrows a section to what matches the search, keeping the grouping.
    ///
    /// Filtering within sections rather than flattening to a result list is
    /// deliberate: "which of these needed no permission" is the question the
    /// grouping answers, and it should survive searching.
    private func matching(_ snapshots: [SensorSnapshot]) -> [SensorSnapshot] {
        guard !query.isEmpty else { return snapshots }
        return snapshots.filter { $0.capability.matches(query) }
    }

    /// Whether a section is currently showing its rows.
    ///
    /// A section always opens while searching. Leaving it closed would hide
    /// matches behind a collapsed header and make the search look broken.
    private func isExpanded(_ title: String) -> Bool {
        !query.isEmpty || !collapsed.contains(title)
    }

    @ViewBuilder
    private func section(_ title: String, note: String?, _ snapshots: [SensorSnapshot]) -> some View {
        if !snapshots.isEmpty {
            Section {
                if isExpanded(title) {
                    ForEach(snapshots, id: \.capability.id) { snapshot in
                        NavigationLink {
                            SensorDetailView(sensorID: snapshot.capability.id, store: store)
                        } label: {
                            SensorRow(snapshot: snapshot)
                        }
                    }
                }
            } header: {
                sectionHeader(title, count: snapshots.count)
            } footer: {
                if let note, isExpanded(title) { Text(note) }
            }
        }
    }

    /// A tappable header carrying the section's name and how many are in it.
    ///
    /// The count is the point as much as the collapsing: seeing "20" next to
    /// "Reading you right now" states the app's whole argument before anyone
    /// scrolls a single row.
    private func sectionHeader(_ title: String, count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsed.contains(title) {
                    collapsed.remove(title)
                } else {
                    collapsed.insert(title)
                }
            }
        } label: {
            HStack {
                Image(systemName: isExpanded(title) ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Searching forces every section open, so offering a control that
        // cannot do anything would be a lie.
        .disabled(!query.isEmpty)
        .accessibilityLabel("\(title), \(count) sensors")
        .accessibilityHint(isExpanded(title) ? "Collapses this section" : "Expands this section")
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
