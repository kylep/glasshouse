import Foundation
import Observation
import GlasshouseCore
import GlasshouseSensors

/// Holds the current view of every sensor, and refreshes it.
@MainActor
@Observable
final class SensorStore {
    private(set) var snapshots: [SensorSnapshot] = []
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?

    /// True while the list is showing values from a previous launch.
    ///
    /// The whole point of the cache is a fast first paint, but a stale reading
    /// presented as a live one is exactly what this app criticises. Everything
    /// that renders a value checks this, and the list says so at the top.
    private(set) var isShowingCached = false

    private var registry = GlasshouseSensors.liveRegistry()

    init() {
        // Painting last launch's readings immediately beats a blank list and a
        // spinner for the several seconds a full sweep takes — the Bluetooth
        // scan alone is four of them.
        if let cache = ReadingCacheFile.load(),
           !cache.isStale(asOf: Date().timeIntervalSince1970) {
            snapshots = cache.snapshots
            lastRefresh = Date(timeIntervalSince1970: cache.capturedAt)
            isShowingCached = true
        }
    }

    /// The recording currently driving the app, if any.
    ///
    /// Replaying must never be mistakeable for live. Everything that renders a
    /// reading checks this, and the app says so at the top of the list — an app
    /// arguing that people are misled about their data cannot itself present a
    /// recording as the present moment.
    private(set) var replaying: ReplayContext?

    struct ReplayContext: Sendable, Equatable {
        let name: String
        let recordedOn: RuntimeEnvironment
        let recordedAt: Double
        let sensors: Int
        let notes: String?
    }

    /// Switches the app onto a recording.
    func startReplaying(_ traces: [SensorTrace], named name: String) async {
        let usable = traces.filter { !$0.isEmpty }
        guard let first = usable.first else {
            replaying = nil
            return
        }

        registry = .replaying(usable)
        replaying = ReplayContext(
            name: name,
            recordedOn: first.recordedOn,
            recordedAt: first.recordedAt,
            sensors: usable.count,
            notes: usable.compactMap(\.notes).first
        )
        await refresh()
    }

    /// Returns to the sensors actually attached to this device.
    func stopReplaying() async {
        registry = GlasshouseSensors.liveRegistry()
        replaying = nil
        await refresh()
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        snapshots = await registry.snapshotAll()
        lastRefresh = Date()
        isShowingCached = false

        // Only live readings are cached. Persisting a replay would mean the
        // next launch opened on someone else's recording presented as this
        // phone's state.
        if replaying == nil {
            ReadingCacheFile.save(ReadingCache(snapshots, at: Date().timeIntervalSince1970))
        }
        DeviceDiagnostics.report(snapshots)
    }

    /// Asks for one sensor's permission, then re-reads everything that grant
    /// covers — not just the sensor that was tapped.
    ///
    /// iOS grants per usage-description key, not per capability. Granting
    /// location also grants the compass; granting Motion & Fitness grants all
    /// nine Core Motion readers at once. Refreshing only the tapped row left
    /// its siblings showing "hasn't been asked for yet" after they had in fact
    /// been granted.
    func requestAccess(to id: SensorID) async {
        _ = await registry.source(for: id).requestAccess()

        for affected in CapabilityLedger.permissionGroup(for: id) {
            guard let updated = await registry.snapshot(affected),
                  let index = snapshots.firstIndex(where: { $0.capability.id == affected })
            else { continue }
            snapshots[index] = updated
        }
    }

    // MARK: - Groupings the UI presents

    /// Sensors reading right now that never asked permission.
    ///
    /// The headline of the whole app: not what the phone can be made to reveal,
    /// but what it is revealing already, silently.
    var readingWithoutAsking: [SensorSnapshot] {
        snapshots.filter { $0.hasReading && $0.capability.gate == .neverAsks }
    }

    var readingWithPermission: [SensorSnapshot] {
        snapshots.filter { $0.hasReading && $0.capability.gate != .neverAsks }
    }

    /// Sensors that could report something, once asked.
    ///
    /// Keyed on runtime availability rather than on the ledger's `gate`. Those
    /// come apart: reading the clipboard's contents raises no system dialog, so
    /// its gate is `.tellsYouAfter`, but the app still declines to do it until
    /// the user asks. Filtering on the gate hid that row from every section and
    /// made it unreachable in the UI.
    var awaitingPermission: [SensorSnapshot] {
        snapshots.filter { $0.availability == .needsPermission }
    }

    /// Sensors you said no to, or that a device policy blocks.
    ///
    /// These matched no section before, which meant a denied sensor simply
    /// vanished from the app — the one outcome a tool about permissions must
    /// not hide. Declining is a legitimate answer and deserves to be visible.
    var denied: [SensorSnapshot] {
        snapshots.filter { $0.availability == .denied || $0.availability == .restricted }
    }

    var unavailableHere: [SensorSnapshot] {
        snapshots.filter {
            guard case .unavailable(let reason) = $0.availability else { return false }
            return reason != .noPublicAPI
        }
    }

    /// Things no app may read at all. Documented rather than hidden, because
    /// the sandbox holding is as much the story as the sandbox leaking.
    var impossible: [SensorSnapshot] {
        snapshots.filter { $0.availability == .unavailable(reason: .noPublicAPI) }
    }

    var notBuiltYet: [SensorSnapshot] {
        snapshots.filter { $0.availability == .notImplemented }
    }

    /// Sensors that claim to work, should work here, and yet returned nothing.
    /// A developer-facing anomaly rather than a user-facing fact.
    var anomalies: [SensorSnapshot] {
        snapshots.unexplained
    }
}
