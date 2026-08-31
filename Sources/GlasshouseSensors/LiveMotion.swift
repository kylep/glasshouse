#if os(iOS)
import Foundation
import CoreMotion
import GlasshouseCore

/// Holds the one `CMMotionManager` the app needs.
///
/// Core Motion requires a manager that outlives a single read, and
/// `CMMotionManager` is not `Sendable`.
@MainActor
final class MotionManagerBox {
    static let shared = MotionManagerBox()
    let manager = CMMotionManager()
    let altimeter = CMAltimeter()

    private init() {
        manager.accelerometerUpdateInterval = 0.1
        manager.gyroUpdateInterval = 0.1
        manager.deviceMotionUpdateInterval = 0.1
    }
}

/// Raw acceleration in three axes.
///
/// Measured: every Core Motion availability check returns false in the
/// Simulator, and there is no injection mechanism at any layer — no `simctl`
/// subcommand, no Simulator.app menu item, nothing. `Features → Shake` sends a
/// UIKit event, not sensor samples.
///
/// This adapter therefore reports unavailable on anything but a device, and the
/// app shows replayed traces instead. That is not a workaround; it is the only
/// possible arrangement.
public struct LiveAccelerometerSource: SensorSource {
    public let id: SensorID = "core_motion.accelerometer"

    public init() {}

    public func availability() async -> SensorAvailability {
        await MainActor.run {
            guard MotionManagerBox.shared.manager.isAccelerometerAvailable else {
                return .unavailable(reason: RuntimeEnvironment.current == .simulator
                    ? .simulator
                    : .hardwareAbsent)
            }
            return .ready
        }
    }

    public func read() async -> SensorSample? {
        await MainActor.run {
            let manager = MotionManagerBox.shared.manager
            guard manager.isAccelerometerAvailable else { return nil }
            if !manager.isAccelerometerActive { manager.startAccelerometerUpdates() }
            guard let data = manager.accelerometerData else { return nil }

            return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("X", .number(data.acceleration.x, unit: "g")),
                SensorField("Y", .number(data.acceleration.y, unit: "g")),
                SensorField("Z", .number(data.acceleration.z, unit: "g")),
            ])
        }
    }
}

/// Rotation rate around each axis.
public struct LiveGyroscopeSource: SensorSource {
    public let id: SensorID = "core_motion.gyroscope"

    public init() {}

    public func availability() async -> SensorAvailability {
        await MainActor.run {
            MotionManagerBox.shared.manager.isGyroAvailable
                ? .ready
                : .unavailable(reason: RuntimeEnvironment.current == .simulator ? .simulator : .hardwareAbsent)
        }
    }

    public func read() async -> SensorSample? {
        await MainActor.run {
            let manager = MotionManagerBox.shared.manager
            guard manager.isGyroAvailable else { return nil }
            if !manager.isGyroActive { manager.startGyroUpdates() }
            guard let data = manager.gyroData else { return nil }

            return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("X", .number(data.rotationRate.x, unit: "rad/s")),
                SensorField("Y", .number(data.rotationRate.y, unit: "rad/s")),
                SensorField("Z", .number(data.rotationRate.z, unit: "rad/s")),
            ])
        }
    }
}

/// Air pressure and relative altitude — sensitive enough to detect one flight
/// of stairs.
public struct LiveAltimeterSource: SensorSource {
    public let id: SensorID = "core_motion.altimeter_relative"

    public init() {}

    public func availability() async -> SensorAvailability {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            return .unavailable(reason: RuntimeEnvironment.current == .simulator
                ? .simulator
                : .hardwareAbsent)
        }
        return Self.map(CMAltimeter.authorizationStatus())
    }

    public func read() async -> SensorSample? {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return nil }

        return await withCheckedContinuation { continuation in
            var resumed = false
            Task { @MainActor in
                MotionManagerBox.shared.altimeter.startRelativeAltitudeUpdates(to: .main) { data, _ in
                    guard !resumed, let data else { return }
                    resumed = true
                    MotionManagerBox.shared.altimeter.stopRelativeAltitudeUpdates()
                    continuation.resume(returning: SensorSample(
                        sensor: SensorID("core_motion.altimeter_relative"),
                        timestamp: Date().timeIntervalSince1970,
                        fields: [
                            SensorField("Pressure", .number(data.pressure.doubleValue, unit: "kPa")),
                            SensorField("Relative altitude", .number(data.relativeAltitude.doubleValue, unit: "m")),
                        ]
                    ))
                }
            }
        }
    }

    static func map(_ status: CMAuthorizationStatus) -> SensorAvailability {
        switch status {
        case .notDetermined: .needsPermission
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .ready
        @unknown default: .needsPermission
        }
    }
}

/// Steps, distance, and floors — including history recorded long before this
/// app was installed.
public struct LivePedometerSource: SensorSource {
    public let id: SensorID = "core_motion.pedometer"

    public init() {}

    public func availability() async -> SensorAvailability {
        guard CMPedometer.isStepCountingAvailable() else {
            return .unavailable(reason: RuntimeEnvironment.current == .simulator
                ? .simulator
                : .hardwareAbsent)
        }
        return LiveAltimeterSource.map(CMPedometer.authorizationStatus())
    }

    public func read() async -> SensorSample? {
        guard CMPedometer.isStepCountingAvailable() else { return nil }

        let pedometer = CMPedometer()
        let start = Date().addingTimeInterval(-86_400)

        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: Date()) { data, _ in
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                var fields: [SensorField] = [
                    SensorField("Steps (24h)", .integer(data.numberOfSteps.intValue)),
                ]
                if let distance = data.distance {
                    fields.append(SensorField("Distance (24h)", .number(distance.doubleValue, unit: "m")))
                }
                if let floors = data.floorsAscended {
                    fields.append(SensorField("Floors climbed", .integer(floors.intValue)))
                }
                continuation.resume(returning: SensorSample(
                    sensor: SensorID("core_motion.pedometer"),
                    timestamp: Date().timeIntervalSince1970,
                    fields: fields
                ))
            }
        }
    }
}
#endif
