/// The complete inventory of what Glasshouse can read, and what each reading costs.
///
/// This is the single source of truth. It is simultaneously the sensor registry,
/// the entitlement record, the simulator expectation, and the provenance trail —
/// deliberately one thing rather than four that must be kept in sync.
///
/// Rows live in `Ledger+<Framework>.swift`. Add a capability by adding a row;
/// there is no separate registration step, and no way to implement a sensor the
/// ledger does not know about.
public enum CapabilityLedger {
    public static let all: [Capability] =
        coreMotion
        + coreLocation
        + health
        + media
        + personalData
        + deviceState
        + connectivity
        + restricted

    // MARK: - Lookup

    public static subscript(id: SensorID) -> Capability? {
        byID[id]
    }

    private static let byID: [SensorID: Capability] = {
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }()

    /// Frameworks in stable order, each with its capabilities sorted by id.
    public static var byFramework: [(framework: String, capabilities: [Capability])] {
        Dictionary(grouping: all, by: \.framework)
            .map { (framework: $0.key, capabilities: $0.value.sorted { $0.id < $1.id }) }
            .sorted { $0.framework < $1.framework }
    }

    // MARK: - Slices the project actually uses

    /// Capabilities reachable at a given signing tier. Everything else is
    /// documentation — real, but not something this build can use.
    public static func reachable(with tier: SigningTier) -> [Capability] {
        all.filter { $0.isReachable(with: tier) }
    }

    /// Capabilities that a simulator can never prove. Generates the device
    /// verification checklist, so device day is enumerated in advance rather
    /// than rediscovered.
    public static var requiringDeviceVerification: [Capability] {
        all.filter { !$0.isProvableInSimulator }.sorted { $0.id < $1.id }
    }

    /// Capabilities iOS never asks about. The quietly alarming set, and the
    /// most instructive thing the app has to show.
    ///
    /// Deliberately excludes `tellsYouAfter`: a banner is not consent, but it
    /// is not nothing either, and folding it in here is what made the old
    /// boolean misleading.
    public static var neverAsked: [Capability] {
        all.filter { $0.gate == .neverAsks }.sorted { $0.id < $1.id }
    }

    /// Capabilities behind a system permission dialog.
    public static var behindADialog: [Capability] {
        all.filter { $0.gate == .asksOnce }.sorted { $0.id < $1.id }
    }

    /// Other capabilities that the same grant unlocks.
    ///
    /// iOS grants permission per *usage-description key*, not per capability,
    /// and several capabilities share one. There is no separate compass
    /// permission: heading and location both declare
    /// `NSLocationWhenInUseUsageDescription`, so granting either grants both.
    /// The same is true of the photo library and photo locations.
    ///
    /// Without this the app lies twice — it offers to ask for something iOS
    /// will not ask about, and it leaves the sibling row looking un-granted
    /// after the user has in fact granted it.
    public static func sharingPermission(with id: SensorID) -> [Capability] {
        guard let row = self[id], !row.plistKeys.isEmpty else { return [] }
        let keys = Set(row.plistKeys)
        return all
            .filter { $0.id != id && !Set($0.plistKeys).isDisjoint(with: keys) }
            .sorted { $0.id < $1.id }
    }

    /// Every capability a single grant covers, including the one asked for.
    public static func permissionGroup(for id: SensorID) -> [SensorID] {
        ([self[id]].compactMap { $0 } + sharingPermission(with: id))
            .map(\.id).sorted()
    }

    /// Every Info.plist usage-description key the app must declare, deduplicated
    /// and sorted. Drives Info.plist generation, so a capability cannot ship
    /// without its purpose string.
    public static func requiredPlistKeys(for tier: SigningTier) -> [String] {
        Set(reachable(with: tier).flatMap(\.plistKeys)).sorted()
    }

    /// Rows whose verification has aged out and should be re-checked.
    public static func stale(asOf today: LedgerDate, limit: Int = 90) -> [Capability] {
        all.filter { $0.isStale(asOf: today, limit: limit) }.sorted { $0.verified < $1.verified }
    }

    // MARK: - Structural validation

    /// Problems that make the ledger internally inconsistent.
    ///
    /// Checked by the test suite rather than at startup: these are authoring
    /// mistakes, and they should fail a build, not a user's launch.
    public static func inconsistencies(in rows: [Capability] = all) -> [String] {
        var problems: [String] = []

        var seen = Set<SensorID>()
        for row in rows where !seen.insert(row.id).inserted {
            problems.append("Duplicate id '\(row.id)'")
        }

        for row in rows {
            if row.id.rawValue.isEmpty || row.displayName.isEmpty {
                problems.append("'\(row.id)' has an empty id or display name")
            }
            if row.source.isEmpty {
                problems.append("'\(row.id)' has no source — every claim needs provenance")
            }
            if row.reveals.isEmpty {
                problems.append("'\(row.id)' does not say what it reveals")
            }
            // Deliberately NOT the converse rule ("a plist key implies a
            // dialog"). That was asserted here until an iPhone disproved it:
            // the raw Core Motion streams declare NSMotionUsageDescription and
            // never prompt, because Motion & Fitness gates only the derived
            // sensors. Declaring a key you might need is cheap; claiming iOS
            // will ask when it won't is a lie to the user.
            // Nothing readable can be off limits, and nothing off limits can be
            // readable — that pairing was the ambiguity the old flag created.
            if row.gate == .noAccessAtAll && row.status != .blocked {
                problems.append("'\(row.id)' is marked off limits but is not blocked")
            }
            // The converse only holds for capabilities this build can actually
            // reach. Some frameworks take consent through a system picker or an
            // authorization centre rather than a usage string — Family Controls
            // and Journaling Suggestions both prompt with no Info.plist key at
            // all — so the rule would produce false positives on rows that are
            // documentation rather than code.
            if row.tier == .free, row.status != .blocked, row.gate.showsSystemDialog, row.plistKeys.isEmpty {
                problems.append("'\(row.id)' prompts the user but declares no Info.plist key")
            }
            // Blocked rows must explain themselves; that explanation is content.
            if row.status == .blocked && (row.notes ?? "").isEmpty {
                problems.append("'\(row.id)' is blocked but does not say why")
            }
            // Note there is deliberately no rule tying `entitlement` to `tier`.
            // The obvious one — "an entitlement implies a cost" — is false:
            // HealthKit, App Groups, HomeKit, and Keychain Sharing are all
            // entitlements a free Personal Team can sign.

            // Anything above the free tier is documentation rather than
            // something this build can use, so it must say what it would take.
            if row.tier > .free && (row.notes ?? "").isEmpty {
                problems.append("'\(row.id)' is above the free tier but does not explain what it requires")
            }
        }

        return problems
    }
}
