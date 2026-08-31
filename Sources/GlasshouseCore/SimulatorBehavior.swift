/// What a sensor actually does in the iOS Simulator.
///
/// This exists because the simulator fails silently rather than loudly: a
/// missing camera yields an empty array, CoreTelephony yields an empty
/// dictionary inside a non-nil Optional, and Core Motion simply reports every
/// capability as unavailable. "Zero samples, no error" looks identical to a
/// working sensor with nothing to report, so the expected behaviour has to be
/// recorded as data rather than discovered at runtime.
public enum SimulatorBehavior: String, Codable, Sendable, CaseIterable {
    /// Produces real, useful data. Safe to develop and test against.
    case worksFully = "works_fully"

    /// Produces data, but it is host-derived, stubbed, or otherwise not
    /// representative of a phone — e.g. disk capacity reporting the Mac's volume.
    case worksWithCaveats = "works_with_caveats"

    /// The API is present and calls succeed, but no data is ever delivered.
    /// This is the dangerous one: it is indistinguishable from a quiet sensor.
    case returnsNothing = "returns_nothing"

    /// The framework or capability is absent entirely, so the code path cannot
    /// even be exercised.
    case unavailable

    /// Whether verifying this sensor requires physical hardware.
    public var requiresDevice: Bool {
        switch self {
        case .worksFully, .worksWithCaveats: false
        case .returnsNothing, .unavailable: true
        }
    }

    /// Whether a zero-sample result from this sensor should be treated as
    /// expected rather than as a defect worth investigating.
    public var silenceIsExpected: Bool {
        self == .returnsNothing || self == .unavailable
    }
}
