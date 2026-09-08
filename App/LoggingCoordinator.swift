import Foundation
import Observation
import GlasshouseCore
import GlasshouseSensors

/// Owns the logging policies, the databases, and the timer that drives polling.
///
/// One coordinator for the whole app. It holds a log per sensitivity class and
/// routes each reading to the right one, so intimate data never touches the
/// file the rest of the app opens.
@MainActor
@Observable
final class LoggingCoordinator {
    private(set) var policies = LoggingPolicies()
    private(set) var lastError: String?

    /// Bumped whenever stored readings change.
    ///
    /// `series` and `count` query SQLite directly, so Observation has no
    /// property to watch and no way to know a row was written — the Dashboard
    /// only ever redrew because some *other* observed property happened to
    /// change at the same moment. A reading recorded by the interval timer
    /// changed nothing on screen. Every read below touches this first, which
    /// registers the dependency and makes stored data behave like state.
    private(set) var revision = 0

    /// When readings were last re-read from disk, for the Dashboard to show.
    private(set) var lastRefreshed: Date?

    /// When each signal was last recorded, for scheduling. Not persisted: a
    /// relaunch should take a reading promptly rather than honour an interval
    /// that elapsed while the app was closed.
    private var lastRead: [SensorID: Double] = [:]

    private var logs: [Sensitivity: SignalLog] = [:]
    private var timer: Task<Void, Never>?
    private let registry = GlasshouseSensors.liveRegistry()

    init() {
        loadPolicies()
        openLogs()
        reschedule()
    }

    // MARK: - Policies

    func policy(for id: SensorID) -> LoggingPolicy { policies[id] }

    func update(_ policy: LoggingPolicy, for id: SensorID) {
        policies[id] = policy
        savePolicies()
        reschedule()

        // Switching a signal on takes a reading immediately, whatever the
        // capture mode. This previously fired only for polling signals, so
        // enabling one with the default (on demand) recorded nothing at all and
        // gave no sign of it — the switch looked broken.
        if policy.isEnabled {
            Task { await record(id) }
        }
    }

    /// Switches on a set of signals at once, and takes a first reading of each.
    ///
    /// Returns how many changed, so the UI can say what it did rather than
    /// leaving someone to count rows.
    @discardableResult
    func enable(_ ids: [SensorID]) -> Int {
        let before = policies.enabled.count
        policies.enable(ids)
        savePolicies()
        reschedule()

        for id in policies.enabled where !ids.isEmpty {
            if ids.contains(id) { Task { await record(id) } }
        }
        return policies.enabled.count - before
    }

    /// Stops recording everything, keeping each signal's settings.
    @discardableResult
    func disableAll() -> Int {
        let stopped = policies.enabled.count
        policies.disableAll()
        savePolicies()
        stopTimer()
        return stopped
    }

    /// Signals that can be recorded right now — readable, and not already on.
    func recordable(from snapshots: [SensorSnapshot]) -> [SensorID] {
        snapshots.filter { $0.availability.canRead }.map(\.capability.id)
    }

    /// Deletes everything recorded for a signal, and says how much went.
    @discardableResult
    func deleteHistory(for id: SensorID) -> Int {
        guard let capability = CapabilityLedger[id],
              let log = logs[capability.sensitivity] else { return 0 }
        let removed = (try? log.deleteAll(sensor: id)) ?? 0
        lastRead[id] = nil
        return removed
    }

    // MARK: - Recording

    /// Takes one reading and stores it, whatever the capture mode. This is what
    /// the on-demand button calls.
    func record(_ id: SensorID) async {
        guard policies[id].isEnabled else { return }
        guard let capability = CapabilityLedger[id],
              let log = logs[capability.sensitivity] else { return }

        guard let snapshot = await registry.snapshot(id), let sample = snapshot.sample else {
            // Nothing to store is not an error — the sensor may be denied or
            // simply quiet — but the attempt still counts, or a silent sensor
            // would be retried in a tight loop forever.
            lastRead[id] = Date().timeIntervalSince1970
            return
        }

        do {
            try log.append(sample)
            revision += 1
            lastRead[id] = Date().timeIntervalSince1970
            try log.enforce(policies[id].retention, on: id, now: Date().timeIntervalSince1970)
        } catch {
            lastError = "Couldn't record \(capability.displayName): \(error)"
        }
    }

    /// How a manual collection is going, for the button to show.
    enum CollectionState: Equatable {
        case idle
        case collecting
        case finished(recorded: Int)
    }

    private(set) var collection: CollectionState = .idle

