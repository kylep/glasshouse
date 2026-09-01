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

    private let registry = GlasshouseSensors.liveRegistry()

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        snapshots = await registry.snapshotAll()
        lastRefresh = Date()
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
