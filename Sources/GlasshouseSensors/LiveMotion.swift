#if os(iOS)
import Foundation
import CoreMotion
import GlasshouseCore

/// Plain values carried out of Core Motion.
///
/// `CMMotionManager`, `CMAltimeter`, and `CMPedometer` are not `Sendable`, so
/// none of them may leave the MainActor. Every read below happens inside
/// `MotionManagerBox` and returns one of these instead.
struct Axes: Sendable {
    let x: Double
    let y: Double
    let z: Double
}

struct Altitude: Sendable {
    let pressure: Double
    let relativeAltitude: Double
}

struct Steps: Sendable {
    let count: Int
    let distance: Double?
    let floors: Int?
}

/// Owns every Core Motion object in the app.
///
/// Two reasons these must outlive a single read. `CMMotionManager` publishes
/// samples into itself over time, so a fresh one has nothing to report. And
/// `CMPedometer` must stay alive for the duration of a query — a local one is
/// released the moment the enclosing function returns, and its completion
/// handler may then never fire, hanging the caller forever.
@MainActor
final class MotionManagerBox {
    static let shared = MotionManagerBox()

    private let manager = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let pedometer = CMPedometer()

    /// Serialises altimeter reads. A single shared `CMAltimeter` cannot serve
    /// two overlapping `startRelativeAltitudeUpdates` calls: the second
    /// replaces the first's handler, and one of the two callers then waits
    /// forever.
    private var altimeterBusy = false

    private init() {
        manager.accelerometerUpdateInterval = 0.1
        manager.gyroUpdateInterval = 0.1
    }

    // MARK: - Availability

    var accelerometerAvailable: Bool { manager.isAccelerometerAvailable }
    var gyroscopeAvailable: Bool { manager.isGyroAvailable }

    // MARK: - Reads

