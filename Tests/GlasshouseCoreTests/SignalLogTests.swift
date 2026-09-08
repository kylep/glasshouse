import Testing
import Foundation
@testable import GlasshouseCore

@Suite("Signal log")
struct SignalLogTests {
    /// A fresh database per test, deleted afterwards.
    private func makeLog(_ sensitivity: Sensitivity = .ambient) throws -> (SignalLog, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glasshouse-tests-\(UUID().uuidString)")
        return (try SignalLog(sensitivity: sensitivity, directory: directory), directory)
    }

    private func sample(_ sensor: SensorID, _ value: Double, at time: Double) -> SensorSample {
        SensorSample(sensor: sensor, timestamp: time, fields: [
            SensorField("Level", .number(value, unit: "%")),
            SensorField("State", .text("charging")),
        ])
    }

    @Test("Stores a reading and reads it back as a series")
    func roundTrip() throws {
        let (log, directory) = try makeLog()
        defer { try? FileManager.default.removeItem(at: directory) }

        try log.append(sample("device.battery", 84, at: 1000))
        try log.append(sample("device.battery", 83, at: 2000))

        let series = try log.series(sensor: "device.battery", field: "Level")
        #expect(series.map(\.value) == [84, 83])
        #expect(series.map(\.at) == [1000, 2000])
    }

    @Test("Series come back oldest first, whatever order they went in")
    func ordering() throws {
        let (log, directory) = try makeLog()
        defer { try? FileManager.default.removeItem(at: directory) }

        for time in [3000.0, 1000, 2000] {
            try log.append(sample("device.battery", time / 100, at: time))
        }
        #expect(try log.series(sensor: "device.battery", field: "Level").map(\.at) == [1000, 2000, 3000])
    }

    @Test("One sensor's readings do not appear under another")
    func sensorsAreSeparate() throws {
        let (log, directory) = try makeLog()
        defer { try? FileManager.default.removeItem(at: directory) }

        try log.append(sample("device.battery", 84, at: 1000))
        try log.append(sample("device.thermal", 20, at: 1000))

        #expect(try log.count(sensor: "device.battery") == 1)
        #expect(try log.series(sensor: "device.thermal", field: "Level").count == 1)
        #expect(try log.series(sensor: "device.locale", field: "Level").isEmpty)
    }

    @Test("Text fields are stored but excluded from numeric series")
    func textIsNotCharted() throws {
        let (log, directory) = try makeLog()
        defer { try? FileManager.default.removeItem(at: directory) }

        try log.append(sample("device.battery", 84, at: 1000))
        // "State" is text, so it must not appear as a chartable series.
        #expect(try log.series(sensor: "device.battery", field: "State").isEmpty)
        #expect(try log.numericFields(sensor: "device.battery") == ["Level"])
    }

    @Test("A since filter excludes older readings")
    func sinceFilter() throws {
        let (log, directory) = try makeLog()
        defer { try? FileManager.default.removeItem(at: directory) }

        for time in [1000.0, 2000, 3000] {
            try log.append(sample("device.battery", 80, at: time))
        }
        #expect(try log.series(sensor: "device.battery", field: "Level", since: 2000).count == 2)
    }

    @Test("Retention deletes only what is past the cutoff")
    func retentionDeletesOldReadings() throws {
        let (log, directory) = try makeLog()
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = 100_000.0
        try log.append(sample("device.battery", 80, at: now - 7200))   // 2 hours old
        try log.append(sample("device.battery", 81, at: now - 60))     // a minute old

        let removed = try log.enforce(.hours(1), on: "device.battery", now: now)
        #expect(removed == 1)
        #expect(try log.count(sensor: "device.battery") == 1)
    }

    @Test("Retention takes the fields with the samples")
    func retentionDoesNotOrphanFields() throws {
        // SQLite has foreign keys off by default, so ON DELETE CASCADE cannot
        // be relied on. Orphaned field rows would grow the file forever.
        let (log, directory) = try makeLog()
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = 100_000.0
        try log.append(sample("device.battery", 80, at: now - 7200))
        try log.enforce(.hours(1), on: "device.battery", now: now)

        #expect(try log.series(sensor: "device.battery", field: "Level").isEmpty)
    }

    @Test("Indefinite retention deletes nothing")
    func foreverKeepsEverything() throws {
        let (log, directory) = try makeLog()
        defer { try? FileManager.default.removeItem(at: directory) }

        try log.append(sample("device.battery", 80, at: 0))
        #expect(try log.enforce(.forever, on: "device.battery", now: 999_999_999) == 0)
        #expect(try log.count(sensor: "device.battery") == 1)
    }

    @Test("Deleting a sensor's readings removes all of them")
    func deleteAll() throws {
        let (log, directory) = try makeLog()
        defer { try? FileManager.default.removeItem(at: directory) }

        try log.append(sample("device.battery", 80, at: 1000))
        try log.append(sample("device.battery", 81, at: 2000))

        #expect(try log.deleteAll(sensor: "device.battery") == 2)
        #expect(try log.count(sensor: "device.battery") == 0)
    }

