import SwiftUI
import GlasshouseCore

struct SensorDetailView: View {
    /// Deliberately the identifier rather than the snapshot itself.
    ///
    /// Holding a captured `SensorSnapshot` would freeze this screen at the
    /// state it had when it was pushed: granting or declining a permission
    /// updates `store.snapshots`, and a plain `let` registers no observation
    /// against it. The screen promises "you can decline, and this screen will
    /// say so", and it has to actually be able to.
    let sensorID: SensorID
    let store: SensorStore
    let logging: LoggingCoordinator

    @State private var isRequesting = false

    private var snapshot: SensorSnapshot? {
        store.snapshots.first { $0.capability.id == sensorID }
    }

    private var capability: Capability? {
        snapshot?.capability ?? CapabilityLedger[sensorID]
    }

    var body: some View {
        if let snapshot, let capability {
            content(snapshot: snapshot, capability: capability)
        } else {
            ContentUnavailableView("Not found", systemImage: "questionmark.circle")
        }
    }

    /// Recording, on the signal's own page.
    ///
    /// Previously this lived only under Settings › Recording, so a signal had
    /// two pages in two places — one describing it, one controlling it. Both
    /// routes now reach the same screen, which is what a reader expects after
    /// tapping a signal to find out about it.
    @ViewBuilder
    private func recordingSection(capability: Capability, canRead: Bool) -> some View {
        let policy = logging.policy(for: capability.id)
        let stored = logging.count(for: capability.id)

        Section {
            if canRead {
                NavigationLink {
                    SignalLoggingView(logging: logging, capability: capability)
                } label: {
                    HStack {
                        Label(policy.isEnabled ? "Recording" : "Not recording",
                              systemImage: policy.isEnabled ? "record.circle.fill" : "record.circle")
                            .foregroundStyle(policy.isEnabled ? Color.accentColor : .primary)
                        Spacer()
                        if stored > 0 {
                            Text("\(stored)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let featured = ChartableSignals.featured(for: capability.id), stored > 1 {
                    NavigationLink {
                        ChartDetailView(logging: logging, featured: featured)
                    } label: {
                        Label("View chart", systemImage: featured.kind == .rose
                              ? "chart.pie" : "chart.xyaxis.line")
                    }
                }
            } else {
                // Offering to record something that cannot produce a reading
                // would be an empty promise.
                Text("This signal can't be recorded until it produces readings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("History")
        } footer: {
            if canRead, !policy.isEnabled {
                Text("Nothing is stored for this signal yet.")
            }
        }
    }

    private func content(snapshot: SensorSnapshot, capability: Capability) -> some View {
        List {
            Section {
                Text(capability.reveals)
                    .font(.callout)
            } header: {
                Text("What this reveals")
            }

            if let sample = snapshot.sample {
                Section("Reading") {
                    ForEach(sample.fields, id: \.label) { field in
                        LabeledContent(field.label) {
                            Text(field.value.displayText)
                                .monospacedDigit()
                                .foregroundStyle(field.value.isPrecise ? .orange : .primary)
                        }
                    }
                }
            } else {
                Section("Reading") {
                    Text(snapshot.explanation)
                        .foregroundStyle(.secondary)
                }
            }

            if snapshot.availability.isResolvableByAsking {
                Section {
                    Button {
                        isRequesting = true
                        Task {
                            await store.requestAccess(to: sensorID)
                            isRequesting = false
                        }
                    } label: {
                        HStack {
                            Text("Ask for permission")
                            if isRequesting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRequesting)
                } footer: {
                    let shared = CapabilityLedger.sharingPermission(with: sensorID)
                    if shared.isEmpty {
                        Text("iOS will show its own dialog. You can decline, and this screen will say so.")
                    } else {
                        Text("""
                            iOS will show its own dialog. You can decline, and this screen will say so.

                            There is no separate permission for this — saying yes also covers \
                            \(shared.map(\.displayName).formatted(.list(type: .and))). \
                            iOS grants access per permission, not per sensor.
                            """)
                    }
                }
            }

            Section {
                Text(capability.gate.explanation)
                    .font(.callout)
                    .foregroundStyle(capability.gate == .neverAsks ? .orange : .secondary)
            } header: {
                Text("Does it ask?")
            }

            recordingSection(capability: capability, canRead: snapshot.availability.canRead)

            Section("How it works") {
                LabeledContent("Framework", value: capability.framework)
                LabeledContent("Consent", value: capability.gate.shortLabel)
                LabeledContent("Sensitivity", value: capability.sensitivity.rawValue.capitalized)
                LabeledContent("Costs", value: tierDescription(capability))

                if !capability.plistKeys.isEmpty {
                    ForEach(capability.plistKeys, id: \.self) { key in
                        LabeledContent("Declared as") {
                            Text(key).font(.caption).monospaced()
                        }
                    }
                }
                if let entitlement = capability.entitlement {
                    LabeledContent("Entitlement") {
                        Text(entitlement).font(.caption).monospaced()
                    }
                }
            }

            Section {
                LabeledContent("In the Simulator", value: simulatorDescription(capability))
                LabeledContent("Verified", value: capability.verified.description)
                Text(capability.source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("Provenance")
            } footer: {
                Text("Every claim on this screen has a source and a date, because Apple's platform changes and stale facts are worse than missing ones.")
            }

            if let notes = capability.notes {
                Section("Notes") {
                    Text(notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(capability.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tierDescription(_ capability: Capability) -> String {
        switch capability.tier {
        case .free: "Nothing — a free Apple account can do this"
        case .paid: "$99/year developer program"
        case .paidPlusApproval: "$99/year, plus Apple's approval"
        case .unobtainable: "Not available to ordinary developers"
        }
    }

    private func simulatorDescription(_ capability: Capability) -> String {
        switch capability.simulator {
        case .worksFully: "Works"
        case .worksWithCaveats: "Works, with caveats"
        case .returnsNothing: "Reports nothing"
        case .unavailable: "Not present"
        }
    }
}
