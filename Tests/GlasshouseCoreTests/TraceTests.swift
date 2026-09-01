import Testing
import Foundation
@testable import GlasshouseCore

@Suite("Recording traces")
struct TraceRecorderTests {
    private func snapshot(
        _ id: SensorID,
        _ availability: SensorAvailability,
        value: Double? = nil,
        at timestamp: Double = 0
    ) throws -> SensorSnapshot {
        let capability = try #require(CapabilityLedger[id])
        let sample = value.map {
            SensorSample(sensor: id, timestamp: timestamp,
                         fields: [SensorField("Value", .number($0))])
        }
        return SensorSnapshot(capability: capability, availability: availability, sample: sample)
    }

    @Test("Records the samples it is given, in order")
    func recordsInOrder() throws {
        var recorder = TraceRecorder(sensor: "device.battery", environment: .device, startedAt: 100)
        for (index, value) in [0.9, 0.8, 0.7].enumerated() {
            recorder.record(try snapshot("device.battery", .ready, value: value,
                                         at: 100 + Double(index)))
        }

        let trace = recorder.finish(notes: "discharging")
        #expect(trace.samples.count == 3)
        #expect(trace.samples.map(\.timestamp) == [100, 101, 102])
        #expect(trace.duration == 2)
        #expect(trace.notes == "discharging")
        #expect(trace.availability == .ready)
    }

    @Test("Ignores snapshots of a different sensor rather than trapping")
    func ignoresForeignSnapshots() throws {
        // A recorder pointed at the wrong stream should produce an empty trace,
        // not take down a capture session mid-recording.
        var recorder = TraceRecorder(sensor: "device.battery", environment: .device, startedAt: 0)
        recorder.record(try snapshot("device.locale", .ready, value: 1))

        #expect(recorder.sampleCount == 0)
        #expect(recorder.finish().isEmpty)
    }

    @Test("A sensor that was unavailable records as unavailable, with no samples")
    func recordsUnavailability() throws {
        var recorder = TraceRecorder(sensor: "core_motion.accelerometer",
                                     environment: .simulator, startedAt: 0)
        recorder.record(try snapshot("core_motion.accelerometer",
                                     .unavailable(reason: .simulator)))

        let trace = recorder.finish()
        #expect(trace.isEmpty)
        #expect(trace.availability == .unavailable)
        #expect(trace.recordedOn == .simulator)
    }

    @Test("Traces survive a Codable round trip")
    func codableRoundTrip() throws {
        var recorder = TraceRecorder(sensor: "core_location.position",
                                     environment: .device, startedAt: 1_756_598_400)
        let capability = try #require(CapabilityLedger["core_location.position"])
        recorder.record(SensorSnapshot(
            capability: capability,
            availability: .ready,
            sample: SensorSample(sensor: "core_location.position", timestamp: 1_756_598_400, fields: [
                SensorField("Coordinate", .coordinate(latitude: 43.6532, longitude: -79.3832)),
            ])
        ))

        let trace = recorder.finish(notes: "walking north")
        let data = try JSONEncoder().encode(trace)
        let decoded = try JSONDecoder().decode(SensorTrace.self, from: data)
        #expect(decoded == trace)
    }
}

@Suite("Replaying traces")
struct ReplaySensorSourceTests {
    private func trace(_ values: [Double], sensor: SensorID = "device.battery") -> SensorTrace {
        SensorTrace(
            sensor: sensor,
            recordedOn: .device,
            recordedAt: 0,
            availability: .ready,
            samples: values.enumerated().map { index, value in
                SensorSample(sensor: sensor, timestamp: Double(index),
                             fields: [SensorField("Value", .number(value))])
            }
        )
    }

    @Test("Replays the recorded availability, not the live one")
    func replaysAvailability() async {
        let source = ReplaySensorSource(trace([1]))
        #expect(await source.availability() == .ready)
    }

    @Test("Reading is deterministic — the same position always gives the same sample")
    func deterministic() async {
        let source = ReplaySensorSource(trace([0.9, 0.8]))
        let first = await source.read()
        let again = await source.read()
        #expect(first == again)
    }

    @Test("Advancing walks the recording, then wraps")
    func advancingWraps() async {
        // Wrapping rather than running dry: a trace is a loop of plausible
        // behaviour, and going silent after N reads would look like a fault.
        var source = ReplaySensorSource(trace([0.9, 0.8, 0.7]))
        var seen: [FieldValue?] = []
        for _ in 0..<4 {
            seen.append(await source.read()?["Value"])
            source = source.advanced()
        }
        #expect(seen == [.number(0.9), .number(0.8), .number(0.7), .number(0.9)])
    }

    @Test("An empty trace reads as nothing rather than crashing")
    func emptyTrace() async {
        let empty = SensorTrace(sensor: "device.battery", recordedOn: .simulator,
                                recordedAt: 0, availability: .unavailable, samples: [])
        let source = ReplaySensorSource(empty)
        #expect(await source.read() == nil)
        #expect(await source.availability() == .unavailable(reason: .simulator))
    }

    @Test("Progress reports position, and is zero for a single sample")
    func progress() {
        let single = ReplaySensorSource(trace([1]))
        #expect(single.progress == 0)

        let source = ReplaySensorSource(trace([1, 2, 3]))
        #expect(source.progress == 0)
        #expect(source.advanced().advanced().progress == 1)
    }
}

@Suite("Replay registry")
struct ReplayRegistryTests {
    @Test("A registry of traces serves them as sensors")
    func servesTraces() async {
        let battery = SensorTrace(
            sensor: "device.battery", recordedOn: .device, recordedAt: 0,
            availability: .ready,
            samples: [SensorSample(sensor: "device.battery", timestamp: 0,
                                   fields: [SensorField("Level", .number(84))])]
        )
        let registry = SensorRegistry.replaying([battery])
        let snapshot = await registry.snapshot("device.battery")

        #expect(snapshot?.sample?["Level"] == .number(84))
        #expect(snapshot?.availability == .ready)
    }

    @Test("Capabilities with no trace stay unimplemented rather than breaking")
    func partialCoverageIsFine() async {
        let registry = SensorRegistry.replaying([])
        let snapshot = await registry.snapshot("device.battery")
        #expect(snapshot?.availability == .notImplemented)
    }

    @Test("Empty traces are dropped rather than served as silent sensors")
    func emptyTracesAreDropped() async {
        // Serving one would produce a capability claiming .ready and reporting
        // nothing — the unexplained silence the whole design forbids.
        let empty = SensorTrace(sensor: "device.battery", recordedOn: .device,
                                recordedAt: 0, availability: .ready, samples: [])
        let registry = SensorRegistry.replaying([empty])
        let snapshot = await registry.snapshot("device.battery")

        #expect(snapshot?.availability == .notImplemented)
        #expect(snapshot?.isUnexplainedSilence == false)
    }
}