    @Test("Sensitivity classes live in separate files")
    func separateFilesPerSensitivity() throws {
        // The whole point: an intimate reading must not be reachable from a
        // connection opened for ambient data.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glasshouse-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let ambient = try SignalLog(sensitivity: .ambient, directory: directory)
        let intimate = try SignalLog(sensitivity: .intimate, directory: directory)

        #expect(ambient.url != intimate.url)

        try intimate.append(sample("health.vitals", 62, at: 1000))
        #expect(try ambient.count(sensor: "health.vitals") == 0)
        #expect(try intimate.count(sensor: "health.vitals") == 1)
    }

    @Test("Coordinates are stored whole, never as separate numbers")
    func coordinatesStayTogether() throws {
        let (log, directory) = try makeLog(.intimate)
        defer { try? FileManager.default.removeItem(at: directory) }

        try log.append(SensorSample(sensor: "core_location.position", timestamp: 1000, fields: [
            SensorField("Where", .coordinate(latitude: 43.6532, longitude: -79.3832)),
        ]))

        // Not chartable, deliberately: splitting a coordinate would let a query
        // read latitude without longitude, which is a shape worth not enabling.
        #expect(try log.series(sensor: "core_location.position", field: "Where").isEmpty)
        #expect(try log.count(sensor: "core_location.position") == 1)
    }

    @Test("Reopening the same file keeps the data")
    func persistsAcrossOpens() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glasshouse-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let log = try SignalLog(sensitivity: .ambient, directory: directory)
            try log.append(sample("device.battery", 84, at: 1000))
        }
        let reopened = try SignalLog(sensitivity: .ambient, directory: directory)
        #expect(try reopened.count(sensor: "device.battery") == 1)
    }
}

@Suite("Logging policy")
struct LoggingPolicyTests {
    @Test("Everything is off by default")
    func defaultsToOff() {
        let policies = LoggingPolicies()
        #expect(!policies[.init(rawValue: "device.battery")].isEnabled)
        #expect(!policies.isAnythingEnabled)
        #expect(policies.enabled.isEmpty)
    }

    @Test("Only enabled signals on a timer are reported as polling")
    func pollingExcludesDisabledAndOnDemand() {
        var policies = LoggingPolicies()
        policies["device.battery"] = LoggingPolicy(isEnabled: true, capture: .interval(seconds: 60))
        policies["device.thermal"] = LoggingPolicy(isEnabled: true, capture: .onDemand)
        policies["device.locale"] = LoggingPolicy(isEnabled: false, capture: .interval(seconds: 60))

        #expect(policies.polling.map(\.id) == ["device.battery"])
        #expect(policies.polling.first?.seconds == 60)
        #expect(policies.enabled.count == 2)
    }

    @Test("Retention converts to a cutoff, and forever has none")
    func retentionCutoffs() {
        #expect(Retention.hours(1).cutoff(now: 10_000) == 6_400)
        #expect(Retention.days(1).cutoff(now: 100_000) == 13_600)
        #expect(Retention.forever.cutoff(now: 10_000) == nil)
    }

    @Test("Policies survive a Codable round trip")
    func codableRoundTrip() throws {
        var policies = LoggingPolicies()
        policies["device.battery"] = LoggingPolicy(
            isEnabled: true, capture: .interval(seconds: 300),
            retention: .days(30), allowBackground: true
        )
        let data = try JSONEncoder().encode(policies)
        let decoded = try JSONDecoder().decode(LoggingPolicies.self, from: data)
        #expect(decoded == policies)
        #expect(decoded["device.battery"].capture.seconds == 300)
    }
}

@Suite("Logging schedule")
struct LoggingPlanTests {
    private func plan(_ entries: [(SensorID, Int)]) -> LoggingPlan {
        var policies = LoggingPolicies()
        for (id, seconds) in entries {
            policies[id] = LoggingPolicy(isEnabled: true, capture: .interval(seconds: seconds))
        }
        return LoggingPlan(policies: policies)
    }

    @Test("A signal never read before is due immediately")
    func firstReadIsImmediate() {
        // Switching logging on should produce a point now, not after a silent
        // interval that reads as the feature being broken.
        let due = plan([("device.battery", 3600)]).due(at: 1000, lastRead: [:])
        #expect(due == ["device.battery"])
    }

    @Test("A signal read recently is not due again")
    func respectsTheInterval() {
        let due = plan([("device.battery", 60)]).due(at: 1030, lastRead: ["device.battery": 1000])
        #expect(due.isEmpty)
    }

    @Test("A signal is due once its interval has elapsed")
    func dueAfterInterval() {
        let due = plan([("device.battery", 60)]).due(at: 1060, lastRead: ["device.battery": 1000])
        #expect(due == ["device.battery"])
    }

