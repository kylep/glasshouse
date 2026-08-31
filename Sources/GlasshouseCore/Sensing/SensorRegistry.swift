/// Every sensor the app can show, backed by whichever implementation is
/// appropriate for where it is running.
///
/// The registry always covers the **whole ledger**. A capability with no
/// registered source falls back to `UnimplementedSource` rather than
/// disappearing, so the app's inventory is complete from the first build and
/// the gaps are visible instead of invisible.
public struct SensorRegistry: Sendable {
    private let sources: [SensorID: any SensorSource]

    public init(_ sources: [any SensorSource] = []) {
        self.sources = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Registered identifiers that no ledger row describes.
    ///
    /// Should always be empty: the ledger is the registry, so a source for an
    /// unknown capability means someone bypassed it. Checked by tests.
    public var unknownSources: [SensorID] {
        sources.keys.filter { CapabilityLedger[$0] == nil }.sorted()
    }

    /// Ledger rows with a real implementation behind them.
    public var implemented: [SensorID] {
        sources.keys.filter { CapabilityLedger[$0] != nil }.sorted()
    }

    public func source(for id: SensorID) -> any SensorSource {
        sources[id] ?? UnimplementedSource(id)
    }

    // MARK: - Reading

    public func snapshot(_ id: SensorID) async -> SensorSnapshot? {
        guard let capability = CapabilityLedger[id] else { return nil }
        let source = source(for: id)
        let availability = await source.availability()
        let sample = availability.canRead ? await source.read() : nil
        return SensorSnapshot(capability: capability, availability: availability, sample: sample)
    }

    /// Snapshot everything the ledger knows about, in parallel.
    ///
    /// Results come back sorted by identifier so the UI has a stable order
    /// regardless of how quickly individual sensors answer.
    public func snapshotAll(reachableWith tier: SigningTier = .free) async -> [SensorSnapshot] {
        let capabilities = CapabilityLedger.reachable(with: tier)

        return await withTaskGroup(of: SensorSnapshot?.self) { group in
            for capability in capabilities {
                group.addTask { await snapshot(capability.id) }
            }
            var results: [SensorSnapshot] = []
            for await snapshot in group {
                if let snapshot { results.append(snapshot) }
            }
            return results.sorted { $0.capability.id < $1.capability.id }
        }
    }
}
