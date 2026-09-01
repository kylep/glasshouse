/// Why a sensor can or cannot produce a reading right now.
///
/// This type exists because of the single most dangerous property of iOS
/// sensor development: **absence of data is not an error**. A missing camera
/// yields an empty array, CoreTelephony yields an empty dictionary inside a
/// non-nil Optional, and Core Motion simply reports every capability
/// unavailable. Without an explicit reason, "no reading" is indistinguishable
/// from "a working sensor with nothing to say".
///
/// Every source must therefore state *why* it is quiet. The UI shows that
/// reason, and the test suite asserts it matches what the ledger predicts.
public enum SensorAvailability: Sendable, Hashable {
    /// Can produce readings now.
    case ready

    /// Permission has not been requested yet. The app must ask.
    case needsPermission

    /// The user declined. Recoverable only through Settings.
    case denied

    /// Permission was granted, but only for part of the data — the iOS 14+
    /// limited photo library, or the iOS 18+ limited contacts. A distinct state
    /// on purpose: collapsing it into `ready` overstates what the app can see,
    /// and collapsing it into `denied` understates it.
    case limited

    /// Blocked by policy rather than choice — Screen Time, MDM, parental
    /// controls. The user cannot simply grant it.
    case restricted

    /// The hardware or framework is not present. Carries the reason, because
    /// "unavailable" alone is what makes silent failure so hard to diagnose.
    case unavailable(reason: UnavailabilityReason)

    /// The capability is in the ledger but no adapter has been written yet.
    /// Honest about the gap rather than pretending the sensor is broken.
    case notImplemented

    /// Whether a reading can be attempted.
    public var canRead: Bool {
        switch self {
        case .ready, .limited: true
        case .needsPermission, .denied, .restricted, .unavailable, .notImplemented: false
        }
    }

    /// Whether asking the user would change anything.
    public var isResolvableByAsking: Bool {
        self == .needsPermission
    }
}

/// Why hardware or a framework cannot serve a reading.
public enum UnavailabilityReason: String, Sendable, Hashable, Codable {
    /// Running in the Simulator, which has no such hardware. Expected, not a bug.
    case simulator

    /// The device genuinely lacks the hardware — no LiDAR, no UWB, no barometer.
    case hardwareAbsent = "hardware_absent"

    /// The build is not signed with the entitlement this requires. Invisible in
    /// the Simulator, which enforces none, so it appears only on device.
    case entitlementMissing = "entitlement_missing"

    /// The OS version is older than the API.
    case osTooOld = "os_too_old"

    /// No public API exists at all — the ambient light sensor, or another app's
    /// permission state. Not a failure: a documented property of the sandbox.
    case noPublicAPI = "no_public_api"

    /// Disabled because it is known to be broken, with the reason recorded in
    /// the ledger. An app about honest disclosure should say "this is broken"
    /// rather than quietly reporting nothing and letting its own anomaly
    /// detector call it a mystery.
    case knownDefect = "known_defect"

    /// Human-readable, and deliberately non-apologetic.
    public var explanation: String {
        switch self {
        case .simulator:
            "This hardware doesn't exist in the Simulator."
        case .hardwareAbsent:
            "This device doesn't have the hardware."
        case .entitlementMissing:
            "This build isn't signed with the required entitlement."
        case .osTooOld:
            "This version of iOS is older than the API."
        case .noPublicAPI:
            "No app is allowed to read this. The sensor exists; the API doesn't."
        case .knownDefect:
            "Switched off: reading this currently crashes the app. Being investigated."
        }
    }
}
