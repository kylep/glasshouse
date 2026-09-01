import Foundation
import Observation
import GlasshouseCore

/// Records what the sensors actually report, so it can be replayed later.
///
/// The replay layer is only worth having if something feeds it. This is that
/// something: it drives the registry for a fixed number of passes, folds each
/// snapshot into a per-sensor recorder, and writes the result out as JSON.
///
/// **Recordings are personal data.** A location trace is a record of where
/// someone was; a Bluetooth trace names the devices around them. They are
/// written with complete file protection, kept out of the repository by
/// `.gitignore`, and never leave the device except when the user explicitly
/// shares one.
@MainActor
@Observable
final class TraceStore {
    private(set) var isRecording = false
    private(set) var progress = 0.0
    private(set) var lastRecording: RecordingSummary?
    private(set) var error: String?

    struct RecordingSummary: Sendable {
        let traces: [SensorTrace]
        let url: URL
        let recordedAt: Date

        var sensorsWithData: Int { traces.filter { !$0.isEmpty }.count }
        var totalSamples: Int { traces.reduce(0) { $0 + $1.samples.count } }
    }

    /// Captures `passes` readings of every sensor, a second apart.
    ///
    /// Sequential rather than parallel on purpose: a trace is meant to be a
    /// coherent picture of one moment repeated, and firing every sensor at once
    /// would have the barometer and the Bluetooth scan contending for the same
    /// few seconds.
    func record(
        from registry: SensorRegistry,
        passes: Int = 10,
        interval: Double = 1.0,
        notes: String?
    ) async {
        guard !isRecording else { return }
        isRecording = true
        progress = 0
        error = nil
        defer { isRecording = false }

        let startedAt = Date().timeIntervalSince1970
        var recorders: [SensorID: TraceRecorder] = [:]
        for capability in CapabilityLedger.reachable(with: .free) {
            recorders[capability.id] = TraceRecorder(sensor: capability.id, startedAt: startedAt)
        }

        for pass in 0..<passes {
            for snapshot in await registry.snapshotAll() {
                recorders[snapshot.capability.id]?.record(snapshot)
            }
            progress = Double(pass + 1) / Double(passes)
            if pass < passes - 1 {
                try? await Task.sleep(for: .seconds(interval))
            }
        }

        let traces = recorders.values
            .map { $0.finish(notes: notes) }
            .sorted { $0.sensor < $1.sensor }

        do {
            let url = try write(traces, at: startedAt)
            lastRecording = RecordingSummary(traces: traces, url: url, recordedAt: Date())
        } catch {
            // Surfaced rather than swallowed: a recording that silently failed
            // to save is worse than one that never started, because the user
            // believes they have it.
            self.error = "Couldn't save the recording: \(error.localizedDescription)"
        }
    }

    private func write(_ traces: [SensorTrace], at timestamp: Double) throws -> URL {
        let directory = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Traces", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(traces)

        let stamp = Int(timestamp)
        let url = directory.appendingPathComponent("glasshouse-trace-\(stamp).json")

        // Same protection class as the attribution history, and for the same
        // reason: this is a record of where someone was and what was near them.
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Every recording on this device, newest first.
    func saved() -> [URL] {
        guard let directory = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ).appendingPathComponent("Traces", isDirectory: true),
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
            )
        else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        if lastRecording?.url == url { lastRecording = nil }
    }

    /// Reports a recording that could not be read.
    ///
    /// A load that silently does nothing looks identical to a tap that missed,
    /// and leaves the person unsure whether the app or their finger failed.
    func reportLoadFailure(_ name: String) {
        error = "Couldn't read \(name). It may not be a Glasshouse recording."
    }

    /// Loads recordings back, for replay.
    static func load(_ url: URL) -> [SensorTrace] {
        guard let data = try? Data(contentsOf: url),
              let traces = try? JSONDecoder().decode([SensorTrace].self, from: data)
        else { return [] }
        return traces
    }
}
