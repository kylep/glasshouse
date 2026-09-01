import SwiftUI
import GlasshouseCore
import GlasshouseSensors

/// Capture what the sensors are reporting, and play it back later.
///
/// The point of recording is that most sensors report nothing in a Simulator.
/// A trace taken on a phone is the only way to see this app behave realistically
/// without one — and the only way to check, months from now, whether a sensor
/// still does what it did today.
struct RecordingView: View {
    @State private var store = TraceStore()
    @State private var notes = ""
    @State private var saved: [URL] = []
    @State private var sharing: URL?

    private let registry = GlasshouseSensors.liveRegistry()

    var body: some View {
        NavigationStack {
            List {
                explanation

                Section {
                    TextField("What's happening? e.g. walking upstairs", text: $notes, axis: .vertical)
                        .lineLimit(1...3)

                    Button {
                        Task {
                            await store.record(from: registry, notes: notes.isEmpty ? nil : notes)
                            notes = ""
                            saved = store.saved()
                        }
                    } label: {
                        HStack {
                            Label(store.isRecording ? "Recording…" : "Record 10 seconds",
                                  systemImage: store.isRecording ? "stop.circle" : "record.circle")
                            Spacer()
                            if store.isRecording {
                                ProgressView(value: store.progress)
                                    .frame(width: 60)
                            }
                        }
                    }
                    .disabled(store.isRecording)
                } footer: {
                    Text("Ten readings of every sensor, a second apart. A note now saves you guessing later — a page of accelerometer numbers means nothing without knowing what you were doing.")
                }

                if let error = store.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }

                if let last = store.lastRecording {
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
                            Button {
                                sharing = url
                            } label: {
                                HStack {
                                    Text(url.lastPathComponent)
                                        .font(.caption)
                                        .monospaced()
                                    Spacer()
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { store.delete(saved[index]) }
                            saved = store.saved()
                        }
                    } header: {
                        Text("Saved on this phone")
                    } footer: {
                        Text("These stay on the device and are readable only while it's unlocked. Sharing one sends it wherever you choose — a location trace is a record of where you were.")
                    }
                }
            }
            .navigationTitle("Record")
            .task { saved = store.saved() }
            .sheet(item: $sharing) { url in
                ShareSheet(url: url)
            }
        }
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
