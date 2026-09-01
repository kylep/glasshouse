#if os(iOS)
import Foundation
import AVFoundation
import CoreTelephony
import GlasshouseCore

// Four more things readable without iOS asking, each its own ledger row.
//
// `LiveSystemStateSource` used to report all of this under `device.thermal`,
// which conflated four separate capabilities into one reading and made the
// ledger's row count a fiction.

/// How much space is free, and how much the device has.
///
/// Stable and finely grained enough to help fingerprint a device across apps,
/// which is why Apple made it a "required reason" API — an App Store build must
/// declare why it looks.
public struct LiveStorageSource: SensorSource {
    public let id: SensorID = "device.storage"

    public init() {}

    public func availability() async -> SensorAvailability { .ready }

    public func read() async -> SensorSample? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]) else { return nil }

        let gigabyte = 1_073_741_824.0
        var fields: [SensorField] = []

        if let free = values.volumeAvailableCapacityForImportantUsage {
            fields.append(SensorField("Free", .number(Double(free) / gigabyte, unit: "GB")))
        }
        if let total = values.volumeTotalCapacity {
            fields.append(SensorField("Capacity", .number(Double(total) / gigabyte, unit: "GB")))
            if let free = values.volumeAvailableCapacityForImportantUsage, total > 0 {
                let used = (1 - Double(free) / Double(total)) * 100
                fields.append(SensorField("Used", .number(used, unit: "%")))
            }
        }

        return fields.isEmpty
            ? nil
            : SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }
}

/// How long since the phone was restarted.
///
/// Boot time is a classic cross-app fingerprint: it is identical for every app
/// on the device and stable until the next reboot, which for most people is
/// weeks. Another of Apple's required-reason categories.
public struct LiveUptimeSource: SensorSource {
    public let id: SensorID = "device.uptime"

    public init() {}

    public func availability() async -> SensorAvailability { .ready }

    public func read() async -> SensorSample? {
        let uptime = ProcessInfo.processInfo.systemUptime
        let bootedAt = Date().timeIntervalSince1970 - uptime

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Uptime", .number(uptime / 3600, unit: "hours")),
            SensorField("Booted", .time(bootedAt)),
            // The point of showing this: every app on the phone computes the
            // same value, which makes it a shared identifier nobody granted.
            SensorField("Same for every app", .boolean(true)),
        ])
    }
}

/// Whether Low Power Mode is on.
public struct LiveLowPowerModeSource: SensorSource {
    public let id: SensorID = "device.low_power_mode"

    public init() {}

    public func availability() async -> SensorAvailability { .ready }

    public func read() async -> SensorSample? {
        SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Low Power Mode", .boolean(ProcessInfo.processInfo.isLowPowerModeEnabled)),
        ])
    }
}

/// What you are listening through, and what is plugged in.
///
/// No permission and no dialog. The port names are as iOS reports them, which
/// for Bluetooth means the accessory's own advertised name — often a person's
/// name, since people call their earbuds after themselves.
public struct LiveAudioRouteSource: SensorSource {
    public let id: SensorID = "av.audio_route"

    public init() {}

    public func availability() async -> SensorAvailability { .ready }

    public func read() async -> SensorSample? {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute

        let outputs = route.outputs.map(\.portName)
        let outputTypes = route.outputs.map(\.portType.rawValue)
        let inputs = route.inputs.map(\.portName)

        var fields: [SensorField] = [
            SensorField("Listening through", .text(outputs.isEmpty ? "nothing" : outputs.joined(separator: ", "))),
            SensorField("Output type", .text(outputTypes.joined(separator: ", "))),
            SensorField("Volume", .number(Double(session.outputVolume) * 100, unit: "%")),
        ]

        if !inputs.isEmpty {
            fields.append(SensorField("Microphone", .text(inputs.joined(separator: ", "))))
        }
        fields.append(SensorField("Other audio playing", .boolean(session.isOtherAudioPlaying)))

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }
}

/// Which cellular technology the phone is using.
///
/// Included as much to show the sandbox tightening as to report a value:
/// carrier identity used to be readable here and was removed in iOS 16, with
/// `CTCarrier` deprecated and no replacement offered.
public struct LiveRadioTechnologySource: SensorSource {
    public let id: SensorID = "telephony.radio_technology"

    public init() {}

    public func availability() async -> SensorAvailability { .ready }

    public func read() async -> SensorSample? {
        let info = CTTelephonyNetworkInfo()

        // Measured trap: in a Simulator this is an EMPTY DICTIONARY inside a
        // non-nil Optional, so unwrapping succeeds and yields nothing. Treat
        // empty as "no cellular", not as a failure.
        guard let technologies = info.serviceCurrentRadioAccessTechnology,
              !technologies.isEmpty
        else {
            return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("Cellular", .text("no service reported")),
            ])
        }

        var fields: [SensorField] = technologies.values.enumerated().map { index, raw in
            SensorField(technologies.count == 1 ? "Technology" : "SIM \(index + 1)",
                        .text(Self.friendly(raw)))
        }
        fields.append(SensorField("SIMs reporting", .integer(technologies.count)))
        // The teaching point, not a reading.
        fields.append(SensorField("Carrier name", .text("removed by Apple in iOS 16")))

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }

    static func friendly(_ raw: String) -> String {
        switch raw {
        case CTRadioAccessTechnologyNR: "5G (standalone)"
        case CTRadioAccessTechnologyNRNSA: "5G"
        case CTRadioAccessTechnologyLTE: "LTE"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA: "3G"
        case CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyGPRS: "2G"
        default: raw.replacingOccurrences(of: "CTRadioAccessTechnology", with: "")
        }
    }
}
#endif
