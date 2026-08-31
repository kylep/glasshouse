#if os(iOS)
import Foundation
import UIKit
import GlasshouseCore

// Device state: everything readable without ever asking.
//
// These adapters exist to make a point as much as to report a value. None of
// them triggers a dialog, appears in Settings, or leaves any trace the user can
// inspect afterwards.

/// Battery level and charging state.
///
/// Historically a tracking vector precisely because it needs no permission and
/// changes predictably — browsers removed the equivalent web API for that reason.
public struct LiveBatterySource: SensorSource {
    public let id: SensorID = "device.battery"

    public init() {}

    public func availability() async -> SensorAvailability {
        // The level is populated asynchronously after monitoring is enabled, so
        // reading it in the same breath can see -1 on a device that plainly has
        // a battery. Enable, yield, then check — otherwise the very first
        // refresh reports "this device doesn't have the hardware" on a phone.
        await MainActor.run { UIDevice.current.isBatteryMonitoringEnabled = true }

        for _ in 0..<6 {
            let ready = await MainActor.run {
                UIDevice.current.isBatteryMonitoringEnabled && UIDevice.current.batteryLevel >= 0
            }
            if ready { return .ready }
            try? await Task.sleep(for: .milliseconds(50))
        }

        // The Simulator refuses to enable monitoring at all and pins the level
        // at -1, so it always lands here — correctly.
        return .unavailable(reason: RuntimeEnvironment.current == .simulator
            ? .simulator
            : .hardwareAbsent)
    }

    public func read() async -> SensorSample? {
        await MainActor.run {
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            guard device.batteryLevel >= 0 else { return nil }

            let state: String = switch device.batteryState {
            case .charging: "charging"
            case .full: "full"
            case .unplugged: "unplugged"
            default: "unknown"
            }

            return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("Level", .number(Double(device.batteryLevel) * 100, unit: "%")),
                SensorField("State", .text(state)),
                SensorField("Low Power Mode", .boolean(ProcessInfo.processInfo.isLowPowerModeEnabled)),
            ])
        }
    }
}

/// Thermal state, power mode, storage, and uptime.
///
/// Individually mundane. Together — and combined with locale — a durable
/// fingerprint, which is why boot time and disk space are two of Apple's five
/// "required reason" API categories.
public struct LiveSystemStateSource: SensorSource {
    public let id: SensorID = "device.thermal"

    public init() {}

    public func availability() async -> SensorAvailability { .ready }

    public func read() async -> SensorSample? {
        let info = ProcessInfo.processInfo

        let thermal: String = switch info.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Thermal state", .text(thermal)),
            SensorField("Low Power Mode", .boolean(info.isLowPowerModeEnabled)),
            SensorField("Uptime", .number(info.systemUptime, unit: "s")),
            SensorField("Processors", .integer(info.processorCount)),
            SensorField("Memory", .number(Double(info.physicalMemory) / 1_073_741_824, unit: "GB")),
        ])
    }
}

/// Language, region, time zone, and calendar.
///
/// Time zone is the strongest element here: it is coarse location that no
/// permission gates and no prompt mentions.
public struct LiveLocaleSource: SensorSource {
    public let id: SensorID = "device.locale"

    public init() {}

    public func availability() async -> SensorAvailability { .ready }

    public func read() async -> SensorSample? {
        let locale = Locale.current
        let zone = TimeZone.current

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Language", .text(locale.identifier)),
            SensorField("Region", .text(locale.region?.identifier ?? "unknown")),
            SensorField("Time zone", .text(zone.identifier)),
            SensorField("UTC offset", .number(Double(zone.secondsFromGMT()) / 3600, unit: "h")),
            SensorField("Measurement", .text("\(locale.measurementSystem)")),
            SensorField("Preferred languages", .text(Locale.preferredLanguages.prefix(3).joined(separator: ", "))),
        ])
    }
}

/// The identifier linking everything one developer's apps see you do.
public struct LiveVendorIdentifierSource: SensorSource {
    public let id: SensorID = "device.identifier_for_vendor"

    public init() {}

    public func availability() async -> SensorAvailability {
        // Nil before the first unlock after a reboot.
        await MainActor.run {
            UIDevice.current.identifierForVendor == nil ? .unavailable(reason: .hardwareAbsent) : .ready
        }
    }

    public func read() async -> SensorSample? {
        await MainActor.run {
            guard let identifier = UIDevice.current.identifierForVendor else { return nil }
            return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("Identifier", .text(identifier.uuidString)),
                SensorField("Model", .text(UIDevice.current.model)),
                SensorField("System", .text("\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")),
            ])
        }
    }
}

/// Accessibility settings, which can imply a disability and are gated by nothing.
public struct LiveAccessibilitySource: SensorSource {
    public let id: SensorID = "device.accessibility"

    public init() {}

    public func availability() async -> SensorAvailability { .ready }

    public func read() async -> SensorSample? {
        await MainActor.run {
            SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("VoiceOver", .boolean(UIAccessibility.isVoiceOverRunning)),
                SensorField("Switch Control", .boolean(UIAccessibility.isSwitchControlRunning)),
                SensorField("Bold text", .boolean(UIAccessibility.isBoldTextEnabled)),
                SensorField("Reduce motion", .boolean(UIAccessibility.isReduceMotionEnabled)),
                SensorField("Reduce transparency", .boolean(UIAccessibility.isReduceTransparencyEnabled)),
                SensorField("Darker system colors", .boolean(UIAccessibility.isDarkerSystemColorsEnabled)),
                SensorField("Differentiate without color", .boolean(UIAccessibility.shouldDifferentiateWithoutColor)),
                SensorField("Larger text", .text(UIApplication.shared.preferredContentSizeCategory.rawValue)),
            ])
        }
    }
}

/// Whether the screen is being recorded or mirrored.
public struct LiveScreenCaptureSource: SensorSource {
    public let id: SensorID = "device.screen_capture"

    public init() {}

    public func availability() async -> SensorAvailability { .ready }

    public func read() async -> SensorSample? {
        await MainActor.run {
            SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("Being captured", .boolean(UIScreen.main.isCaptured)),
                SensorField("Screens attached", .integer(UIScreen.screens.count)),
                SensorField("Brightness", .number(Double(UIScreen.main.brightness) * 100, unit: "%")),
            ])
        }
    }
}
#endif
