#if os(iOS)
import Foundation
// The ONLY file in the project permitted to import Network, and the invariant
// test enforces that. `NWPathMonitor` observes the shape of connectivity — Wi-Fi
// versus cellular, expensive, constrained — without opening a connection or
// sending a byte. The egress types (`NWConnection`, `NWListener`, `NWBrowser`)
// remain banned everywhere, including here.
//
// Banning the whole import would have been a proxy for the wrong thing: it is
// egress that must not exist, not the framework.
import Network
import GlasshouseCore

/// Which kind of connection you are on, and whether it costs you.
///
/// Silent: no permission, no prompt, no Settings entry. A decent proxy for
/// whether someone is at home or out, available to any app that asks.
public struct LiveNetworkPathSource: SensorSource {
    public let id: SensorID = "network.path"

    public init() {}

    public func availability() async -> SensorAvailability { .ready }

    public func read() async -> SensorSample? {
        let path = await NetworkPathBox.shared.currentPath()

        let interface: String
        if path.usesInterfaceType(.wifi) { interface = "Wi-Fi" }
        else if path.usesInterfaceType(.cellular) { interface = "Cellular" }
        else if path.usesInterfaceType(.wiredEthernet) { interface = "Wired" }
        else if path.usesInterfaceType(.loopback) { interface = "Loopback" }
        else { interface = "Unknown" }

        let status: String = switch path.status {
        case .satisfied: "connected"
        case .unsatisfied: "no connection"
        case .requiresConnection: "needs connecting"
        @unknown default: "unknown"
        }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Connection", .text(interface)),
            SensorField("Status", .text(status)),
            SensorField("Metered", .boolean(path.isExpensive)),
            SensorField("Low Data Mode", .boolean(path.isConstrained)),
            SensorField("IPv4", .boolean(path.supportsIPv4)),
            SensorField("IPv6", .boolean(path.supportsIPv6)),
        ])
    }
}

/// Holds the monitor, which must run to have a path to report.
///
/// A freshly started monitor has `.requiresConnection` until its first update
/// arrives, so a one-shot read would report a disconnected phone as offline.
@MainActor
final class NetworkPathBox {
    static let shared = NetworkPathBox()

    private let monitor = NWPathMonitor()
    private var started = false

    private init() {}

    func currentPath() async -> NWPath {
        if !started {
            started = true
            monitor.start(queue: .global(qos: .utility))
            // One brief yield so the first path update can land.
            try? await Task.sleep(for: .milliseconds(120))
        }
        return monitor.currentPath
    }
}
#endif
