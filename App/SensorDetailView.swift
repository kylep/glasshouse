import SwiftUI
import GlasshouseCore

struct SensorDetailView: View {
    let snapshot: SensorSnapshot
    let store: SensorStore

    @State private var isRequesting = false

    private var capability: Capability { snapshot.capability }

    var body: some View {
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
                            await store.requestAccess(to: capability.id)
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
                LabeledContent("Costs", value: tierDescription)

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
                LabeledContent("In the Simulator", value: simulatorDescription)
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

    private var tierDescription: String {
        switch capability.tier {
        case .free: "Nothing — a free Apple account can do this"
        case .paid: "$99/year developer program"
        case .paidPlusApproval: "$99/year, plus Apple's approval"
        case .unobtainable: "Not available to ordinary developers"
        }
    }

    private var simulatorDescription: String {
        switch capability.simulator {
        case .worksFully: "Works"
        case .worksWithCaveats: "Works, with caveats"
        case .returnsNothing: "Reports nothing"
        case .unavailable: "Not present"
        }
    }
}
