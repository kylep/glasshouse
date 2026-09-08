import SwiftUI
import GlasshouseCore

struct RootView: View {
    let store: SensorStore
    let logging: LoggingCoordinator

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
        "Always allowed on iOS",
        "Permission required — granted",
        "Permission required — pending",
        "Access denied",
        "Unavailable on this device",
        "No public API exists",
        "Not built yet",
        "Not in this recording",
        "Error",
    ]

    var body: some View {
        NavigationStack {
            List {
                replayBanner
                statusLine

                section("Always allowed on iOS",
                        note: "No permission exists for these. Any app can read them.",
                        matching(store.readingWithoutAsking))

                section("Permission required — granted", note: nil,
                        matching(store.readingWithPermission))

                permissionSection

                section("Access denied",
                        note: "Reversible in Settings › Privacy & Security.",
                        matching(store.denied))

                section("Unavailable on this device",
                        note: RuntimeEnvironment.current == .simulator
                            ? "The Simulator has no such hardware. These need a real phone."
                            : "This device doesn't have the hardware.",
                        matching(store.unavailableHere))

                section("No public API exists",
                        note: "The sensor exists. The API doesn't.",
                        matching(store.impossible))

                // During replay these are not unbuilt — they simply were not
                // in the recording. Saying "not built yet" would misreport the
                // app's own state, which is the failure mode it exists to show.
                section(store.replaying == nil ? "Not built yet" : "Not in this recording",
                        note: store.replaying == nil
                            ? nil
                            : "These sensors exist, but the recording being played back does not contain them.",
                        matching(store.notBuiltYet))

                if !matching(store.anomalies).isEmpty {
                    section("Error",
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

                    // The filename was meaningless on a phone, where nobody
                    // browses files. What matters is where it came from and how
                    // much of it there is.
                    Text("Cached · captured on \(replay.recordedOn == .device ? "a phone" : "a simulator") · \(replay.sensors) sensors")
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

    /// A slim status line rather than a headline card.
    ///
    /// The section titles already say what each group is, so a banner
    /// summarising them was restating the list above the list — and the
    /// original wording ("and iOS never asked") argued a case rather than
    /// reporting a fact. What remains is only what the titles cannot tell you:
    /// when this was read, and whether it is live.
    @ViewBuilder
    private var statusLine: some View {
        if store.lastRefresh != nil || RuntimeEnvironment.current == .simulator {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    if RuntimeEnvironment.current == .simulator, store.replaying == nil {
                        Label("Simulator — most sensors report nothing here.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if let last = store.lastRefresh {
                        if store.isShowingCached {
                            // Never let a value from last launch look current.
                            Label("From your last visit, \(last.formatted(date: .omitted, time: .shortened)) — reading again…",
                                  systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.orange)
                        } else {
                            Label("Read \(last.formatted(date: .omitted, time: .standard))",
                                  systemImage: "clock")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption2)
                .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if !matching(store.awaitingPermission).isEmpty {
            Section {
                if isExpanded("Permission required — pending") {
                    ForEach(matching(store.awaitingPermission), id: \.capability.id) { snapshot in
                        NavigationLink {
                            SensorDetailView(sensorID: snapshot.capability.id, store: store, logging: logging)
                        } label: {
                            SensorRow(snapshot: snapshot)
                        }
                    }
                }
            } header: {
                sectionHeader("Permission required — pending",
                              count: matching(store.awaitingPermission).count)
            } footer: {
                if isExpanded("Permission required — pending") {
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
                            SensorDetailView(sensorID: snapshot.capability.id, store: store, logging: logging)
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
                Text("\(first.label): \(first.value.displayText)")
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
    RootView(store: SensorStore(), logging: LoggingCoordinator())
}
