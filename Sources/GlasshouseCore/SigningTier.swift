/// What it costs to legally sign a build that uses a given capability.
///
/// The simulator does not code-sign at all (`CODE_SIGNING_ALLOWED = NO`), and
/// every restricted framework links cleanly there. That means entitlement
/// problems are invisible until first device deploy, all at once. Recording the
/// tier per sensor is how the project carries a constraint the compiler won't.
public enum SigningTier: String, Codable, Sendable, CaseIterable, Comparable {
    /// A free Apple Account (Personal Team) can sign this. Note that this is a
    /// larger set than folklore suggests: HealthKit, App Groups, Keychain
    /// Sharing, HomeKit, and all `UIBackgroundModes` qualify.
    case free

    /// Requires the $99/yr Apple Developer Program, but no further approval.
    case paid

    /// Requires the paid program plus a per-entitlement request granted by
    /// Apple, e.g. multicast networking or Family Controls distribution.
    case paidPlusApproval = "paid_plus_approval"

    /// Cannot realistically be obtained for a personal project at any price.
    /// SensorKit is the canonical example: Apple grants it only for approved
    /// research studies with ethics-board sign-off.
    case unobtainable

    /// Whether this capability is reachable given the project's current
    /// signing situation.
    public func isReachable(with available: SigningTier) -> Bool {
        self <= available
    }

    private var cost: Int {
        switch self {
        case .free: 0
        case .paid: 1
        case .paidPlusApproval: 2
        case .unobtainable: 3
        }
    }

    public static func < (lhs: SigningTier, rhs: SigningTier) -> Bool {
        lhs.cost < rhs.cost
    }
}
