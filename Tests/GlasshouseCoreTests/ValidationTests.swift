import Testing
@testable import GlasshouseCore

@Suite("Reading validation")
struct ReadingValidationTests {
    private func sample(_ fields: [SensorField], from sensor: SensorID = "device.battery") -> SensorSample {
        SensorSample(sensor: sensor, timestamp: 1_756_598_400, fields: fields)
    }

    @Test("A plausible reading has no problems")
    func plausibleReadingPasses() {
        let good = sample([
            SensorField("Level", .number(84, unit: "%")),
            SensorField("State", .text("charging")),
            SensorField("Charging", .boolean(true)),
        ])
        #expect(ReadingValidation.problems(in: good).isEmpty)
    }

    @Test("A missing unit conversion is caught")
    func catchesAFactorOfOneHundred() {
        // What `batteryLevel` looks like when someone forgets it is 0...1 and
        // multiplies twice. A shape test cannot tell this from 84%.
        let wrong = sample([SensorField("Level", .number(8400, unit: "%"))])
        let problems = ReadingValidation.problems(in: wrong)
        #expect(problems.count == 1)
        #expect(problems[0].field == "Level")
    }

    @Test("Impossible physics is caught", arguments: [
        ("g", 400.0),          // no phone survives 400g
        ("kPa", 0.5),          // vacuum
        ("dBFS", 40.0),        // above full scale
        ("bpm", 900.0),        // not a heart
    ])
    func catchesImpossiblePhysics(unit: String, value: Double) {
        let wrong = sample([SensorField("Reading", .number(value, unit: unit))])
        #expect(!ReadingValidation.problems(in: wrong).isEmpty)
    }

    @Test("Real physical values pass", arguments: [
        ("g", 1.0),            // gravity
        ("g", -0.98),          // gravity, other way up
        ("kPa", 101.3),        // sea level
        ("µT", 48.0),          // Earth's magnetic field
        ("dBFS", -47.0),       // a quiet room
        ("bpm", 62.0),         // a resting heart
    ])
    func acceptsRealValues(unit: String, value: Double) {
        let fine = sample([SensorField("Reading", .number(value, unit: unit))])
        #expect(ReadingValidation.problems(in: fine).isEmpty)
    }

    @Test("NaN and infinity are rejected before any range is consulted")
    func rejectsNonFinite() {
        // These satisfy every comparison a range check makes, so they must be
        // excluded explicitly or they pass silently.
        for value in [Double.nan, .infinity, -.infinity] {
            let broken = sample([SensorField("Level", .number(value, unit: "%"))])
            #expect(ReadingValidation.problems(in: broken).count == 1)
        }
    }

    @Test("An unknown unit is not policed")
    func unknownUnitsPass() {
        // Better to check nothing than to invent a range and reject real data.
        let odd = sample([SensorField("Reading", .number(99_999, unit: "furlongs"))])
        #expect(ReadingValidation.problems(in: odd).isEmpty)
    }

    @Test("Coordinates off the Earth are caught")
    func catchesImpossibleCoordinates() {
        let wrong = sample([
            SensorField("Where", .coordinate(latitude: 143.2, longitude: -79.4)),
        ], from: "core_location.position")
        #expect(ReadingValidation.problems(in: wrong).count == 1)

        let sentinel = sample([
            // The simulator's own no-GPS marker, which must never be treated
            // as a real place.
            SensorField("Where", .coordinate(latitude: -180, longitude: -180)),
        ], from: "core_location.position")
        #expect(!ReadingValidation.problems(in: sentinel).isEmpty)
    }

    @Test("A real coordinate passes")
    func acceptsRealCoordinates() {
        let toronto = sample([
            SensorField("Where", .coordinate(latitude: 43.6532, longitude: -79.3832)),
        ], from: "core_location.position")
        #expect(ReadingValidation.problems(in: toronto).isEmpty)
    }

    @Test("Milliseconds mistaken for seconds is caught")
    func catchesTimestampUnitMistakes() {
        // The classic: a timestamp 1000× too large lands in the year 57000.
        let wrong = sample([SensorField("Taken", .time(1_756_598_400_000))])
        #expect(ReadingValidation.problems(in: wrong).count == 1)

        let right = sample([SensorField("Taken", .time(1_756_598_400))])
        #expect(ReadingValidation.problems(in: right).isEmpty)
    }

    @Test("Negative counts are caught")
    func catchesNegativeCounts() {
        // -1 is what UIDevice.batteryLevel returns when it does not know, and
        // it must never reach a reading as though it were a count.
        let wrong = sample([SensorField("Devices heard", .integer(-1))])
        #expect(ReadingValidation.problems(in: wrong).count == 1)
    }

    @Test("A whole sweep is checked, and problems name their sensor")
    func checksAcrossSnapshots() throws {
        let capability = try #require(CapabilityLedger["device.battery"])
        let snapshot = SensorSnapshot(
            capability: capability,
            availability: .ready,
            sample: sample([SensorField("Level", .number(-5, unit: "%"))])
        )
        let problems = ReadingValidation.problems(in: [snapshot])
        #expect(problems.count == 1)
        #expect(problems[0].sensor == "device.battery")
        #expect(problems[0].description.contains("device.battery.Level"))
    }
}
