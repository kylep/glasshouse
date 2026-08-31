/// A plain calendar date, used to record when a ledger claim was last verified.
///
/// Deliberately not `Foundation.Date`: this is a civil date with no time zone,
/// no time component, and no ambiguity. It is written in source as a string
/// literal (`"2026-08-30"`) and compared by day count, so staleness checks are
/// exact and testable without a `Calendar`.
public struct LedgerDate: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`. Returns nil on anything else.
    ///
    /// Deliberately labelled rather than `init?(_:)`: an unlabelled failable
    /// initializer would sit alongside the `ExpressibleByStringLiteral` one, and
    /// `LedgerDate("2026-02-30")` would silently pick the *trapping* literal
    /// overload instead of returning nil.
    public init?(parsing text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m),
              (1...LedgerDate.daysInMonth(year: y, month: m)).contains(d)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var description: String {
        let m = month < 10 ? "0\(month)" : "\(month)"
        let d = day < 10 ? "0\(day)" : "\(day)"
        return "\(year)-\(m)-\(d)"
    }

    // MARK: - Day arithmetic

    /// Days since 1970-01-01. Howard Hinnant's `days_from_civil`: exact for all
    /// proleptic Gregorian dates, and simple enough to verify by inspection.
    public var daysSinceEpoch: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                        // [0, 399]
        let mp = (month + 9) % 12                                      // Mar = 0
        let doy = (153 * mp + 2) / 5 + day - 1                         // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy                // [0, 146096]
        return era * 146_097 + doe - 719_468
    }

    /// Whole days from this date to `other`. Negative if `other` is earlier.
    public func days(to other: LedgerDate) -> Int {
        other.daysSinceEpoch - daysSinceEpoch
    }

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        case 2: isLeapYear(year) ? 29 : 28
        default: 0
        }
    }

    public static func < (lhs: LedgerDate, rhs: LedgerDate) -> Bool {
        lhs.daysSinceEpoch < rhs.daysSinceEpoch
    }
}

extension LedgerDate: ExpressibleByStringLiteral {
    /// Traps on a malformed literal. That is intended: the ledger is source
    /// code, so a bad date should fail loudly at authoring time rather than
    /// quietly become a default.
    public init(stringLiteral value: String) {
        guard let parsed = LedgerDate(parsing: value) else {
            preconditionFailure("Malformed ledger date '\(value)' — expected YYYY-MM-DD")
        }
        self = parsed
    }
}

extension LedgerDate: Codable {
    /// Encoded as `"YYYY-MM-DD"` rather than as three fields, so the JSON export
    /// reads the same way the source does.
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = LedgerDate(parsing: text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Malformed ledger date '\(text)' — expected YYYY-MM-DD")
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
