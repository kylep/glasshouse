import Foundation
import SQLite3

/// The on-device store of recorded readings.
///
/// SQLite, reached through the system library, so this adds nothing to the
/// app's dependency surface. Time series is what SQLite is good at: append-
/// heavy writes, range scans over an indexed timestamp, and retention
/// expressible as one DELETE rather than application code.
///
/// **One database file per sensitivity class.** That is not tidiness. Intimate
/// readings — health, precise location, reproductive records — live in a file
/// the rest of the app never opens, so a future export or AI feature can be
/// handed a connection that *cannot* see them. A `WHERE sensitivity != …`
/// clause is one bug away from leaking; a file you never opened is not.
public final class SignalLog: @unchecked Sendable {
    /// SQLite's own sentinel for "copy this string, I may free it".
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var handle: OpaquePointer?
    private let lock = NSLock()
    public let sensitivity: Sensitivity
    public let url: URL

    public init(sensitivity: Sensitivity, directory: URL) throws {
        self.sensitivity = sensitivity
        self.url = directory.appendingPathComponent("signals-\(sensitivity.rawValue).sqlite")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard sqlite3_open_v2(
            url.path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil
        ) == SQLITE_OK else {
            throw LogError.couldNotOpen(String(cString: sqlite3_errmsg(handle)))
        }

        // WAL lets a read run while a write is in flight, which is what keeps a
        // chart query from blocking the poller.
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try createSchema()
    }

    deinit { sqlite3_close_v2(handle) }

    public enum LogError: Error, CustomStringConvertible {
        case couldNotOpen(String)
        case statementFailed(String)

        public var description: String {
            switch self {
            case let .couldNotOpen(message): "Could not open the log: \(message)"
            case let .statementFailed(message): "Statement failed: \(message)"
            }
        }
    }

    // MARK: - Schema

    private func createSchema() throws {
        // Narrow rather than a column per metric, because readings are
        // heterogeneous — fields differ per sensor, and several sensors report
        // fields that did not exist when this was written.
        try execute("""
            CREATE TABLE IF NOT EXISTS samples (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                sensor    TEXT NOT NULL,
                taken_at  REAL NOT NULL
            );
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS fields (
                sample_id INTEGER NOT NULL REFERENCES samples(id) ON DELETE CASCADE,
                label     TEXT NOT NULL,
                numeric   REAL,
                text      TEXT,
                unit      TEXT
            );
            """)
        // The index every query this app makes will use: one sensor, ordered by
        // time. Without it, retention and charting both degrade to table scans.
        try execute("CREATE INDEX IF NOT EXISTS samples_by_sensor_time ON samples(sensor, taken_at);")
        try execute("CREATE INDEX IF NOT EXISTS fields_by_sample ON fields(sample_id);")
    }

    // MARK: - Writing

