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

    var body: some View {
        List {
            Section {
                Text("""
                    Nothing is recorded until you switch it on here. Readings \
                    stay on this device, and you choose how long they are kept.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(readable, id: \.capability.id) { snapshot in
                NavigationLink {
                    SignalLoggingView(logging: logging, capability: snapshot.capability)
                } label: {
                    row(for: snapshot)
                }
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

    private func row(for snapshot: SensorSnapshot) -> some View {
        let policy = logging.policy(for: snapshot.capability.id)
        let stored = logging.count(for: snapshot.capability.id)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.capability.displayName)
                Text(policy.isEnabled ? describe(policy) : "Off")
                    .font(.caption2)
                    .foregroundStyle(policy.isEnabled ? Color.accentColor : .secondary)
            }
            Spacer()
            if stored > 0 {
                Text("\(stored)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
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
