/// A sensor that reports exactly what it was told to.
///
/// This is the workhorse of the whole project. The Simulator produces real data
/// for only a handful of sources and cannot inject motion at all, so the test
/// suite and most of the UI run against these rather than against hardware.
///
/// Everything is deterministic: no clock, no randomness, no I/O. Two runs with
/// the same construction produce byte-identical samples.
public struct FakeSensorSource: SensorSource {
    public let id: SensorID
    private let state: SensorAvailability
    private let stateAfterAsking: SensorAvailability?
    private let samples: [SensorSample]

    /// - Parameters:
    ///   - availability: what the sensor reports about itself.
    ///   - grantsOnRequest: availability after `requestAccess()`. Nil means
    ///     asking changes nothing, which models a denied or unavailable sensor.
    ///   - samples: readings served in order, then repeating the last one.
    ///     Empty models the important case of an available sensor with nothing
    ///     to report.
    public init(
        id: SensorID,
        availability: SensorAvailability = .ready,
        grantsOnRequest: SensorAvailability? = nil,
        samples: [SensorSample] = []
    ) {
        self.id = id
        self.state = availability
        self.stateAfterAsking = grantsOnRequest
        self.samples = samples
    }

    public func availability() async -> SensorAvailability { state }

    public func requestAccess() async -> SensorAvailability {
        stateAfterAsking ?? state
    }

    public func read() async -> SensorSample? { samples.first }
}

public extension FakeSensorSource {
    /// A sensor that is present, permitted, and reporting one value.
    static func reporting(
        _ id: SensorID,
        _ fields: [SensorField],
        at timestamp: Double = 0
    ) -> FakeSensorSource {
        FakeSensorSource(
            id: id,
            availability: .ready,
            samples: [SensorSample(sensor: id, timestamp: timestamp, fields: fields)]
        )
    }

    /// A sensor that works but has nothing to say. Distinct from unavailable,
    /// and the distinction is the point.
    static func quiet(_ id: SensorID) -> FakeSensorSource {
        FakeSensorSource(id: id, availability: .ready, samples: [])
    }

    /// A sensor absent because this is a Simulator — the default state of most
    /// of the ledger during development.
    static func missingInSimulator(_ id: SensorID) -> FakeSensorSource {
        FakeSensorSource(id: id, availability: .unavailable(reason: .simulator))
    }

    /// A sensor waiting to be asked for, which will be granted.
    static func awaitingPermission(_ id: SensorID, thenReporting fields: [SensorField] = []) -> FakeSensorSource {
        FakeSensorSource(
            id: id,
            availability: .needsPermission,
            grantsOnRequest: .ready,
            samples: fields.isEmpty ? [] : [SensorSample(sensor: id, timestamp: 0, fields: fields)]
        )
    }

    /// A sensor the user declined. Asking again changes nothing.
    static func denied(_ id: SensorID) -> FakeSensorSource {
        FakeSensorSource(id: id, availability: .denied)
    }
}

/// Builds a registry whose behaviour matches what the ledger predicts for the
/// current environment.
///
/// This is what the Simulator UI runs against: every capability the ledger says
/// returns nothing here reports as unavailable, and everything else reports a
/// plausible fixed reading. It means the app is fully explorable with no
/// hardware, and — more usefully — that the *explanations* for missing sensors
/// are exercised rather than assumed.
public enum LedgerConsistentFakes {
    public static func registry(
        for environment: RuntimeEnvironment = .current,
        tier: SigningTier = .free
    ) -> SensorRegistry {
        SensorRegistry(CapabilityLedger.reachable(with: tier).map { capability in
            source(for: capability, in: environment)
        })
    }

    static func source(for capability: Capability, in environment: RuntimeEnvironment) -> FakeSensorSource {
        if capability.status == .blocked {
            return FakeSensorSource(
                id: capability.id,
                availability: .unavailable(
                    reason: capability.tier == .unobtainable ? .noPublicAPI : .entitlementMissing
                )
            )
        }

        // On anything that is not a real device, honour the measured simulator
        // behaviour rather than pretending the sensor works.
        if !environment.supportsLiveSensors, capability.simulator.silenceIsExpected {
            return .missingInSimulator(capability.id)
        }

        if capability.gate.showsSystemDialog {
            return .awaitingPermission(capability.id, thenReporting: placeholderFields(for: capability))
        }

        return .reporting(capability.id, placeholderFields(for: capability))
    }

    /// A single field naming what would appear here. Deliberately not fabricated
    /// sensor data — showing invented coordinates in an app about honesty would
    /// undercut the whole exercise.
    static func placeholderFields(for capability: Capability) -> [SensorField] {
        [SensorField("Status", .text("Awaiting a real reading from \(capability.framework)"))]
    }
}
