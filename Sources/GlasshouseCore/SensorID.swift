/// Stable identifier for one sensor or data source.
///
/// Values are dotted paths grouped by framework, e.g. `core_motion.accelerometer`
/// or `photos.asset_location`. The identifier is the join key between the
/// capability ledger, the sensor registry, and the generated documentation, so
/// it must never change once a sensor ships.
public struct SensorID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The framework group this sensor belongs to, i.e. everything before the first dot.
    public var group: String {
        String(rawValue.prefix { $0 != "." })
    }
}

extension SensorID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

extension SensorID: CustomStringConvertible {
    public var description: String { rawValue }
}

extension SensorID: Comparable {
    public static func < (lhs: SensorID, rhs: SensorID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