    /// Takes a reading of every enabled signal, now, regardless of schedule.
    ///
    /// Sequential rather than parallel: several sensors take seconds to answer
    /// and a few contend for the same hardware, so firing them all at once
    /// makes the slow ones slower and the button lie about being finished.
    func collectNow() async {
        guard collection != .collecting else { return }
        collection = .collecting

        var recorded = 0
        for id in policies.enabled {
            let before = count(for: id)
            await record(id)
            if count(for: id) > before { recorded += 1 }
        }

        collection = .finished(recorded: recorded)
        reschedule()

        // Held long enough to read, then cleared. The button fades back rather
        // than snapping, so a fast collection does not just flicker.
        try? await Task.sleep(for: .seconds(2))
        if case .finished = collection { collection = .idle }
    }

    /// Re-reads what is on disk, for pull-to-refresh.
    ///
    /// Deliberately does not take new readings — that is what Collect is for,
    /// and a pull that silently wrote to the log would be a hidden side effect
    /// on a gesture people use to look, not to change things.
    func refresh() async {
        revision += 1
        lastRefreshed = Date()
        // A re-read of a few hundred rows finishes faster than the spinner can
        // appear, which reads as the gesture having been ignored. This holds it
        // just long enough to be seen.
        try? await Task.sleep(for: .milliseconds(450))
    }

    /// Reads everything currently due.
    func recordDue() async {
        let plan = LoggingPlan(policies: policies)
        for id in plan.due(at: Date().timeIntervalSince1970, lastRead: lastRead) {
            await record(id)
        }
        reschedule()
    }

    // MARK: - Reading back

    func series(for sensor: SensorID, field: String, since: Double? = nil) -> [(at: Double, value: Double)] {
        _ = revision
        guard let capability = CapabilityLedger[sensor],
              let log = logs[capability.sensitivity] else { return [] }
        return (try? log.series(sensor: sensor, field: field, since: since)) ?? []
    }

    func count(for sensor: SensorID) -> Int {
        _ = revision
        guard let capability = CapabilityLedger[sensor],
              let log = logs[capability.sensitivity] else { return 0 }
        return (try? log.count(sensor: sensor)) ?? 0
    }

    func numericFields(for sensor: SensorID) -> [String] {
        _ = revision
        guard let capability = CapabilityLedger[sensor],
              let log = logs[capability.sensitivity] else { return [] }
        return (try? log.numericFields(sensor: sensor)) ?? []
    }

    /// Featured charts that actually have data behind them.
    var chartsWithData: [ChartableSignals.Featured] {
        ChartableSignals.featured.filter { count(for: $0.sensor) > 1 }
    }

    var hasAnyData: Bool {
        policies.enabled.contains { count(for: $0) > 0 }
    }

    /// Signals switched on that do not yet have enough points to draw.
    ///
    /// A chart needs two readings to have a shape. Without this the Dashboard
    /// could not distinguish "you have not turned anything on" from "it is
    /// recording, wait for the next reading" — and said the former in both
    /// cases, which was wrong and looked like a bug.
    var awaitingFirstPoints: [(featured: ChartableSignals.Featured, count: Int)] {
        ChartableSignals.featured.compactMap { featured in
            guard policies[featured.sensor].isEnabled else { return nil }
            let stored = count(for: featured.sensor)
            return stored > 1 ? nil : (featured, stored)
        }
    }

    // MARK: - Scheduling

    /// Foreground only, and deliberately so — see `CaptureMode.interval`.
    private func reschedule() {
        timer?.cancel()
        let plan = LoggingPlan(policies: policies)
        guard let wait = plan.secondsUntilNextDue(at: Date().timeIntervalSince1970, lastRead: lastRead)
        else { return }

        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await self?.recordDue()
        }
    }

    func stopTimer() { timer?.cancel(); timer = nil }

    // MARK: - Storage

    private func openLogs() {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("Logs", isDirectory: true) else { return }

        for sensitivity in Sensitivity.allCases {
            do {
                logs[sensitivity] = try SignalLog(sensitivity: sensitivity, directory: directory)
            } catch {
                lastError = "Couldn't open the \(sensitivity.rawValue) log: \(error)"
            }
        }
    }

    private var policiesURL: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("logging-policies.json")
    }

    private func loadPolicies() {
        guard let url = policiesURL, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LoggingPolicies.self, from: data)
        else { return }
        policies = decoded
    }

    private func savePolicies() {
        guard let url = policiesURL, let data = try? JSONEncoder().encode(policies) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
