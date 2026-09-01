/// A recording of what one sensor actually reported, over time.
///
/// The third implementation the architecture always described and never had.
/// Live adapters need hardware; fakes are invented. A trace is neither: it is
/// what a real sensor really did, captured once and replayable forever.
///
/// That matters for three things this project could not otherwise do:
///
/// - **Demonstrate the app without a phone.** Most sensors report nothing in a
///   Simulator, so the UI could only ever be shown against invented values.
/// - **Regression-test against reality.** A fake asserts what someone thought
///   a sensor does; a trace asserts what one did.
/// - **Keep a record.** Sensor behaviour changes between iOS versions, and a
///   trace from today is evidence about today.
///
/// Traces are personal data — a location trace is a record of where someone
/// was. `.gitignore` excludes captures for that reason, and only synthetic or
/// hand-authored traces belong in the repository.
public struct SensorTrace: Sendable, Hashable, Codable, Identifiable {
    public var id: SensorID { sensor }

    public let sensor: SensorID

    /// Where this was recorded. A trace from a Simulator says something very
    /// different from one taken on a phone, and conflating them would make the
    /// replay lie about its own provenance.
    public let recordedOn: RuntimeEnvironment

    /// When recording started, seconds since 1970.
    public let recordedAt: Double

    /// What the sensor said about itself while being recorded.
    public let availability: RecordedAvailability

    /// The samples, in the order they arrived.
    public let samples: [SensorSample]

    /// Free text about the conditions — "walking upstairs", "phone face down".
    /// Without it a trace of accelerometer numbers is unreadable six months on.
    public let notes: String?

    public init(
        sensor: SensorID,
        recordedOn: RuntimeEnvironment,
        recordedAt: Double,
        availability: RecordedAvailability,
        samples: [SensorSample],
        notes: String? = nil
    ) {
        self.sensor = sensor
        self.recordedOn = recordedOn
        self.recordedAt = recordedAt
        self.availability = availability
        self.samples = samples
        self.notes = notes
    }

    public var isEmpty: Bool { samples.isEmpty }

    /// How long the recording covers, from first sample to last.
    public var duration: Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return last.timestamp - first.timestamp
    }
}

/// `SensorAvailability` flattened for storage.
///
/// The live type carries an associated value, which makes its `Codable`
/// synthesis awkward and its JSON ugly. Traces outlive the code that wrote
/// them, so their format is kept deliberately dull.
public enum RecordedAvailability: String, Sendable, Hashable, Codable {
    case ready
    case limited
    case needsPermission = "needs_permission"
    case denied
    case restricted
    case unavailable
    case notImplemented = "not_implemented"

    public init(_ availability: SensorAvailability) {
        self = switch availability {
        case .ready: .ready
        case .limited: .limited
        case .needsPermission: .needsPermission
        case .denied: .denied
        case .restricted: .restricted
        case .unavailable: .unavailable
        case .notImplemented: .notImplemented
        }
    }

    /// Rebuilds a live value. An unavailable trace replays as unavailable in a
    /// Simulator, because that is the honest reason there — the original cause
    /// is not preserved, and inventing one would be worse than being vague.
    public var live: SensorAvailability {
        switch self {
        case .ready: .ready
        case .limited: .limited
        case .needsPermission: .needsPermission
        case .denied: .denied
        case .restricted: .restricted
        case .unavailable: .unavailable(reason: .simulator)
        case .notImplemented: .notImplemented
        }
    }
}

/// Plays a recorded trace back as though it were a live sensor.
///
/// Deterministic and stateless between reads: the same index always yields the
/// same sample. Advancing is explicit rather than time-based, so a test can
/// step through a trace without sleeping and the UI can drive it from a timer.
public struct ReplaySensorSource: SensorSource {
    public let id: SensorID
    private let trace: SensorTrace
    private let index: Int

    public init(_ trace: SensorTrace, at index: Int = 0) {
        self.id = trace.sensor
        self.trace = trace
        self.index = index
    }

    public func availability() async -> SensorAvailability {
        trace.availability.live
    }

    public func read() async -> SensorSample? {
        guard !trace.samples.isEmpty else { return nil }
        // Wraps rather than running out. A trace is a loop of plausible
        // behaviour, and stopping after N reads would make the UI go silent
        // for no reason a viewer could understand.
        return trace.samples[index % trace.samples.count]
    }

    /// The same trace positioned at the next sample.
    public func advanced() -> ReplaySensorSource {
        ReplaySensorSource(trace, at: index + 1)
    }

    /// How far through the recording this is, 0...1. Zero for a single-sample
    /// trace, which has no progression to report.
    public var progress: Double {
        guard trace.samples.count > 1 else { return 0 }
        return Double(index % trace.samples.count) / Double(trace.samples.count - 1)
    }
}

/// Captures what a live sensor reports, into a replayable trace.
///
/// Deliberately a plain value rather than something that owns a timer: the
/// caller decides when to sample, which keeps recording deterministic in tests
/// and lets the app record on its own refresh cycle rather than a second one.
public struct TraceRecorder: Sendable {
    public let sensor: SensorID
    private let environment: RuntimeEnvironment
    private let startedAt: Double
    private var availability: RecordedAvailability
    private var samples: [SensorSample]

    public init(
        sensor: SensorID,
        environment: RuntimeEnvironment = .current,
        startedAt: Double
    ) {
        self.sensor = sensor
        self.environment = environment
        self.startedAt = startedAt
        self.availability = .notImplemented
        self.samples = []
    }

    /// Folds one snapshot in. Snapshots of other sensors are ignored rather
    /// than trapping — a recorder pointed at the wrong stream should produce an
    /// empty trace, not crash a capture session.
    public mutating func record(_ snapshot: SensorSnapshot) {
        guard snapshot.capability.id == sensor else { return }
        availability = RecordedAvailability(snapshot.availability)
        if let sample = snapshot.sample {
            samples.append(sample)
        }
    }

    public var sampleCount: Int { samples.count }

    public func finish(notes: String? = nil) -> SensorTrace {
        SensorTrace(
            sensor: sensor,
            recordedOn: environment,
            recordedAt: startedAt,
            availability: availability,
            samples: samples,
            notes: notes
        )
    }
}

public extension SensorRegistry {
    /// A registry backed entirely by recorded traces.
    ///
    /// This is what makes the app demonstrable without hardware. Capabilities
    /// with no trace fall back to `UnimplementedSource`, so a partial set of
    /// recordings produces a partially-populated app rather than a broken one.
    static func replaying(_ traces: [SensorTrace]) -> SensorRegistry {
        SensorRegistry(traces.filter { !$0.isEmpty }.map { ReplaySensorSource($0) })
    }
}
