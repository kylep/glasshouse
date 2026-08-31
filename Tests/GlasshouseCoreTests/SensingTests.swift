import Testing
import Foundation
@testable import GlasshouseCore

@Suite("Sensor samples")
struct SensorSampleTests {
    @Test("Fields are reachable by label")
    func fieldLookup() {
        let sample = SensorSample(sensor: "device.battery", timestamp: 0, fields: [
            SensorField("Level", .number(0.42, unit: "%")),
            SensorField("Charging", .boolean(true)),
        ])
        #expect(sample["Level"] == .number(0.42, unit: "%"))
        #expect(sample["Charging"] == .boolean(true))
        #expect(sample["Nonexistent"] == nil)
    }

    @Test("Coordinates are the only value flagged as precise")
    func precisionFlagging() {
        // Drives redaction defaults, so it must not silently widen.
        #expect(FieldValue.coordinate(latitude: 43.65, longitude: -79.38).isPrecise)
        #expect(!FieldValue.number(42).isPrecise)
        #expect(!FieldValue.text("Toronto").isPrecise)
        #expect(!FieldValue.integer(7).isPrecise)
        #expect(!FieldValue.boolean(true).isPrecise)
        #expect(!FieldValue.time(0).isPrecise)
    }

    @Test("Samples survive a Codable round trip")
    func codableRoundTrip() throws {
        let original = SensorSample(sensor: "core_location.position", timestamp: 1_756_598_400, fields: [
            SensorField("Coordinate", .coordinate(latitude: 43.6532, longitude: -79.3832)),
            SensorField("Altitude", .number(76.5, unit: "m")),
            SensorField("Source", .text("simulated")),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SensorSample.self, from: data)
        #expect(decoded == original)
    }

    @Test("Values describe themselves without a formatter")
    func plainDescriptions() {
        #expect(FieldValue.number(0.5, unit: "kPa").plainDescription == "0.5 kPa")
        #expect(FieldValue.number(0.5).plainDescription == "0.5")
        #expect(FieldValue.boolean(false).plainDescription == "no")
        #expect(FieldValue.text("hello").plainDescription == "hello")
    }
}

@Suite("Sensor availability")
struct SensorAvailabilityTests {
    @Test("Only ready and limited permit a read")
    func canRead() {
        #expect(SensorAvailability.ready.canRead)
        #expect(SensorAvailability.limited.canRead)
        #expect(!SensorAvailability.needsPermission.canRead)
        #expect(!SensorAvailability.denied.canRead)
        #expect(!SensorAvailability.restricted.canRead)
        #expect(!SensorAvailability.notImplemented.canRead)
        #expect(!SensorAvailability.unavailable(reason: .simulator).canRead)
    }

    @Test("Only an unasked permission is resolvable by asking")
    func resolvableByAsking() {
        #expect(SensorAvailability.needsPermission.isResolvableByAsking)
        #expect(!SensorAvailability.denied.isResolvableByAsking)
        #expect(!SensorAvailability.unavailable(reason: .hardwareAbsent).isResolvableByAsking)
    }

    @Test("Every unavailability reason explains itself")
    func reasonsAreExplained() {
        for reason in [UnavailabilityReason.simulator, .hardwareAbsent,
                       .entitlementMissing, .osTooOld, .noPublicAPI] {
            #expect(!reason.explanation.isEmpty)
            #expect(reason.explanation.hasSuffix("."))
        }
    }
}

@Suite("Fake sensors")
struct FakeSensorSourceTests {
    @Test("A reporting sensor yields its sample")
    func reporting() async {
        let sensor = FakeSensorSource.reporting("device.battery", [SensorField("Level", .number(0.5))])
        #expect(await sensor.availability() == .ready)
        let sample = await sensor.read()
        #expect(sample?["Level"] == .number(0.5))
    }

    @Test("A quiet sensor is available but returns nothing")
    func quietIsNotUnavailable() async {
        // The distinction this whole design exists to preserve.
        let sensor = FakeSensorSource.quiet("device.battery")
        #expect(await sensor.availability() == .ready)
        #expect(await sensor.read() == nil)
    }

    @Test("Asking grants a pending permission")
    func requestingAccess() async {
        let sensor = FakeSensorSource.awaitingPermission("contacts.all")
        #expect(await sensor.availability() == .needsPermission)
        #expect(await sensor.requestAccess() == .ready)
    }

    @Test("Asking a denied sensor changes nothing")
    func askingDeniedIsFutile() async {
        let sensor = FakeSensorSource.denied("contacts.all")
        #expect(await sensor.requestAccess() == .denied)
    }
}

@Suite("Sensor registry")
struct SensorRegistryTests {
    @Test("An unregistered capability still appears, as unimplemented")
    func coversTheWholeLedger() async {
        let registry = SensorRegistry()
        let snapshot = await registry.snapshot("core_motion.accelerometer")
        #expect(snapshot?.availability == .notImplemented)
    }

    @Test("A blocked capability reports impossible, not unimplemented")
    func blockedIsNotUnimplemented() async {
        // "Not built yet" and "no app may ever read this" are different claims,
        // and conflating them would misrepresent the sandbox.
        let registry = SensorRegistry()
        let snapshot = await registry.snapshot("restricted.ambient_light")
        #expect(snapshot?.availability == .unavailable(reason: .noPublicAPI))
    }

