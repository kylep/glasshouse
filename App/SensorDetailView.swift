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

    @ViewBuilder
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
                            Text(field.value.plainDescription)
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
                    Text("iOS will show its own dialog. You can decline, and this screen will say so.")
                }
            }

            Section("How it works") {
                LabeledContent("Framework", value: capability.framework)
                LabeledContent("Asks permission", value: capability.promptsUser ? "Yes" : "No")
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
