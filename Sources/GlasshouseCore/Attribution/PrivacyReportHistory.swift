/// Accumulated activity across many imports.
///
/// The report keeps only a **7-day rolling window**, and switching it off in
/// Settings erases it. So a single import is a snapshot of one week; the point
/// of this type is to build a history that outlives the window by merging
/// repeated imports without double-counting the overlap.
public struct PrivacyReportHistory: Sendable, Hashable, Codable {
    /// Keyed on the identity of the underlying event — which app, which
    /// resource, starting when — rather than on the whole value.
    ///
    /// This matters because the same real access can arrive twice in different
    /// shapes. Week one's export catches it mid-flight and reports no end time;
    /// week two's export contains the same access, now finished, with one. As
    /// distinct values those would both survive a set union, and the same event
    /// would be counted twice — exactly the inflation this type exists to
    /// prevent.
    private var accessesByEvent: [AccessKey: ResourceAccess]

    private var contactsByKey: [String: NetworkContact]

    private struct AccessKey: Hashable, Codable, Sendable {
        let bundleID: String
        let resource: AccessedResource
        let began: Double
    }

    public init() {
        accessesByEvent = [:]
        contactsByKey = [:]
    }

    public var accesses: Set<ResourceAccess> {
        Set(accessesByEvent.values)
    }

    public var contacts: [NetworkContact] {
        contactsByKey.values.sorted { ($0.hits, $1.domain) > ($1.hits, $0.domain) }
    }

    /// Folds an import in, merging rather than appending.
    public mutating func merge(_ report: PrivacyReportImport) {
        for access in report.accesses {
            let key = AccessKey(bundleID: access.bundleID, resource: access.resource, began: access.began)

            guard let existing = accessesByEvent[key] else {
                accessesByEvent[key] = access
                continue
            }

            // A later import that completes a previously open interval is an
            // upgrade, not a new event. Prefer the version with a known end.
            if existing.ended == nil, access.ended != nil {
                accessesByEvent[key] = access
            }
        }

        for contact in report.contacts {
            let key = "\(contact.bundleID)|\(contact.domain)"
            guard let existing = contactsByKey[key] else {
                contactsByKey[key] = contact
                continue
            }

            // `hits` counts within one report window, so overlapping imports
            // would double-count if summed. Taking the maximum under-reports a
            // genuinely busier later window, which is the safer direction: this
            // data is used to make claims about other people's apps.
            contactsByKey[key] = NetworkContact(
                bundleID: contact.bundleID,
                domain: contact.domain,
                hits: Swift.max(existing.hits, contact.hits),
                flaggedAsTracker: existing.flaggedAsTracker || contact.flaggedAsTracker,
                appInitiated: existing.appInitiated || contact.appInitiated,
                owner: contact.owner ?? existing.owner,
                firstSeen: Swift.min(existing.firstSeen, contact.firstSeen),
                lastSeen: Swift.max(existing.lastSeen, contact.lastSeen)
            )
        }
    }

    // MARK: - Questions worth asking of it

    /// Every app seen, most active first.
    public var apps: [String] {
        let counts = Dictionary(grouping: accesses, by: \.bundleID).mapValues(\.count)
        return Set(accesses.map(\.bundleID))
            .union(contactsByKey.values.map(\.bundleID))
            .sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    }

    public func accesses(by bundleID: String) -> [ResourceAccess] {
        accesses.filter { $0.bundleID == bundleID }.sorted { $0.began < $1.began }
    }

    public func contacts(by bundleID: String) -> [NetworkContact] {
        contactsByKey.values.filter { $0.bundleID == bundleID }.sorted { $0.hits > $1.hits }
    }

    /// Which apps touched a given resource, and how often.
    public func apps(touching resource: AccessedResource) -> [(bundleID: String, times: Int)] {
        Dictionary(grouping: accesses.filter { $0.resource == resource }, by: \.bundleID)
            .map { (bundleID: $0.key, times: $0.value.count) }
            .sorted { ($0.times, $1.bundleID) > ($1.times, $0.bundleID) }
    }

    /// Domains iOS itself flagged as tracking people across apps.
    ///
    /// Apple's judgement, not an inference — `domainType: 1` in the export.
    public var trackers: [NetworkContact] {
        contactsByKey.values.filter(\.flaggedAsTracker).sorted { $0.hits > $1.hits }
    }

    /// Apps that contacted at least one flagged tracking domain, ranked by how
    /// many distinct ones.
    public var appsContactingTrackers: [(bundleID: String, domains: Int)] {
        Dictionary(grouping: trackers, by: \.bundleID)
            .map { (bundleID: $0.key, domains: Set($0.value.map(\.domain)).count) }
            .sorted { ($0.domains, $1.bundleID) > ($1.domains, $0.bundleID) }
    }

    /// Total seconds an app spent using a resource, across completed intervals.
    ///
    /// Ignores intervals still open at a window edge, so this under-reports
    /// rather than inventing an end time.
    public func totalDuration(bundleID: String, resource: AccessedResource) -> Double {
        accesses
            .filter { $0.bundleID == bundleID && $0.resource == resource }
            .compactMap(\.duration)
            .reduce(0, +)
    }

    /// The most sensitive resource each app touched.
    public var deepestReachPerApp: [(bundleID: String, resource: AccessedResource)] {
        Dictionary(grouping: accesses, by: \.bundleID)
            .compactMap { bundleID, events in
                guard let worst = events.map(\.resource).max(by: {
                    $0.sensitivity < $1.sensitivity
                }) else { return nil }
                return (bundleID, worst)
            }
            .sorted { ($0.resource.sensitivity, $1.bundleID) > ($1.resource.sensitivity, $0.bundleID) }
    }

    public var isEmpty: Bool { accessesByEvent.isEmpty && contactsByKey.isEmpty }
}