    /// Starts a motion sensor, waits briefly for its first sample, then stops it.
    ///
    /// `accelerometerData` is nil until a sample lands, so reading immediately
    /// after `start` always returns nothing — the first refresh on a real
    /// device would show the sensor as mysteriously silent. Leaving it running
    /// instead would keep the accelerometer at 10 Hz for the life of the
    /// process, which is precisely the battery behaviour this app criticises.
    func readAccelerometer(attempts: Int = 12) async -> Axes? {
        guard manager.isAccelerometerAvailable else { return nil }
        manager.startAccelerometerUpdates()
        defer { manager.stopAccelerometerUpdates() }

        for _ in 0..<attempts {
            if let a = manager.accelerometerData?.acceleration {
                return Axes(x: a.x, y: a.y, z: a.z)
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    func readGyroscope(attempts: Int = 12) async -> Axes? {
        guard manager.isGyroAvailable else { return nil }
        manager.startGyroUpdates()
        defer { manager.stopGyroUpdates() }

        for _ in 0..<attempts {
            if let r = manager.gyroData?.rotationRate {
                return Axes(x: r.x, y: r.y, z: r.z)
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    /// Takes one barometer reading, then stops the sensor again.
    ///
    /// Resumes exactly once on every path — sample, error, or timeout — and
    /// always stops updates. An earlier version returned from the handler
    /// without resuming when Core Motion reported an error, which hung the
    /// caller forever and left the barometer running; because
    /// `SensorRegistry.snapshotAll` awaits a task group over every capability,
    /// that one stall froze the entire sensor list.
    func readAltitude(timeout: Double = 3) async -> Altitude? {
        guard CMAltimeter.isRelativeAltitudeAvailable(), !altimeterBusy else { return nil }
        altimeterBusy = true
        defer { altimeterBusy = false }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Altitude?, Never>) in
            let once = SingleResume(continuation)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                if once.resume(nil) { MotionManagerBox.shared.stopAltimeter() }
            }

            // Deliberately does NOT use MainActor.assumeIsolated here, which is
            // what crashed the app the moment Motion & Fitness was granted.
            //
            // `to: .main` delivers on OperationQueue.main, which runs on the
            // main *thread* — but that is not the same as being isolated to the
            // MainActor's executor. `assumeIsolated` asserts executor identity
            // and traps when it does not match, which is a hard crash rather
            // than a warning.
            //
            // So the handler touches no actor-isolated state at all: it pulls
            // plain Doubles out of the sample, resumes, and hops to the
            // MainActor separately to stop the sensor.
            altimeter.startRelativeAltitudeUpdates(to: .main) { data, error in
                let reading: Altitude? = if error == nil, let data {
                    Altitude(
                        pressure: data.pressure.doubleValue,
                        relativeAltitude: data.relativeAltitude.doubleValue
                    )
                } else {
                    nil
                }

                if once.resume(reading) {
                    Task { @MainActor in MotionManagerBox.shared.stopAltimeter() }
                }
            }
        }
    }

    /// Stops the barometer. MainActor-isolated because `CMAltimeter` is not
    /// Sendable and must only be touched from here.
    func stopAltimeter() {
        altimeter.stopRelativeAltitudeUpdates()
    }

    /// Triggers the Motion & Fitness dialog and waits for an answer.
    ///
    /// Core Motion has no `requestAuthorization` call — unlike Core Location or
    /// Photos, the dialog appears the first time a gated sensor is *started*.
    /// So asking means starting it and then watching the authorization status.
    ///
    /// The wait is generous because a person has to read a dialog and decide.
    func askForMotionAccess(startingWith trigger: @escaping @Sendable () async -> Void) async {
        guard CMPedometer.authorizationStatus() == .notDetermined else { return }
        await trigger()

        for _ in 0..<120 {
            if CMPedometer.authorizationStatus() != .notDetermined { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// Queries the last 24 hours of step data.
    ///
    /// The pedometer is a stored property rather than a local, because a local
    /// one is released as soon as the calling function returns and its
    /// completion handler may then never fire.
    /// Set false while `queryPedometerData` is under investigation.
    ///
    /// On an iPhone 14 Pro running iOS 26.6, with Motion & Fitness granted
    /// (authorizationStatus == .authorized) and NSMotionUsageDescription
    /// present in the bundle, this call terminates the process with SIGTRAP
    /// before ever invoking its completion handler. Verified by bisection:
    /// skipping the query alone lets the whole refresh finish normally.
    ///
    /// Quarantined rather than removed, because one crashing sensor should not
    /// take down an app whose entire purpose is showing the other forty.
    nonisolated static let pedometerQueryEnabled = false

    func readSteps(timeout: Double = 5) async -> Steps? {
        guard CMPedometer.isStepCountingAvailable(),
              Self.pedometerQueryEnabled
        else { return nil }

        let now = Date()
        let start = now.addingTimeInterval(-86_400)

        return await withCheckedContinuation { (continuation: CheckedContinuation<Steps?, Never>) in
            let once = SingleResume(continuation)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                once.resume(nil)
            }

            pedometer.queryPedometerData(from: start, to: now) { data, _ in
                guard let data else {
                    once.resume(nil)
                    return
                }
                once.resume(Steps(
                    count: data.numberOfSteps.intValue,
                    distance: data.distance?.doubleValue,
                    floors: data.floorsAscended?.intValue
                ))
            }
        }
    }
}

/// Raw acceleration in three axes.
///
/// Measured: every Core Motion availability check returns false in the
/// Simulator, and no `simctl` facility injects motion data. `Features → Shake`
/// sends a UIKit event, not sensor samples. So this reports unavailable on
/// anything but a device, by construction rather than by omission.
public struct LiveAccelerometerSource: SensorSource {
    public let id: SensorID = "core_motion.accelerometer"

    public init() {}

    public func availability() async -> SensorAvailability {
        await MotionManagerBox.shared.accelerometerAvailable
            ? .ready
            : .unavailable(reason: RuntimeEnvironment.current == .simulator ? .simulator : .hardwareAbsent)
    }

    public func read() async -> SensorSample? {
        guard let axes = await MotionManagerBox.shared.readAccelerometer() else { return nil }
        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("X", .number(axes.x, unit: "g")),
            SensorField("Y", .number(axes.y, unit: "g")),
            SensorField("Z", .number(axes.z, unit: "g")),
        ])
    }
}

/// Rotation rate around each axis.
public struct LiveGyroscopeSource: SensorSource {
    public let id: SensorID = "core_motion.gyroscope"

    public init() {}

    public func availability() async -> SensorAvailability {
        await MotionManagerBox.shared.gyroscopeAvailable
            ? .ready
            : .unavailable(reason: RuntimeEnvironment.current == .simulator ? .simulator : .hardwareAbsent)
    }

    public func read() async -> SensorSample? {
        guard let axes = await MotionManagerBox.shared.readGyroscope() else { return nil }
        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("X", .number(axes.x, unit: "rad/s")),
            SensorField("Y", .number(axes.y, unit: "rad/s")),
            SensorField("Z", .number(axes.z, unit: "rad/s")),
        ])
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

    /// Starting the barometer is what raises the Motion & Fitness dialog;
    /// there is no separate authorization call to make. Without this override
    /// the protocol default applied, which asks for nothing — the button did
    /// nothing at all.
    public func requestAccess() async -> SensorAvailability {
        await MotionManagerBox.shared.askForMotionAccess {
            _ = await MotionManagerBox.shared.readAltitude(timeout: 1)
        }
        return await availability()
    }

    public func read() async -> SensorSample? {
        guard let reading = await MotionManagerBox.shared.readAltitude() else { return nil }
        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Pressure", .number(reading.pressure, unit: "kPa")),
            SensorField("Relative altitude", .number(reading.relativeAltitude, unit: "m")),
        ])
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
        // Reported honestly rather than as `.ready`. Claiming readiness and
        // then returning nothing is exactly the "silent failure" this project
        // exists to make impossible, and it made the app's own anomaly detector
        // flag a mystery whose cause is known and written down.
        guard MotionManagerBox.pedometerQueryEnabled else {
            return .unavailable(reason: .knownDefect)
        }
        guard CMPedometer.isStepCountingAvailable() else {
            return .unavailable(reason: RuntimeEnvironment.current == .simulator
                ? .simulator
                : .hardwareAbsent)
        }
        return LiveAltimeterSource.map(CMPedometer.authorizationStatus())
    }

    /// As with the barometer, running the query is what raises the dialog.
    public func requestAccess() async -> SensorAvailability {
        await MotionManagerBox.shared.askForMotionAccess {
            _ = await MotionManagerBox.shared.readSteps(timeout: 1)
        }
        return await availability()
    }

    public func read() async -> SensorSample? {
        guard let steps = await MotionManagerBox.shared.readSteps() else { return nil }

        var fields: [SensorField] = [
            SensorField("Steps (24h)", .integer(steps.count)),
        ]
        if let distance = steps.distance {
            fields.append(SensorField("Distance (24h)", .number(distance, unit: "m")))
        }
        if let floors = steps.floors {
            fields.append(SensorField("Floors climbed", .integer(floors)))
        }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }
}
#endif
