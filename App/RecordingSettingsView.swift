import SwiftUI
import GlasshouseCore

/// Per-signal logging controls.
///
/// Everything starts off. Turning one on is a deliberate act, and the screen
/// says what it will cost — how often, how long it is kept, and whether iOS
/// can be asked to do it in the background.
struct RecordingSettingsView: View {
    let logging: LoggingCoordinator
    let store: SensorStore

    @State private var applied: Int?
    @State private var stopped: Int?

    /// Charted signals that can actually produce a reading right now.
    private var chartable: [SensorID] {
        let readableIDs = Set(readable.map(\.capability.id))
        return ChartableSignals.featured.map(\.sensor).filter(readableIDs.contains)
    }

    var body: some View {
        List {
            Section {
                Text("""
                    Nothing is recorded until you switch it on. Readings stay on \
                    this device, and you choose how long they are kept.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    applied = logging.enable(chartable)
                } label: {
                    Label("Record the \(chartable.count) charted signals", systemImage: "chart.xyaxis.line")
                }
                .disabled(chartable.isEmpty)

                Button {
                    applied = logging.enable(logging.recordable(from: readable))
                } label: {
                    Label("Record everything readable (\(readable.count))", systemImage: "waveform")
                }

                if logging.policies.isAnythingEnabled {
                    Button(role: .destructive) {
                        stopped = logging.disableAll()
                        applied = nil
                    } label: {
                        Label("Stop recording everything", systemImage: "stop.circle")
                    }
                }
            } header: {
                Text("Quick start")
            } footer: {
                if let applied {
                    Text(applied == 0
                         ? "Those were already recording."
                         : "^[\(applied) signal](inflect: true) switched on, every 5 minutes, kept for a week. Adjust any of them below.")
                } else if let stopped {
                    // Says what was kept, because "stop everything" sounds like
                    // it might have thrown the readings away.
                    Text("^[\(stopped) signal](inflect: true) stopped. Settings and recorded history are kept.")
                } else {
                    Text("Each starts at every 5 minutes, kept for a week. Already-configured signals keep their own settings.")
                }
            }

            Section {
                ForEach(readable, id: \.capability.id) { snapshot in
                    row(for: snapshot)
                }
            } header: {
                Text("Signals")
            } footer: {
                Text("Tap a name to set how often it records and how long it is kept.")
            }
        }
        .navigationTitle("Recording")
    }

    /// Only signals that can actually produce a reading — offering to log a
    /// denied or unavailable sensor would be an empty promise.
    private var readable: [SensorSnapshot] {
        store.snapshots
            .filter { $0.availability.canRead }
            .sorted { $0.capability.displayName < $1.capability.displayName }
    }

    /// A switch that works in place, and a name that opens the detail.
    ///
    /// The navigation round trip per signal — tap in, toggle, come back — was
    /// the actual tedium. Tapping through is now only needed to change interval
    /// or retention.
    private func row(for snapshot: SensorSnapshot) -> some View {
        let capability = snapshot.capability
        let policy = logging.policy(for: capability.id)
        let stored = logging.count(for: capability.id)

        return HStack(spacing: 12) {
            NavigationLink {
                SignalLoggingView(logging: logging, capability: capability)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(capability.displayName)
                    HStack(spacing: 6) {
                        Text(policy.isEnabled ? describe(policy) : "Off")
                            .foregroundStyle(policy.isEnabled ? Color.accentColor : .secondary)
                        if stored > 0 {
                            Text("· \(stored) stored").foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption2)
                }
            }

            Toggle("", isOn: Binding(
                get: { logging.policy(for: capability.id).isEnabled },
                set: { isOn in
                    var updated = logging.policy(for: capability.id)
                    updated.isEnabled = isOn
                    // A signal switched on inline has never been configured, so
                    // it gets the same defaults the presets use rather than
                    // silently landing on "on demand" and recording once.
                    if isOn, !updated.capture.isPolling, stored == 0 {
                        updated.capture = .interval(seconds: LoggingDefaults.interval)
                        updated.retention = LoggingDefaults.retention
                    }
                    logging.update(updated, for: capability.id)
                }
            ))
            .labelsHidden()
        }
    }

    private func describe(_ policy: LoggingPolicy) -> String {
        let cadence = switch policy.capture {
        case .onDemand: "On demand"
        case let .interval(seconds):
            CaptureMode.choices.first { $0.seconds == seconds }?.label ?? "Every \(seconds)s"
        }
        return "\(cadence) · kept \(policy.retention.label.lowercased())"
    }
}

/// One signal's logging settings.
struct SignalLoggingView: View {
    let logging: LoggingCoordinator
    let capability: Capability

    @State private var policy = LoggingPolicy.off
    @State private var justRecorded = false
    @State private var deleted: Int?

    var body: some View {
        List {
            Section {
                Toggle("Record this signal", isOn: Binding(
                    get: { policy.isEnabled },
                    set: { policy.isEnabled = $0; commit() }
                ))
            } footer: {
                Text(capability.reveals)
            }

            if policy.isEnabled {
                captureSection
                retentionSection
                backgroundSection
                dataSection
            }
        }
        .navigationTitle(capability.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { policy = logging.policy(for: capability.id) }
    }

    private var captureSection: some View {
        Section {
            Picker("When", selection: Binding(
                get: { policy.capture.seconds ?? 0 },
                set: {
                    policy.capture = $0 == 0 ? .onDemand : .interval(seconds: $0)
                    commit()
                }
            )) {
                Text("Only when I ask").tag(0)
                ForEach(CaptureMode.choices, id: \.seconds) { choice in
                    Text(choice.label).tag(choice.seconds)
                }
            }

            // Offered in every mode. Waiting fifteen minutes to find out
            // whether a signal records anything is a poor way to learn that it
            // does not.
            Button {
                Task {
                    await logging.record(capability.id)
                    justRecorded = true
                }
            } label: {
                Label(justRecorded ? "Recorded" : "Record a reading now",
                      systemImage: justRecorded ? "checkmark" : "plus.circle")
            }
        } header: {
            Text("How often")
        } footer: {
            if policy.capture.isPolling {
                // Stated plainly rather than discovered later: iOS grants no
                // reliable periodic background execution.
                Text("While the app is open. iOS does not allow reliable timed readings once an app is in the background.")
            }
        }
    }

    private var retentionSection: some View {
        Section {
            Picker("Keep readings for", selection: Binding(
                get: { policy.retention },
                set: { policy.retention = $0; commit() }
            )) {
                ForEach(Retention.choices, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
        } header: {
            Text("Retention")
        } footer: {
            if policy.retention == .forever {
                Text("Kept until you delete them. This is the one setting that turns a log into an archive.")
            } else {
                Text("Older readings are deleted automatically.")
            }
        }
    }

    private var backgroundSection: some View {
        Section {
            Toggle("Try to record in the background", isOn: Binding(
                get: { policy.allowBackground },
                set: { policy.allowBackground = $0; commit() }
            ))
        } footer: {
            Text("iOS decides whether to allow this and when. It is opportunistic — sometimes hourly, sometimes not for days — so it cannot be relied on for an even series.")
        }
    }

    private var dataSection: some View {
        Section {
            LabeledContent("Readings stored", value: "\(logging.count(for: capability.id))")

            if let featured = ChartableSignals.featured(for: capability.id) {
                NavigationLink {
                    ChartDetailView(logging: logging, featured: featured)
                } label: {
                    Label("View chart", systemImage: featured.kind == .rose
                          ? "chart.pie" : "chart.xyaxis.line")
                }
                .disabled(logging.count(for: capability.id) < 2)
            }
            LabeledContent("Sensitivity", value: capability.sensitivity.rawValue)

            Button(role: .destructive) {
                deleted = logging.deleteHistory(for: capability.id)
            } label: {
                Label("Delete recorded history", systemImage: "trash")
            }
        } header: {
            Text("Stored data")
        } footer: {
            if let deleted {
                Text("Deleted \(deleted) readings.")
            } else {
                Text("Stored in the \(capability.sensitivity.rawValue) database, separate from the other sensitivity classes.")
            }
        }
    }

    private func commit() {
        logging.update(policy, for: capability.id)
        justRecorded = false
        deleted = nil
    }
}
