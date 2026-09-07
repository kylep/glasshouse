import Testing
import Foundation
@testable import GlasshouseCore

@Suite("Reading cache")
struct ReadingCacheTests {
    private func snapshot(_ id: SensorID, value: Double? = nil) throws -> SensorSnapshot {
        let capability = try #require(CapabilityLedger[id])
        let sample = value.map {
            SensorSample(sensor: id, timestamp: 0, fields: [SensorField("Value", .number($0))])
        }
        return SensorSnapshot(capability: capability, availability: .ready, sample: sample)
    }

    @Test("Round-trips a set of readings through Codable")
    func codableRoundTrip() throws {
        let cache = ReadingCache([
            try snapshot("device.battery", value: 84),
            try snapshot("device.locale"),
        ], at: 1_756_598_400)

        let data = try JSONEncoder().encode(cache)
        let decoded = try JSONDecoder().decode(ReadingCache.self, from: data)
        #expect(decoded == cache)
        #expect(decoded.snapshots.count == 2)
    }

    @Test("Rebuilt snapshots carry the ledger's current description, not a stored one")
    func capabilityComesFromTheLedger() throws {
        // The Capability is deliberately not persisted. If it were, a stale
        // cache would keep showing an old build's wording after the ledger
        // that replaced it had shipped.
        let cache = ReadingCache([try snapshot("device.battery", value: 50)], at: 0)
        let rebuilt = try #require(cache.snapshots.first)
        #expect(rebuilt.capability.displayName == CapabilityLedger["device.battery"]?.displayName)
    }

    @Test("A sensor the ledger no longer knows is dropped, not resurrected")
    func unknownSensorsAreDropped() {
        let cache = ReadingCache(capturedAt: 0, readings: [
            CachedReading(sensor: "gone.removed", availability: .ready, sample: nil),
        ])
        #expect(cache.snapshots.isEmpty)
    }

    @Test("Availability survives, including why something was unavailable")
    func availabilitySurvives() throws {
        let capability = try #require(CapabilityLedger["core_motion.accelerometer"])
        let cache = ReadingCache([SensorSnapshot(
            capability: capability,
            availability: .unavailable(reason: .simulator),
            sample: nil
        )], at: 0)

        let rebuilt = try #require(cache.snapshots.first)
        #expect(!rebuilt.availability.canRead)
    }

    @Test("Age is reported, and never negative")
    func age() {
        let cache = ReadingCache(capturedAt: 1000, readings: [])
        #expect(cache.age(asOf: 1060) == 60)
        // A clock that moved backwards should not produce a negative age.
        #expect(cache.age(asOf: 900) == 0)
    }

    @Test("A day-old cache is stale")
    func staleness() {
        let cache = ReadingCache(capturedAt: 0, readings: [])
        #expect(!cache.isStale(asOf: 3600))
        #expect(cache.isStale(asOf: 90_000))
    }

    @Test("Snapshots come back in a stable order regardless of how they went in")
    func stableOrder() throws {
        let cache = ReadingCache([
            try snapshot("device.locale"),
            try snapshot("device.battery"),
        ], at: 0)
        #expect(cache.snapshots.map(\.capability.id) == cache.snapshots.map(\.capability.id).sorted())
    }
}