    @Test("On-demand and disabled signals are never due")
    func onlyPollingSignalsAreDue() {
        var policies = LoggingPolicies()
        policies["device.battery"] = LoggingPolicy(isEnabled: true, capture: .onDemand)
        policies["device.thermal"] = LoggingPolicy(isEnabled: false, capture: .interval(seconds: 1))
        #expect(LoggingPlan(policies: policies).due(at: 9999, lastRead: [:]).isEmpty)
    }

    @Test("The next wake is the soonest signal, and never under a second")
    func nextWake() {
        let subject = plan([("device.battery", 60), ("device.thermal", 300)])
        let last: [SensorID: Double] = ["device.battery": 1000, "device.thermal": 1000]

        #expect(subject.secondsUntilNextDue(at: 1030, lastRead: last) == 30)
        // Overdue signals must not produce a zero-second timer that spins.
        #expect(subject.secondsUntilNextDue(at: 9999, lastRead: last) == 1)
        #expect(LoggingPlan(policies: LoggingPolicies()).secondsUntilNextDue(at: 0, lastRead: [:]) == nil)
    }

    @Test("Retention work covers on-demand signals too, but not indefinite ones")
    func retentionWork() {
        var policies = LoggingPolicies()
        policies["device.battery"] = LoggingPolicy(isEnabled: true, capture: .onDemand, retention: .days(7))
        policies["device.thermal"] = LoggingPolicy(isEnabled: true, capture: .onDemand, retention: .forever)
        policies["device.locale"] = LoggingPolicy(isEnabled: false, retention: .days(1))

        let work = LoggingPlan(policies: policies).retentionWork
        #expect(work.map(\.id) == ["device.battery"])
    }
}

@Suite("Featured charts")
struct ChartableSignalsTests {
    @Test("Every featured signal exists in the ledger")
    func featuredSignalsAreReal() {
        for entry in ChartableSignals.featured {
            #expect(CapabilityLedger[entry.sensor] != nil, "\(entry.sensor) is not in the ledger")
        }
    }

    @Test("Every featured signal explains what its shape means")
    func featuredSignalsExplainThemselves() {
        for entry in ChartableSignals.featured {
            #expect(entry.reading.count > 40, "\(entry.sensor) has no explanation worth reading")
        }
    }

    @Test("Lookup finds featured signals and rejects others")
    func lookup() {
        #expect(ChartableSignals.isFeatured("device.battery"))
        #expect(!ChartableSignals.isFeatured("contacts.all"))
        #expect(ChartableSignals.featured(for: "device.battery")?.field == "Level")
    }
}

@Suite("Heading rose")
struct HeadingRoseTests {
    @Test("Due north lands in the first sector, from either side of the wrap")
    func northWrapsCorrectly() {
        // The bug this guards: 359° and 1° are two degrees apart, and a naive
        // binning puts them in opposite sectors on the far side of the chart.
        let sectors = HeadingRose.bin([0, 1, 359, 358])
        #expect(sectors[0].count == 4)
        #expect(sectors[0].label == "N")
    }

    @Test("Cardinal directions land in their own sectors")
    func cardinals() {
        let sectors = HeadingRose.bin([0, 90, 180, 270])
        #expect(sectors.filter { $0.count > 0 }.map(\.label).sorted() == ["E", "N", "S", "W"])
    }

    @Test("Shares sum to one, and are zero for an empty rose")
    func shares() {
        let sectors = HeadingRose.bin([0, 0, 90, 180])
        #expect(abs(sectors.reduce(0) { $0 + $1.share } - 1.0) < 0.0001)
        #expect(sectors[0].share == 0.5)

        #expect(HeadingRose.bin([]).allSatisfy { $0.share == 0 })
    }

    @Test("Out-of-range and non-finite headings are handled, not dropped or crashed")
    func handlesOddInput() {
        // A negative or over-wound heading should still land somewhere.
        #expect(HeadingRose.bin([-90]).first { $0.label == "W" }?.count == 1)
        #expect(HeadingRose.bin([450]).first { $0.label == "E" }?.count == 1)
        // NaN has no sector and must not corrupt the totals.
        #expect(HeadingRose.bin([.nan, 0]).reduce(0) { $0 + $1.count } == 1)
    }

    @Test("Sector count is configurable and labelled where it makes sense")
    func sectorCounts() {
        #expect(HeadingRose.bin([0], sectors: 16).count == 16)
        #expect(HeadingRose.bin([0], sectors: 8).count == 8)
        #expect(HeadingRose.bin([0], sectors: 4).map(\.label) == ["N", "E", "S", "W"])
    }

    @Test("Two opposing spikes stay opposing")
    func aStreetHasTwoDirections() {
        // Walking a street both ways should show as two spikes 180° apart,
        // which is the shape that makes this chart worth having.
        let sectors = HeadingRose.bin(Array(repeating: 45.0, count: 10) + Array(repeating: 225.0, count: 10))
        let busiest = sectors.filter { $0.count > 0 }
        #expect(busiest.count == 2)
        #expect(abs(busiest[0].centre - busiest[1].centre) == 180)
    }
}
