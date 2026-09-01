#if os(iOS)
import Foundation
import CoreBluetooth
import GlasshouseCore

/// A census of the Bluetooth devices around you.
///
/// The highest-value sensor available to a free account: it needs no
/// entitlement at all, and it is completely unavailable in a Simulator — the
/// runtime ships no Bluetooth stack, so this could not be written honestly
/// until there was a phone to run it on.
///
/// What it sees is other people's hardware. Headphones, watches, cars, fitness
/// trackers, and the phones of everyone nearby, each with a signal strength
/// that estimates distance. Many advertise a name their owner chose, which is
/// frequently their actual name.
@MainActor
final class BluetoothScanner: NSObject, CBCentralManagerDelegate {
    static let shared = BluetoothScanner()

    private var central: CBCentralManager?

    /// Discovered peers, keyed by the identifier iOS assigns. Never a MAC
    /// address — iOS substitutes a per-app UUID, and the peripheral's own
    /// address rotates roughly every fifteen minutes.
    private var seen: [UUID: Peer] = [:]

    struct Peer: Sendable {
        let name: String?
        let rssi: Int
        let connectable: Bool
        let manufacturer: String?
        let services: Int
        let firstSeen: Double
    }

    private override init() {
        super.init()
    }

    /// Creating the manager is what triggers the Bluetooth permission dialog,
    /// so it is deliberately deferred until something asks — constructing it
    /// eagerly would prompt on launch, before the user has any context.
    private func ensureManager() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    var authorization: CBManagerAuthorization { CBManager.authorization }

    /// Whether the radio can actually be used.
    ///
    /// Measured trap, and the reason this is separate from `authorization`:
    /// in a Simulator `CBManager.authorization` reports `.allowedAlways` while
    /// `state` is `.unsupported`. Gating on authorization alone would claim a
    /// working radio where there is none.
    var state: CBManagerState { central?.state ?? .unknown }

    func prepare() {
        ensureManager()
    }

    /// Scans for `duration` seconds and returns what was heard.
    func scan(for duration: Double = 4) async -> [Peer] {
        ensureManager()

        // The manager needs a moment to reach .poweredOn after creation.
        for _ in 0..<20 where central?.state != .poweredOn {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard central?.state == .poweredOn else { return [] }

        seen.removeAll()
        central?.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
        ])

        try? await Task.sleep(for: .seconds(duration))
        central?.stopScan()

        return seen.values.sorted { $0.rssi > $1.rssi }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {}

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Nothing here crosses into the MainActor except plain values —
        // CBPeripheral is not Sendable and must not.
        let id = peripheral.identifier
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.count ?? 0
        let manufacturer = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)
            .flatMap { Self.manufacturerName(from: $0) }
        let rssi = RSSI.intValue
        let now = Date().timeIntervalSince1970

        Task { @MainActor in
            let peer = Peer(name: name, rssi: rssi, connectable: connectable,
                            manufacturer: manufacturer, services: services, firstSeen: now)
            BluetoothScanner.shared.record(id, peer)
        }
    }

    private func record(_ id: UUID, _ peer: Peer) {
        seen[id] = peer
    }

    /// The first two bytes of manufacturer data are a company identifier
    /// assigned by the Bluetooth SIG. Only the handful worth naming are mapped;
    /// everything else stays a number rather than a guess.
    nonisolated static func manufacturerName(from data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        let code = UInt16(data[0]) | (UInt16(data[1]) << 8)
        return switch code {
        case 0x004C: "Apple"
        case 0x0006: "Microsoft"
        case 0x00E0: "Google"
        case 0x0075: "Samsung"
        case 0x0087: "Garmin"
        case 0x0157: "Huawei"
        case 0x038F: "Xiaomi"
        case 0x0171: "Amazon"
        case 0x00D2: "Bose"
        case 0x01D7: "Sonos"
        default: "company 0x\(String(format: "%04X", code))"
        }
    }
}

public struct LiveBluetoothScanSource: SensorSource {
    public let id: SensorID = "bluetooth.scan"

    public init() {}

    public func availability() async -> SensorAvailability {
        switch await BluetoothScanner.shared.authorization {
        case .notDetermined: return .needsPermission
        case .denied: return .denied
        case .restricted: return .restricted
        case .allowedAlways: break
        @unknown default: return .needsPermission
        }

        // Authorization says yes; the radio may still be absent or off. In a
        // Simulator authorization reports allowed while the state is
        // `.unsupported`, so this check is what stops the app claiming a
        // working radio that does not exist.
        await BluetoothScanner.shared.prepare()
        for _ in 0..<10 where await BluetoothScanner.shared.state != .poweredOn {
            try? await Task.sleep(for: .milliseconds(100))
        }

        return switch await BluetoothScanner.shared.state {
        case .poweredOn: .ready
        case .unsupported: .unavailable(reason: RuntimeEnvironment.current == .simulator
            ? .simulator
            : .hardwareAbsent)
        case .unauthorized: .denied
        // Switched off in Control Centre rather than denied to this app —
        // recoverable by the user, but not by granting anything.
        case .poweredOff: .unavailable(reason: .hardwareAbsent)
        default: .unavailable(reason: .hardwareAbsent)
        }
    }

    public func requestAccess() async -> SensorAvailability {
        // Creating the CBCentralManager is what raises the dialog; there is no
        // separate authorization call.
        await BluetoothScanner.shared.prepare()
        for _ in 0..<100 where await BluetoothScanner.shared.authorization == .notDetermined {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return await availability()
    }

    public func read() async -> SensorSample? {
        let peers = await BluetoothScanner.shared.scan()

        // Zero devices is a real answer, not a failure — an empty room reads
        // exactly like this, and reporting nil would file it as a mystery.
        var fields: [SensorField] = [
            SensorField("Devices heard", .integer(peers.count)),
        ]

        let named = peers.compactMap(\.name)
        if !named.isEmpty {
            fields.append(SensorField("Named", .integer(named.count)))
            fields.append(SensorField("Names", .text(named.prefix(6).joined(separator: ", "))))
        }

        if let closest = peers.first {
            fields.append(SensorField("Strongest signal", .number(Double(closest.rssi), unit: "dBm")))
            if let name = closest.name {
                fields.append(SensorField("Closest device", .text(name)))
            }
        }

        let makers = Set(peers.compactMap(\.manufacturer))
        if !makers.isEmpty {
            fields.append(SensorField("Makers", .text(makers.sorted().prefix(5).joined(separator: ", "))))
        }
        fields.append(SensorField("Connectable", .integer(peers.filter(\.connectable).count)))

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }
}
#endif
