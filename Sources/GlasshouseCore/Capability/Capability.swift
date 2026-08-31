/// One sensor or data source, with everything the project needs to know about it.
///
/// This type is the spine of the project. It is simultaneously the registry of
/// what the app can read, the record of what it costs to sign, the expectation
/// of how it behaves in a simulator, and the provenance of every claim. Keeping
/// those as one value means they cannot drift apart.
///
/// Rows live in `Ledger+<Framework>.swift` files and are assembled in
/// `CapabilityLedger.all`.
public struct Capability: Sendable, Hashable, Codable, Identifiable {
    /// Stable dotted identifier. Never change one once it has shipped.
    public let id: SensorID

    /// Short human name, as shown in the app.
    public let displayName: String

    /// Apple framework providing it, e.g. `CoreMotion`.
    public let framework: String

    /// What this actually reveals about the person, in plain language.
    /// This is user-facing copy, not a developer note — it is the sentence the
    /// app shows to explain why the reading matters.
    public let reveals: String

    /// Info.plist usage-description keys required. Empty means no permission
    /// dialog is involved, which is itself one of the most instructive facts
    /// this app can surface.
    public let plistKeys: [String]

    /// Entitlement required, if any, e.g. `com.apple.developer.healthkit`.
    public let entitlement: String?

    /// What it costs to legally sign a build using this.
    public let tier: SigningTier

    /// What it actually does in the iOS Simulator.
    public let simulator: SimulatorBehavior

    /// How much it reveals, driving storage and default-collection policy.
    public let sensitivity: Sensitivity

    /// Whether reading this triggers a system permission prompt.
    ///
    /// Deliberately separate from `plistKeys` being empty, because the two come
    /// apart in both directions — Vision needs no permission at all, while
    /// pasteboard *shape* can be read with a usage key but no prompt and no
    /// banner.
    public let promptsUser: Bool

    /// Where the claims above were verified. A URL, or a local path such as
    /// `xcrun simctl help privacy`.
    public let source: String

    /// When they were last verified. Rows go stale; Apple deprecates quietly.
    public let verified: LedgerDate

    /// Implementation state.
    public let status: ImplementationStatus

    /// Anything a reader would otherwise have to rediscover: silent-failure
    /// modes, deprecations, hardware requirements, related traps.
    public let notes: String?

    public init(
        id: SensorID,
        displayName: String,
        framework: String,
        reveals: String,
        plistKeys: [String] = [],
        entitlement: String? = nil,
        tier: SigningTier = .free,
        simulator: SimulatorBehavior,
        sensitivity: Sensitivity,
        promptsUser: Bool,
        source: String,
        verified: LedgerDate,
        status: ImplementationStatus = .notStarted,
        notes: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.framework = framework
        self.reveals = reveals
        self.plistKeys = plistKeys
        self.entitlement = entitlement
        self.tier = tier
        self.simulator = simulator
        self.sensitivity = sensitivity
        self.promptsUser = promptsUser
        self.source = source
        self.verified = verified
        self.status = status
        self.notes = notes
    }

    /// Whether this can be verified without physical hardware.
    public var isProvableInSimulator: Bool {
        !simulator.requiresDevice
    }

    /// Whether this is reachable given a signing tier.
    public func isReachable(with available: SigningTier) -> Bool {
        tier.isReachable(with: available)
    }

    /// Whether the verification of this row has aged past `limit` days as of `today`.
    public func isStale(asOf today: LedgerDate, limit: Int = 90) -> Bool {
        verified.days(to: today) > limit
    }
}

/// How far along a capability is.
public enum ImplementationStatus: String, Sendable, Codable, CaseIterable {
    /// Researched and in the ledger, no code yet.
    case notStarted = "not_started"

    /// Being implemented right now.
    case inProgress = "in_progress"

    /// Implemented, with tests.
    case implemented

    /// Cannot be implemented, and the reason is recorded in `notes`. This is a
    /// finished state, not a failure — documenting an impossibility is part of
    /// what this app is for.
    case blocked
}
