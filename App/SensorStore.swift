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
    }

    /// Asks for one sensor's permission, then re-reads just that sensor.
    func requestAccess(to id: SensorID) async {
        _ = await registry.source(for: id).requestAccess()
        guard let updated = await registry.snapshot(id) else { return }
        if let index = snapshots.firstIndex(where: { $0.capability.id == id }) {
            snapshots[index] = updated
        }
    }

    // MARK: - Groupings the UI presents

    /// Sensors reading right now that never asked permission.
    ///
    /// The headline of the whole app: not what the phone can be made to reveal,
    /// but what it is revealing already, silently.
    var readingWithoutAsking: [SensorSnapshot] {
        snapshots.filter { $0.hasReading && !$0.capability.promptsUser }
    }

    var readingWithPermission: [SensorSnapshot] {
        snapshots.filter { $0.hasReading && $0.capability.promptsUser }
    }

    var awaitingPermission: [SensorSnapshot] {
        snapshots.filter { $0.availability == .needsPermission && $0.capability.promptsUser }
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
