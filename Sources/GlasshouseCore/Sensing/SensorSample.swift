/// One reading from one sensor, at one moment.
///
/// Readings are uniform rather than strongly typed per sensor, because this app
/// displays values rather than computing on them. A single shape means the UI,
/// the replay format, and the eventual export all handle every sensor the same
/// way, and adding a sensor requires no new rendering code.
public struct SensorSample: Sendable, Hashable, Codable {
    public let sensor: SensorID

    /// Seconds since 1970. A plain `Double` rather than `Foundation.Date` so
    /// that fakes and replays are exactly reproducible.
    public let timestamp: Double

    public let fields: [SensorField]

    public init(sensor: SensorID, timestamp: Double, fields: [SensorField]) {
        self.sensor = sensor
        self.timestamp = timestamp
        self.fields = fields
    }

    public subscript(label: String) -> FieldValue? {
        fields.first { $0.label == label }?.value
    }
}

/// One labelled value within a reading.
public struct SensorField: Sendable, Hashable, Codable {
    public let label: String
    public let value: FieldValue

    public init(_ label: String, _ value: FieldValue) {
        self.label = label
        self.value = value
    }
}

/// The value types a sensor can report.
///
/// Deliberately small. Anything a sensor produces has to be expressible here,
/// which keeps sensors from smuggling in bespoke rendering requirements.
public enum FieldValue: Sendable, Hashable, Codable {
    case number(Double, unit: String? = nil)
    case integer(Int, unit: String? = nil)
    case text(String)
    case boolean(Bool)

    /// Latitude and longitude in degrees. Separate from `number` because
    /// coordinates need distinct formatting, distinct redaction rules, and are
    /// the single most sensitive shape of value in the app.
    case coordinate(latitude: Double, longitude: Double)

    /// Seconds since 1970, for values that are themselves times.
    case time(Double)

    /// A rendering-neutral description. Formatting for display is the UI's job;
    /// this exists for logs, tests, and diffs.
    public var plainDescription: String {
        switch self {
        case let .number(value, unit):
            unit.map { "\(value) \($0)" } ?? "\(value)"
        case let .integer(value, unit):
            unit.map { "\(value) \($0)" } ?? "\(value)"
        case let .text(value):
            value
        case let .boolean(value):
            value ? "yes" : "no"
        case let .coordinate(latitude, longitude):
            "\(latitude), \(longitude)"
        case let .time(value):
            "t=\(value)"
        }
    }

    /// Whether this value is precise enough to identify a place or a person on
    /// its own. Drives redaction defaults, and matters a great deal in Phase 2.
    public var isPrecise: Bool {
        if case .coordinate = self { return true }
        return false
    }
}