    @Test("An unknown identifier yields no snapshot")
    func unknownCapability() async {
        let registry = SensorRegistry()
        #expect(await registry.snapshot("not.a.real.sensor") == nil)
    }

    @Test("Registered sources are used in preference to the fallback")
    func registeredSourceWins() async {
        let registry = SensorRegistry([
            FakeSensorSource.reporting("device.battery", [SensorField("Level", .number(0.9))]),
        ])
        let snapshot = await registry.snapshot("device.battery")
        #expect(snapshot?.sample?["Level"] == .number(0.9))
    }

    @Test("Snapshotting everything covers the reachable ledger, in stable order")
    func snapshotAll() async {
        let registry = SensorRegistry()
        let snapshots = await registry.snapshotAll(reachableWith: .free)

        #expect(snapshots.count == CapabilityLedger.reachable(with: .free).count)
        #expect(snapshots.map(\.capability.id) == snapshots.map(\.capability.id).sorted())
    }

    @Test("No source exists for a capability the ledger does not know")
    func noOrphanSources() {
        let registry = LedgerConsistentFakes.registry(for: .simulator)
        #expect(registry.unknownSources.isEmpty)
    }
}

@Suite("Snapshot explanations")
struct SensorSnapshotTests {
    private func snapshot(
        _ id: SensorID,
        _ availability: SensorAvailability,
        sample: SensorSample? = nil
    ) throws -> SensorSnapshot {
        let capability = try #require(CapabilityLedger[id])
        return SensorSnapshot(capability: capability, availability: availability, sample: sample)
    }

    @Test("Every state produces a non-empty explanation")
    func alwaysExplains() throws {
        let states: [SensorAvailability] = [
            .ready, .limited, .needsPermission, .denied, .restricted,
            .notImplemented, .unavailable(reason: .simulator),
        ]
        for state in states {
            let snapshot = try snapshot("core_location.position", state)
            #expect(!snapshot.explanation.isEmpty)
        }
    }

    @Test("Unavailable silence is expected, and not flagged as an anomaly")
    func expectedSilence() throws {
        let snapshot = try snapshot("core_motion.accelerometer", .unavailable(reason: .simulator))
        #expect(snapshot.silenceIsExpected)
        #expect(!snapshot.isUnexplainedSilence)
        #expect(snapshot.explanation.contains("Simulator"))
    }

    @Test("A readable sensor that reports nothing IS an anomaly")
    func unexplainedSilenceIsFlagged() throws {
        // This is the case that would otherwise pass unnoticed: the sensor says
        // it works, the ledger says it works here, and yet no data arrived.
        let snapshot = try snapshot("contacts.all", .ready, sample: nil)
        #expect(snapshot.isUnexplainedSilence)
    }

    @Test("A sensor with a reading is never silent")
    func readingIsNotSilence() throws {
        let sample = SensorSample(sensor: "contacts.all", timestamp: 0,
                                  fields: [SensorField("Count", .integer(6))])
        let snapshot = try snapshot("contacts.all", .ready, sample: sample)
        #expect(snapshot.hasReading)
        #expect(!snapshot.silenceIsExpected)
        #expect(!snapshot.isUnexplainedSilence)
    }

    @Test("A blocked capability explains that no API exists, not that it broke")
    func blockedExplanation() throws {
        let snapshot = try snapshot("restricted.ambient_light",
                                    .unavailable(reason: .noPublicAPI))
        #expect(snapshot.explanation.contains("No app is allowed"))
    }
}

@Suite("Ledger-consistent fakes")
struct LedgerConsistentFakesTests {
    @Test("Simulator fakes agree with the ledger's measured behaviour")
    func fakesMatchTheLedger() async {
        let registry = LedgerConsistentFakes.registry(for: .simulator)
        let snapshots = await registry.snapshotAll()

        for snapshot in snapshots where snapshot.capability.simulator.silenceIsExpected {
            #expect(
                !snapshot.availability.canRead,
                "'\(snapshot.capability.id)' claims to read in a Simulator, but the ledger says it returns nothing"
            )
        }
    }

    @Test("Nothing is unexplainedly silent when fakes follow the ledger")
    func noAnomalies() async {
        // If this fails, the fakes and the ledger have drifted apart — which is
        // exactly the drift the registry exists to make impossible.
        let registry = LedgerConsistentFakes.registry(for: .simulator)
        let snapshots = await registry.snapshotAll()
        let anomalies = snapshots.unexplained.map(\.capability.id)
        #expect(anomalies.isEmpty, "unexplained: \(anomalies.map(\.rawValue).joined(separator: ", "))")
    }

    @Test("On a device, capabilities that only fail in a simulator become readable")
    func deviceEnvironmentDiffers() async {
        let simulator = LedgerConsistentFakes.registry(for: .simulator)
        let device = LedgerConsistentFakes.registry(for: .device)

        let simReadable = await simulator.snapshotAll().filter { $0.availability.canRead }.count
        let deviceReadable = await device.snapshotAll().filter { $0.availability.canRead || $0.availability == .needsPermission }.count

        #expect(deviceReadable > simReadable)
    }
}
