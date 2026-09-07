/// One sensor's last known state, in a form that survives a relaunch.
///
/// Exists so the app can paint something the instant it opens rather than a
/// blank list and a spinner — reading every capability takes seconds, and the
/// Bluetooth scan alone accounts for four of them.
///
/// Stores only what cannot be recomputed. The `Capability` is not persisted,
/// because it comes from the ledger in code: caching it would mean a stale
/// build's descriptions outliving the ledger that replaced them.
public struct CachedReading: Sendable, Hashable, Codable {
    public let sensor: SensorID
    public let availability: RecordedAvailability
    public let sample: SensorSample?

    public init(sensor: SensorID, availability: RecordedAvailability, sample: SensorSample?) {
        self.sensor = sensor
        self.availability = availability
        self.sample = sample
    }

    public init(_ snapshot: SensorSnapshot) {
        self.sensor = snapshot.capability.id
        self.availability = RecordedAvailability(snapshot.availability)
        self.sample = snapshot.sample
    }

    /// Rebuilds a snapshot, or nil if the ledger no longer has this sensor.
    ///
    /// Dropping unknown rows is deliberate: a capability removed from the
    /// ledger should vanish from the app on the next launch, not linger because
    /// an old cache remembers it.
    public var snapshot: SensorSnapshot? {
        guard let capability = CapabilityLedger[sensor] else { return nil }
        return SensorSnapshot(
            capability: capability,
            availability: availability.live,
            sample: sample
        )
    }
}

/// A whole set of readings, with when they were taken.
public struct ReadingCache: Sendable, Hashable, Codable {
    /// Seconds since 1970.
    public let capturedAt: Double
    public let readings: [CachedReading]

    public init(capturedAt: Double, readings: [CachedReading]) {
        self.capturedAt = capturedAt
        self.readings = readings
    }

    public init(_ snapshots: [SensorSnapshot], at capturedAt: Double) {
        self.capturedAt = capturedAt
        self.readings = snapshots.map(CachedReading.init)
    }

    /// Snapshots the ledger still recognises, in stable order.
    public var snapshots: [SensorSnapshot] {
        readings.compactMap(\.snapshot).sorted { $0.capability.id < $1.capability.id }
    }

    /// How old this is, in seconds, as of `now`.
    public func age(asOf now: Double) -> Double {
        max(0, now - capturedAt)
    }

    /// Whether this is too old to be worth showing even as a placeholder.
    ///
    /// A day-old battery level is not informative, it is misleading — and the
    /// point of the cache is a fast first paint, not a history.
    public func isStale(asOf now: Double, limit: Double = 86_400) -> Bool {
        age(asOf: now) > limit
    }
}