    /// Records one reading. Fields are written in the same transaction as the
    /// sample, so a crash cannot leave a sample with no values.
    public func append(_ sample: SensorSample) throws {
        lock.lock()
        defer { lock.unlock() }

        try execute("BEGIN IMMEDIATE;")
        do {
            try run("INSERT INTO samples (sensor, taken_at) VALUES (?, ?);") { statement in
                sqlite3_bind_text(statement, 1, sample.sensor.rawValue, -1, Self.transient)
                sqlite3_bind_double(statement, 2, sample.timestamp)
            }
            let sampleID = sqlite3_last_insert_rowid(handle)

            for field in sample.fields {
                try run("INSERT INTO fields (sample_id, label, numeric, text, unit) VALUES (?, ?, ?, ?, ?);") { statement in
                    sqlite3_bind_int64(statement, 1, sampleID)
                    sqlite3_bind_text(statement, 2, field.label, -1, Self.transient)
                    switch field.value.storable {
                    case let (numeric?, text, unit):
                        sqlite3_bind_double(statement, 3, numeric)
                        self.bind(statement, 4, text)
                        self.bind(statement, 5, unit)
                    case let (nil, text, unit):
                        sqlite3_bind_null(statement, 3)
                        self.bind(statement, 4, text)
                        self.bind(statement, 5, unit)
                    }
                }
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, Self.transient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    // MARK: - Reading

    /// Numeric values for one field of one sensor, oldest first.
    ///
    /// The shape a chart needs, and deliberately the only query offered — a
    /// general query interface would be an invitation to read more than the
    /// screen is showing.
    public func series(
        sensor: SensorID,
        field: String,
        since: Double? = nil,
        limit: Int = 5000
    ) throws -> [(at: Double, value: Double)] {
        lock.lock()
        defer { lock.unlock() }

        var points: [(at: Double, value: Double)] = []
        try run("""
            SELECT samples.taken_at, fields.numeric
              FROM fields JOIN samples ON samples.id = fields.sample_id
             WHERE samples.sensor = ? AND fields.label = ? AND fields.numeric IS NOT NULL
               AND samples.taken_at >= ?
             ORDER BY samples.taken_at ASC
             LIMIT ?;
            """,
            bind: { statement in
                sqlite3_bind_text(statement, 1, sensor.rawValue, -1, Self.transient)
                sqlite3_bind_text(statement, 2, field, -1, Self.transient)
                sqlite3_bind_double(statement, 3, since ?? 0)
                sqlite3_bind_int(statement, 4, Int32(limit))
            },
            step: { statement in
                points.append((sqlite3_column_double(statement, 0),
                               sqlite3_column_double(statement, 1)))
            })
        return points
    }

    /// How many readings are stored for a sensor.
    public func count(sensor: SensorID) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        var total = 0
        try run("SELECT COUNT(*) FROM samples WHERE sensor = ?;",
                bind: { sqlite3_bind_text($0, 1, sensor.rawValue, -1, Self.transient) },
                step: { total = Int(sqlite3_column_int64($0, 0)) })
        return total
    }

    /// Which numeric fields a sensor has recorded, for offering chart choices.
    public func numericFields(sensor: SensorID) throws -> [String] {
        lock.lock()
        defer { lock.unlock() }

        var labels: [String] = []
        try run("""
            SELECT DISTINCT fields.label
              FROM fields JOIN samples ON samples.id = fields.sample_id
             WHERE samples.sensor = ? AND fields.numeric IS NOT NULL
             ORDER BY fields.label;
            """,
            bind: { sqlite3_bind_text($0, 1, sensor.rawValue, -1, Self.transient) },
            step: { statement in
                if let text = sqlite3_column_text(statement, 0) {
                    labels.append(String(cString: text))
                }
            })
        return labels
    }

    // MARK: - Retention

    /// Deletes readings for one sensor older than its retention allows.
    ///
    /// Returns how many samples went, so the caller can say so rather than
    /// deleting a person's data silently.
    @discardableResult
    public func enforce(_ retention: Retention, on sensor: SensorID, now: Double) throws -> Int {
        guard let cutoff = retention.cutoff(now: now) else { return 0 }

        lock.lock()
        defer { lock.unlock() }

        var removed = 0
        try run("SELECT COUNT(*) FROM samples WHERE sensor = ? AND taken_at < ?;",
                bind: { statement in
                    sqlite3_bind_text(statement, 1, sensor.rawValue, -1, Self.transient)
                    sqlite3_bind_double(statement, 2, cutoff)
                },
                step: { removed = Int(sqlite3_column_int64($0, 0)) })
        guard removed > 0 else { return 0 }

        // Fields go first: the schema declares ON DELETE CASCADE, but foreign
        // keys are off by default in SQLite and enabling them per-connection is
        // easy to forget. Deleting explicitly does not rely on that.
        try run("""
            DELETE FROM fields WHERE sample_id IN
                (SELECT id FROM samples WHERE sensor = ? AND taken_at < ?);
            """,
            bind: { statement in
                sqlite3_bind_text(statement, 1, sensor.rawValue, -1, Self.transient)
                sqlite3_bind_double(statement, 2, cutoff)
            })
        try run("DELETE FROM samples WHERE sensor = ? AND taken_at < ?;",
                bind: { statement in
                    sqlite3_bind_text(statement, 1, sensor.rawValue, -1, Self.transient)
                    sqlite3_bind_double(statement, 2, cutoff)
                })
        return removed
    }

    /// Removes everything recorded for one sensor.
    @discardableResult
    public func deleteAll(sensor: SensorID) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        var removed = 0
        try run("SELECT COUNT(*) FROM samples WHERE sensor = ?;",
                bind: { sqlite3_bind_text($0, 1, sensor.rawValue, -1, Self.transient) },
                step: { removed = Int(sqlite3_column_int64($0, 0)) })

        try run("DELETE FROM fields WHERE sample_id IN (SELECT id FROM samples WHERE sensor = ?);",
                bind: { sqlite3_bind_text($0, 1, sensor.rawValue, -1, Self.transient) })
        try run("DELETE FROM samples WHERE sensor = ?;",
                bind: { sqlite3_bind_text($0, 1, sensor.rawValue, -1, Self.transient) })
        return removed
    }

    // MARK: - Statement plumbing

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw LogError.statementFailed(message)
        }
    }

    private func run(
        _ sql: String,
        bind: ((OpaquePointer?) -> Void)? = nil,
        step: ((OpaquePointer?) -> Void)? = nil
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw LogError.statementFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        bind?(statement)

        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: step?(statement)
            case SQLITE_DONE: return
            default: throw LogError.statementFailed(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }
}

extension FieldValue {
    /// Flattened for storage: a number, a string, and a unit.
    var storable: (numeric: Double?, text: String?, unit: String?) {
        switch self {
        case let .number(value, unit): (value, nil, unit)
        case let .integer(value, unit): (Double(value), nil, unit)
        case let .text(value): (nil, value, nil)
        case let .boolean(value): (value ? 1 : 0, value ? "yes" : "no", nil)
        // Stored as text rather than two numbers: a coordinate is one value,
        // and splitting it would let a query read latitude without longitude,
        // which is a shape this app should not make easy.
        case let .coordinate(latitude, longitude): (nil, "\(latitude),\(longitude)", "coordinate")
        case let .time(seconds): (seconds, nil, "epoch")
        }
    }
}
