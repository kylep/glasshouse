import Foundation
import OSLog
import GlasshouseCore

/// Dumps what each capability did on real hardware, for the device checklist.
///
/// Exists because 30-odd capabilities cannot be verified by reading a phone
/// screen aloud. It runs once per launch in debug builds and writes one line
/// per capability to the system log, which can be read from a Mac with:
///
///     log stream --device --predicate 'subsystem == "fit.glasshouse.diagnostics"'
///
/// **It logs no readings.** Only the capability identifier, the availability the
/// adapter reported, and whether a sample arrived at all. Logging values would
/// write location, health, and contact data into a system log that other
/// processes and sysdiagnose bundles can read — which would be a far worse
/// privacy failure than anything this app was built to expose.
enum DeviceDiagnostics {
    private static let log = Logger(subsystem: "fit.glasshouse.diagnostics", category: "capabilities")

    /// Also written to stdout, because `log stream` cannot target a connected
    /// device from the command line on current macOS, while
    /// `devicectl process launch --console` can capture stdout directly.
    private static func emit(_ line: String) {
        print("GH| \(line)")
        log.notice("\(line, privacy: .public)")
    }

    static func report(_ snapshots: [SensorSnapshot]) {
        #if DEBUG
        let environment = RuntimeEnvironment.current
        emit("BEGIN environment=\(environment.rawValue) capabilities=\(snapshots.count)")

        for snapshot in snapshots.sorted(by: { $0.capability.id < $1.capability.id }) {
            // Field labels are static strings from the ledger, never values —
            // and even so, only the count is emitted.
            emit("""
                CAP id=\(snapshot.capability.id.rawValue) \
                state=\(describe(snapshot.availability)) \
                reading=\(snapshot.hasReading ? "yes" : "no") \
                fields=\(snapshot.sample?.fields.count ?? 0) \
                expectedSim=\(snapshot.capability.simulator.rawValue) \
                anomaly=\(snapshot.isUnexplainedSilence ? "YES" : "no")
                """.replacingOccurrences(of: "\n", with: ""))
        }

        let readable = snapshots.filter(\.hasReading).count
        let silent = snapshots.filter { $0.hasReading && $0.capability.gate == .neverAsks }.count
        let anomalies = snapshots.unexplained.count
        emit("END readable=\(readable) silentlyReadable=\(silent) anomalies=\(anomalies)")
        #endif
    }

    private static func describe(_ availability: SensorAvailability) -> String {
        switch availability {
        case .ready: "ready"
        case .limited: "limited"
        case .needsPermission: "needsPermission"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notImplemented: "notImplemented"
        case let .unavailable(reason): "unavailable(\(reason.rawValue))"
        }
    }
}
