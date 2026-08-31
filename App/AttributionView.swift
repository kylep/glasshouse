import SwiftUI
import UniformTypeIdentifiers
import GlasshouseCore

/// What your *other* apps did — the only cross-app view iOS permits.
struct AttributionView: View {
    @State private var store = AttributionStore()
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                if store.history.isEmpty {
                    onboarding
                } else {
                    summary
                    trackerSection
                    appsSection
                }

                if let error = store.importError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }

                Section {
                    Button("Import a privacy report") { isImporting = true }
                    if !store.history.isEmpty {
                        Button("Delete everything imported", role: .destructive) {
                            store.deleteEverything()
                        }
                    }
                }
            }
            .navigationTitle("Other apps")
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json, .plainText, .data]
            ) { result in
                if case let .success(url) = result { store.importReport(from: url) }
            }
        }
    }

    // MARK: - Sections

    private var onboarding: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("No app can read what other apps accessed.")
                    .font(.headline)

                Text("""
                    There's no API for it, at any price — Apple confirmed as much \
                    to developers in March 2026. The one legitimate route is a \
                    report iOS keeps for you, which only you can export.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                Text("To use it:").font(.subheadline.bold())
                stepsList

                Label("iOS keeps only 7 days, and turning the report off erases it.",
                      systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .padding(.vertical, 4)
        }
    }

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            step(1, "Settings → Privacy & Security → App Privacy Report")
            step(2, "Turn it on, if it isn't already")
            step(3, "Wait a few days for it to record something")
            step(4, "Tap the share button there, save the file")
            step(5, "Come back and import it below")
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(text).font(.caption)
        }
    }

    private var summary: some View {
        Section {
            let apps = store.history.apps.count
            let accesses = store.history.accesses.count
            let trackers = store.history.trackers.count

            VStack(alignment: .leading, spacing: 8) {
                Text("\(apps) apps, \(accesses) recorded accesses.")
                    .font(.headline)
                if trackers > 0 {
                    Text("iOS flagged \(trackers) of the domains they contacted as tracking you across apps.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let schema = store.lastImport?.schema {
                    Text("Last import used the \(schema.rawValue) format.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var trackerSection: some View {
        let offenders = store.history.appsContactingTrackers
        if !offenders.isEmpty {
            Section {
                ForEach(offenders, id: \.bundleID) { entry in
                    LabeledContent(entry.bundleID) {
                        Text("^[\(entry.domains) domain](inflect: true)")
                            .foregroundStyle(.orange)
                    }
                    .font(.callout)
                }
            } header: {
                Text("Contacted tracking domains")
            } footer: {
                Text("iOS itself flagged these as tracking people across apps and websites. That's Apple's judgement, not a guess.")
            }
        }
    }

    private var appsSection: some View {
        Section("What each app touched") {
            ForEach(store.history.deepestReachPerApp, id: \.bundleID) { entry in
                NavigationLink {
                    AppActivityDetailView(bundleID: entry.bundleID, history: store.history)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.bundleID).font(.callout)
                        Text("Reached: \(entry.resource.displayName)")
                            .font(.caption)
                            .foregroundStyle(entry.resource.sensitivity == .intimate ? .orange : .secondary)
                    }
                }
            }
        }
    }
}

struct AppActivityDetailView: View {
    let bundleID: String
    let history: PrivacyReportHistory

    var body: some View {
        List {
            Section("Resources accessed") {
                ForEach(AccessedResource.allCases, id: \.self) { resource in
                    let events = history.accesses(by: bundleID).filter { $0.resource == resource }
                    if !events.isEmpty {
                        LabeledContent(resource.displayName) {
                            let seconds = history.totalDuration(bundleID: bundleID, resource: resource)
                            Text(seconds > 0
                                 ? "\(events.count)×, \(Int(seconds))s total"
                                 : "\(events.count)×")
                                .monospacedDigit()
                        }
                    }
                }
            }

            let contacts = history.contacts(by: bundleID)
            if !contacts.isEmpty {
                Section {
                    ForEach(contacts, id: \.domain) { contact in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(contact.domain).font(.callout)
                                Spacer()
                                Text("\(contact.hits)×").font(.caption).monospacedDigit()
                            }
                            if contact.flaggedAsTracker {
                                Text("Flagged by iOS as cross-app tracking")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            if let owner = contact.owner {
                                Text(owner).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Domains contacted")
                } footer: {
                    Text("Counts are the largest seen in any single import, not a sum — report windows overlap, so adding them would inflate the numbers.")
                }
            }
        }
        .navigationTitle(bundleID)
        .navigationBarTitleDisplayMode(.inline)
    }
}
