/// Checks that a reading could plausibly be true.
///
/// Every test in this project until now asserted *shape* — that a sensor
/// returned the right number of fields, of the right type. None asserted that
/// the values could be real. A battery reporting 8400% and one reporting 84%
/// are indistinguishable to a shape test, and the first is what a missing
/// unit conversion looks like.
///
/// This app mixes percentages, g-forces, microteslas, kilopascals, decibels,
/// degrees and metres, so a misplaced factor of 100 is the single most likely
/// defect. Physics supplies the ground truth: gravity is 1g, sea-level
/// pressure is about 101 kPa, a latitude cannot exceed 90.
public enum ReadingValidation {
    /// Something in a reading that cannot be true.
    public struct Problem: Sendable, Hashable {
        public let sensor: SensorID
        public let field: String
        public let value: String
        public let expectation: String

        public var description: String {
            "\(sensor).\(field) = \(value) — expected \(expectation)"
        }
    }

    /// A plausible range for a value, with a note on why.
    struct Range: Sendable {
        let low: Double
        let high: Double
        let because: String

        func admits(_ value: Double) -> Bool { value >= low && value <= high }
        var described: String { "\(low)…\(high) (\(because))" }
    }

    /// Ranges keyed by unit. Deliberately generous — the aim is catching an
    /// order-of-magnitude mistake, not policing the last decimal.
    static let byUnit: [String: Range] = [
        "%": Range(low: 0, high: 100, because: "a percentage"),
        "g": Range(low: -16, high: 16, because: "iPhone accelerometers saturate around ±16g"),
        "rad/s": Range(low: -35, high: 35, because: "gyroscope full scale"),
        "µT": Range(low: -2000, high: 2000, because: "Earth's field is ~50µT; magnets exceed it"),
        "kPa": Range(low: 30, high: 120, because: "sea level is ~101kPa; 30 is above Everest"),
        "dBFS": Range(low: -160, high: 0, because: "0 is full scale by definition"),
        "°": Range(low: -360, high: 360, because: "a bearing or angle"),
        "bpm": Range(low: 20, high: 250, because: "survivable heart rate"),
        "hours": Range(low: 0, high: 87_600, because: "uptime under ten years"),
        "GB": Range(low: 0, high: 100_000, because: "storage in gigabytes"),
    ]

    /// Checks one sample and returns everything implausible about it.
    public static func problems(in sample: SensorSample) -> [Problem] {
        var found: [Problem] = []

        for field in sample.fields {
            switch field.value {
            case let .number(value, unit):
                // NaN and infinity pass every range check ever written, so
                // they are rejected before the ranges are consulted.
                if !value.isFinite {
                    found.append(Problem(sensor: sample.sensor, field: field.label,
                                         value: "\(value)", expectation: "a finite number"))
                    continue
                }
                if let unit, let range = byUnit[unit], !range.admits(value) {
                    found.append(Problem(sensor: sample.sensor, field: field.label,
                                         value: "\(value) \(unit)", expectation: range.described))
                }

            case let .integer(value, _):
                if value < 0 {
                    // Every integer this app reports is a count or a level.
                    found.append(Problem(sensor: sample.sensor, field: field.label,
                                         value: "\(value)", expectation: "not negative"))
                }

            case let .coordinate(latitude, longitude):
                if !(-90...90).contains(latitude) || !(-180...180).contains(longitude) {
                    found.append(Problem(sensor: sample.sensor, field: field.label,
                                         value: "\(latitude), \(longitude)",
                                         expectation: "a real place on Earth"))
                }

            case let .time(seconds):
                // A timestamp before 2001 or far in the future is a unit
                // mistake — milliseconds mistaken for seconds, or the reverse.
                if seconds < 978_307_200 || seconds > 4_102_444_800 {
                    found.append(Problem(sensor: sample.sensor, field: field.label,
                                         value: "\(seconds)",
                                         expectation: "seconds since 1970, this century"))
                }

            case .text, .boolean:
                continue
            }
        }

        return found
    }

    /// Checks a whole sweep.
    public static func problems(in snapshots: [SensorSnapshot]) -> [Problem] {
        snapshots.compactMap(\.sample).flatMap(problems(in:))
    }
}
