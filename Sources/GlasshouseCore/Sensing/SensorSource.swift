/// One sensor, in one of its three forms.
///
/// Every capability has up to three implementations of this protocol:
///
/// - **Live** — the real framework call. iOS only, deliberately trivial.
/// - **Fake** — deterministic, no I/O. What the test suite runs against.
/// - **Replay** — plays back a recorded trace. What the Simulator UI uses.
///
/// The third is not a convenience. The Simulator produces real data for only a
/// handful of the app's sources and offers no motion injection at all, so
/// replay is the primary development surface rather than a fallback.
public protocol SensorSource: Sendable {
    /// Which ledger row this implements. Must exist in `CapabilityLedger`.
    var id: SensorID { get }

    /// Whether a reading can be taken, and if not, why not.
    func availability() async -> SensorAvailability

    /// Ask the user for access, if that is meaningful for this sensor.
    /// Returns the availability afterwards. Default: unchanged.
    func requestAccess() async -> SensorAvailability

    /// Take one reading. Returning nil means "available but nothing to report",
    /// which is a genuinely different thing from being unavailable — check
    /// `availability()` to tell them apart.
    func read() async -> SensorSample?
}

public extension SensorSource {
    /// Most sensors have nothing to ask for. Those that do override this.
    func requestAccess() async -> SensorAvailability {
        await availability()
    }

    /// The ledger row backing this source.
    var capability: Capability? {
        CapabilityLedger[id]
    }
}

/// A source for a capability that has no implementation yet.
///
/// Every ledger row gets one of these until a real adapter replaces it, so the
/// app can show its complete inventory from day one — including the parts that
/// do not work. An empty row would be a worse lie than an honest one.
public struct UnimplementedSource: SensorSource {
    public let id: SensorID

    public init(_ id: SensorID) {
        self.id = id
    }

    public func availability() async -> SensorAvailability {
        // A blocked ledger row is not unimplemented — it is impossible, and it
        // should say so rather than implying someone forgot to write it.
        guard let capability = CapabilityLedger[id] else { return .notImplemented }

        if capability.status == .blocked {
            return .unavailable(reason: capability.tier == .unobtainable
                ? .noPublicAPI
                : .entitlementMissing)
        }
        return .notImplemented
    }

    public func read() async -> SensorSample? { nil }
}
