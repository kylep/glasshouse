import SwiftUI
import UniformTypeIdentifiers
import GlasshouseCore
import GlasshouseSensors

/// Capture what the sensors are reporting, and play it back later.
///
/// The point of recording is that most sensors report nothing in a Simulator.
/// A trace taken on a phone is the only way to see this app behave realistically
/// without one — and the only way to check, months from now, whether a sensor
/// still does what it did today.
struct RecordingView: View {
    let store: SensorStore

    @State private var traces = TraceStore()
    @State private var notes = ""
    @State private var saved: [URL] = []
    @State private var sharing: URL?

    private let registry = GlasshouseSensors.liveRegistry()
    @State private var importing = false

    var body: some View {
        NavigationStack {
            List {
                explanation

                Section {
                    TextField("What's happening? e.g. walking upstairs", text: $notes, axis: .vertical)
                        .lineLimit(1...3)

                    Button {
                        Task {
                            await traces.record(from: registry, notes: notes.isEmpty ? nil : notes)
                            notes = ""
                            saved = traces.saved()
                        }
                    } label: {
                        HStack {
                            Label(traces.isRecording ? "Recording…" : "Record 10 seconds",
                                  systemImage: traces.isRecording ? "stop.circle" : "record.circle")
                            Spacer()
                            if traces.isRecording {
                                ProgressView(value: traces.progress)
                                    .frame(width: 60)
                            }
                        }
                    }
                    .disabled(traces.isRecording)
                } footer: {
                    Text("Ten readings of every sensor, a second apart. A note now saves you guessing later — a page of accelerometer numbers means nothing without knowing what you were doing.")
                }

                if let error = traces.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }

                if let last = traces.lastRecording {
                    Section("Just recorded") {
                        LabeledContent("Sensors with data", value: "\(last.sensorsWithData)")
                        LabeledContent("Samples", value: "\(last.totalSamples)")
                        Button {
                            sharing = last.url
                        } label: {
                            Label("Share this recording", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if !saved.isEmpty {
                    Section {
                        ForEach(saved, id: \.self) { url in
                            HStack {
                                Button {
                                    play(url)
                                } label: {
                                    HStack {
                                        Image(systemName: "play.circle")
                                        Text(url.lastPathComponent)
                                            .font(.caption)
                                            .monospaced()
                                    }
                                }
                                Spacer()
                                Button {
                                    sharing = url
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { traces.delete(saved[index]) }
                            saved = traces.saved()
                        }
                    } header: {
                        Text("Saved on this phone")
                    } footer: {
                        Text("These stay on the device and are readable only while it's unlocked. Sharing one sends it wherever you choose — a location trace is a record of where you were.")
                    }
                }
            }
            .navigationTitle("Record")
            .task { saved = traces.saved() }
            .sheet(item: $sharing) { url in
                ShareSheet(url: url)
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case let .success(url) = result { play(url) }
            }
        }
    }

    /// Loads a recording and switches the app onto it.
    private func play(_ url: URL) {
        // Files arriving from the picker sit outside the sandbox until claimed.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let loaded = TraceStore.load(url)
        guard !loaded.isEmpty else {
            traces.reportLoadFailure(url.lastPathComponent)
            return
        }
        Task { await store.startReplaying(loaded, named: url.lastPathComponent) }
    }

    private var explanation: some View {
        Section {
            Text("""
                Most sensors report nothing in a Simulator. A recording made \
                here is the only way to see this app behave realistically \
                without a phone — and the only way to tell, later, whether a \
                sensor still does what it does today.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// The system share sheet, so a recording can be sent off the device — but only
/// when the person operating it says so.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
