/// What the app knows about one sensor at one moment: the ledger's claims, the
/// runtime's answer, and the reading if there was one.
///
/// The important work this type does is `explanation` — turning silence into a
/// sentence. That is the product, not a nicety: an app that shows a blank row
/// for the accelerometer teaches nothing, while one that says "this hardware
/// doesn't exist in the Simulator" teaches exactly what it set out to.
public struct SensorSnapshot: Sendable, Hashable {
    public let capability: Capability
    public let availability: SensorAvailability
    public let sample: SensorSample?

    public init(capability: Capability, availability: SensorAvailability, sample: SensorSample?) {
        self.capability = capability
        self.availability = availability
        self.sample = sample
    }

    /// Whether there is a reading to show.
    public var hasReading: Bool { sample != nil }

    /// Whether this sensor is quiet, and the silence is expected rather than a
    /// defect. Cross-references the ledger's measured simulator behaviour.
    public var silenceIsExpected: Bool {
        guard sample == nil else { return false }
        if case .unavailable = availability { return true }
        if availability == .notImplemented { return true }
        return capability.simulator.silenceIsExpected
            && RuntimeEnvironment.current == .simulator
    }

    /// Whether this is a genuine anomaly: the sensor claims it can read, the
    /// ledger says it should produce data here, and yet nothing arrived. This
    /// is the case worth surfacing to a developer rather than a user.
    public var isUnexplainedSilence: Bool {
        sample == nil && availability.canRead && !silenceIsExpected
    }

    /// Plain-language account of the current state, suitable for display.
    public var explanation: String {
        switch availability {
        case .ready:
            return sample == nil
                ? "Available, but reported nothing."
                : "Reading now."
        case .limited:
            return "You granted access to only part of this."
        case .needsPermission:
            return switch capability.gate {
            case .asksOnce: "Hasn't been asked for yet."
            case .tellsYouAfter: "Ready when you are — reading this will notify you."
            case .neverAsks, .noAccessAtAll: "Not started yet."
            }
        case .denied:
            return "You declined this. It can be changed in Settings."
        case .restricted:
            return "Blocked by a policy on this device, not by your choice."
        case let .unavailable(reason):
            return reason.explanation
        case .notImplemented:
            return "Not built yet."
        }
    }
}

public extension Array where Element == SensorSnapshot {
    /// Sensors currently producing readings.
    var reading: [SensorSnapshot] { filter(\.hasReading) }

    /// Sensors producing readings that iOS never asked about. The most
    /// instructive group in the app.
    var readingWithoutAsking: [SensorSnapshot] {
        filter { $0.hasReading && $0.capability.gate == .neverAsks }
    }

    /// Anomalies worth a developer's attention: quiet with no good reason.
    var unexplained: [SensorSnapshot] { filter(\.isUnexplainedSilence) }

    /// Grouped by sensitivity, most revealing first.
    var bySensitivity: [(level: Sensitivity, snapshots: [SensorSnapshot])] {
        Sensitivity.allCases.reversed().compactMap { level in
            let matching = filter { $0.capability.sensitivity == level }
            return matching.isEmpty ? nil : (level, matching)
        }
    }
}
