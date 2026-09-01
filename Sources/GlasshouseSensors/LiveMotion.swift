#if os(iOS)
import Foundation
import CoreMotion
import AVFoundation
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

struct Attitude: Sendable {
    let pitch: Double
    let roll: Double
    let yaw: Double
    let gravityX: Double
    let gravityY: Double
    let gravityZ: Double
    let userAcceleration: Double
}

struct AbsoluteAltitude: Sendable {
    let altitude: Double
    let accuracy: Double
    let precision: Double
}

struct ActivityGuess: Sendable {
    let kind: String
    let confidence: String
    let startedAt: Double
    let sampleCount: Int
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
    private let headphones = CMHeadphoneMotionManager()
    private let activity = CMMotionActivityManager()

    /// Serialises altimeter reads. A single shared `CMAltimeter` cannot serve
    /// two overlapping `startRelativeAltitudeUpdates` calls: the second
    /// replaces the first's handler, and one of the two callers then waits
    /// forever.
    private var altimeterBusy = false
    private var absoluteBusy = false

    private init() {
        manager.accelerometerUpdateInterval = 0.1
        manager.gyroUpdateInterval = 0.1
    }

    // MARK: - Availability

    var accelerometerAvailable: Bool { manager.isAccelerometerAvailable }
    var gyroscopeAvailable: Bool { manager.isGyroAvailable }
    var magnetometerAvailable: Bool { manager.isMagnetometerAvailable }
    var deviceMotionAvailable: Bool { manager.isDeviceMotionAvailable }
    var headphoneMotionAvailable: Bool { headphones.isDeviceMotionAvailable }

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

    func readMagnetometer(attempts: Int = 12) async -> Axes? {
        guard manager.isMagnetometerAvailable else { return nil }
        manager.startMagnetometerUpdates()
        defer { manager.stopMagnetometerUpdates() }

        for _ in 0..<attempts {
            if let f = manager.magnetometerData?.magneticField {
                return Axes(x: f.x, y: f.y, z: f.z)
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    func readDeviceMotion(attempts: Int = 12) async -> Attitude? {
        guard manager.isDeviceMotionAvailable else { return nil }
        manager.startDeviceMotionUpdates()
        defer { manager.stopDeviceMotionUpdates() }

        for _ in 0..<attempts {
            if let m = manager.deviceMotion {
                let a = m.userAcceleration
                return Attitude(
                    pitch: m.attitude.pitch, roll: m.attitude.roll, yaw: m.attitude.yaw,
                    gravityX: m.gravity.x, gravityY: m.gravity.y, gravityZ: m.gravity.z,
                    userAcceleration: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
                )
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    /// AirPods head tracking. Stops immediately after one sample — leaving it
    /// running would keep the earbuds streaming motion indefinitely.
    func readHeadphoneMotion(attempts: Int = 20) async -> Attitude? {
        guard headphones.isDeviceMotionAvailable else { return nil }
        headphones.startDeviceMotionUpdates()
        defer { headphones.stopDeviceMotionUpdates() }

        for _ in 0..<attempts {
            if let m = headphones.deviceMotion {
                let a = m.userAcceleration
                return Attitude(
                    pitch: m.attitude.pitch, roll: m.attitude.roll, yaw: m.attitude.yaw,
                    gravityX: m.gravity.x, gravityY: m.gravity.y, gravityZ: m.gravity.z,
                    userAcceleration: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
                )
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    /// Height above sea level. Same single-resume discipline as the relative
    /// barometer, and deliberately no `assumeIsolated` — `to: .main` runs on
    /// the main thread but is not the MainActor's executor, and asserting
    /// otherwise is a hard crash.
    func readAbsoluteAltitude(timeout: Double = 3) async -> AbsoluteAltitude? {
        guard CMAltimeter.isAbsoluteAltitudeAvailable(), !absoluteBusy else { return nil }
        absoluteBusy = true
        defer { absoluteBusy = false }

        return await withCheckedContinuation { (continuation: CheckedContinuation<AbsoluteAltitude?, Never>) in
            let once = SingleResume(continuation)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                if once.resume(nil) { MotionManagerBox.shared.stopAbsoluteAltimeter() }
            }

            altimeter.startAbsoluteAltitudeUpdates(to: .main) { data, error in
                let reading: AbsoluteAltitude? = if error == nil, let data {
                    AbsoluteAltitude(
                        altitude: data.altitude,
                        accuracy: data.accuracy,
                        precision: data.precision
                    )
                } else {
                    nil
                }
                if once.resume(reading) {
                    Task { @MainActor in MotionManagerBox.shared.stopAbsoluteAltimeter() }
                }
            }
        }
    }

    func stopAbsoluteAltimeter() {
        altimeter.stopAbsoluteAltitudeUpdates()
    }

    /// What the OS thinks you have been doing — walking, driving, still.
    ///
    /// Uses the same historical-query shape as the pedometer, which currently
    /// terminates the process on this device. Run under the same quarantine
    /// flag so one experiment cannot take the app down.
    func readActivity(timeout: Double = 5) async -> ActivityGuess? {
        guard CMMotionActivityManager.isActivityAvailable(),
              Self.activityQueryEnabled
        else { return nil }

        let now = Date()
        let start = now.addingTimeInterval(-3_600)

        return await withCheckedContinuation { (continuation: CheckedContinuation<ActivityGuess?, Never>) in
            let once = SingleResume(continuation)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                once.resume(nil)
            }

            activity.queryActivityStarting(from: start, to: now, to: .main) { activities, _ in
                guard let latest = activities?.last else {
                    once.resume(nil)
                    return
                }
                let kind = if latest.walking { "walking" }
                    else if latest.running { "running" }
                    else if latest.automotive { "in a vehicle" }
                    else if latest.cycling { "cycling" }
                    else if latest.stationary { "stationary" }
                    else { "unknown" }

                let confidence = switch latest.confidence {
                case .high: "high"
                case .medium: "medium"
                default: "low"
                }

                once.resume(ActivityGuess(
                    kind: kind,
                    confidence: confidence,
                    startedAt: latest.startDate.timeIntervalSince1970,
                    sampleCount: activities?.count ?? 0
                ))
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
    /// Retained as a kill switch. Core Motion's historical queries were the
    /// source of a process-terminating crash once; if either regresses, this
    /// keeps one sensor from taking down an app built to show the other forty.
    nonisolated static let activityQueryEnabled = true

    /// Steps, distance and floors over the last hour.
    ///
    /// Deliberately `nonisolated`, on a detached task, with its own
    /// `CMPedometer` — and that is not a style choice, it is the difference
    /// between working and terminating the process.
    ///
    /// Driven from a `@MainActor` context against a MainActor-owned pedometer,
    /// every entry point killed the app with SIGTRAP before invoking its
    /// handler: `queryPedometerData` over 24 hours, the same over 1 hour, and
    /// `startUpdates`. Moving it off the main actor onto its own object fixed
    /// all three. See docs/TODO.md for the full bisection.
    ///
    /// The object must outlive the query, hence `withExtendedLifetime`: a local
    /// `CMPedometer` released mid-flight may never call its handler at all.
    nonisolated func readSteps(timeout: Double = 5) async -> Steps? {
        guard CMPedometer.isStepCountingAvailable() else { return nil }

        return await Task.detached(priority: .utility) { () -> Steps? in
            let pedometer = CMPedometer()
            let now = Date()
            let start = now.addingTimeInterval(-3_600)

            let result: Steps? = await withCheckedContinuation { (continuation: CheckedContinuation<Steps?, Never>) in
                let once = SingleResume(continuation)

                Task.detached {
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
            withExtendedLifetime(pedometer) {}
            return result
        }.value
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
// MARK: - The rest of Core Motion

/// The ambient magnetic field.
///
/// Indoors this is distorted by structural steel in ways stable enough to act
/// as a location fingerprint — the same building reads the same way.
public struct LiveMagnetometerSource: SensorSource {
    public let id: SensorID = "core_motion.magnetometer"

    public init() {}

    public func availability() async -> SensorAvailability {
        await MotionManagerBox.shared.magnetometerAvailable
            ? .ready
            : .unavailable(reason: RuntimeEnvironment.current == .simulator ? .simulator : .hardwareAbsent)
    }

    public func read() async -> SensorSample? {
        guard let field = await MotionManagerBox.shared.readMagnetometer() else { return nil }
        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("X", .number(field.x, unit: "µT")),
            SensorField("Y", .number(field.y, unit: "µT")),
            SensorField("Z", .number(field.z, unit: "µT")),
            SensorField("Strength", .number((field.x * field.x + field.y * field.y + field.z * field.z).squareRoot(), unit: "µT")),
        ])
    }
}

/// The fused reading: how the phone is oriented and how it is being moved.
///
/// Cleaner than any single sensor because iOS separates gravity from the
/// movement you cause, and correspondingly more revealing.
public struct LiveDeviceMotionSource: SensorSource {
    public let id: SensorID = "core_motion.device_motion"

    public init() {}

    public func availability() async -> SensorAvailability {
        await MotionManagerBox.shared.deviceMotionAvailable
            ? .ready
            : .unavailable(reason: RuntimeEnvironment.current == .simulator ? .simulator : .hardwareAbsent)
    }

    public func read() async -> SensorSample? {
        guard let motion = await MotionManagerBox.shared.readDeviceMotion() else { return nil }
        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Pitch", .number(motion.pitch * 180 / .pi, unit: "°")),
            SensorField("Roll", .number(motion.roll * 180 / .pi, unit: "°")),
            SensorField("Yaw", .number(motion.yaw * 180 / .pi, unit: "°")),
            SensorField("Gravity", .text(String(format: "%.2f, %.2f, %.2f", motion.gravityX, motion.gravityY, motion.gravityZ))),
            SensorField("Your movement", .number(motion.userAcceleration, unit: "g")),
            SensorField("Face up", .boolean(motion.gravityZ < -0.8)),
        ])
    }
}

/// Height above sea level, from the barometer plus a reference pressure.
///
/// Combined with a coordinate this identifies which floor of a building you
/// are on, which is why it is classified alongside location rather than motion.
public struct LiveAbsoluteAltitudeSource: SensorSource {
    public let id: SensorID = "core_motion.altimeter_absolute"

    public init() {}

    public func availability() async -> SensorAvailability {
        guard CMAltimeter.isAbsoluteAltitudeAvailable() else {
            // iPhone 12 and later only, so this is a genuine hardware gate on
            // older devices rather than a Simulator artefact.
            return .unavailable(reason: RuntimeEnvironment.current == .simulator
                ? .simulator
                : .hardwareAbsent)
        }
        return LiveAltimeterSource.map(CMAltimeter.authorizationStatus())
    }

    public func requestAccess() async -> SensorAvailability {
        await MotionManagerBox.shared.askForMotionAccess {
            _ = await MotionManagerBox.shared.readAbsoluteAltitude(timeout: 1)
        }
        return await availability()
    }

    public func read() async -> SensorSample? {
        guard let reading = await MotionManagerBox.shared.readAbsoluteAltitude() else { return nil }
        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Altitude", .number(reading.altitude, unit: "m")),
            SensorField("Accuracy", .number(reading.accuracy, unit: "m")),
            SensorField("Precision", .number(reading.precision, unit: "m")),
        ])
    }
}

/// The orientation of your head, streamed from AirPods.
///
/// Needs motion-capable AirPods actually connected, so on a phone with none
/// paired this reports unavailable rather than silent — which is the honest
/// answer, not a failure.
public struct LiveHeadphoneMotionSource: SensorSource {
    public let id: SensorID = "core_motion.headphone_motion"

    public init() {}

    public func availability() async -> SensorAvailability {
        guard await MotionManagerBox.shared.headphoneMotionAvailable else {
            return .unavailable(reason: RuntimeEnvironment.current == .simulator
                ? .simulator
                : .hardwareAbsent)
        }

        // `isDeviceMotionAvailable` says the API exists, not that any AirPods
        // are connected — so it stays true with nothing in your ears, and the
        // sensor then reports ready and delivers nothing forever. That is the
        // silent failure this project exists to make impossible, so check the
        // audio route for a wireless output before claiming readiness.
        guard Self.wirelessHeadphonesConnected else {
            return .unavailable(reason: .hardwareAbsent)
        }

        return LiveAltimeterSource.map(CMHeadphoneMotionManager.authorizationStatus())
    }

    /// Whether audio is currently routed to something wireless and head-worn.
    static var wirelessHeadphonesConnected: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones: true
            default: false
            }
        }
    }

    public func read() async -> SensorSample? {
        guard let motion = await MotionManagerBox.shared.readHeadphoneMotion() else { return nil }
        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Head pitch", .number(motion.pitch * 180 / .pi, unit: "°")),
            SensorField("Head roll", .number(motion.roll * 180 / .pi, unit: "°")),
            SensorField("Head yaw", .number(motion.yaw * 180 / .pi, unit: "°")),
        ])
    }
}
/// What the OS has decided you were doing, and how sure it is.
///
/// Not a raw sensor: iOS classifies your movement continuously and keeps the
/// answer, so this is a queryable history of your behaviour rather than a
/// reading of the present moment.
public struct LiveMotionActivitySource: SensorSource {
    public let id: SensorID = "core_motion.activity"

    public init() {}

    public func availability() async -> SensorAvailability {
        guard MotionManagerBox.activityQueryEnabled else {
            return .unavailable(reason: .knownDefect)
        }
        guard CMMotionActivityManager.isActivityAvailable() else {
            return .unavailable(reason: RuntimeEnvironment.current == .simulator
                ? .simulator
                : .hardwareAbsent)
        }
        return LiveAltimeterSource.map(CMMotionActivityManager.authorizationStatus())
    }

    public func requestAccess() async -> SensorAvailability {
        await MotionManagerBox.shared.askForMotionAccess {
            _ = await MotionManagerBox.shared.readActivity(timeout: 1)
        }
        return await availability()
    }

    public func read() async -> SensorSample? {
        guard let guess = await MotionManagerBox.shared.readActivity() else { return nil }
        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Doing", .text(guess.kind)),
            SensorField("Confidence", .text(guess.confidence)),
            SensorField("Since", .time(guess.startedAt)),
            SensorField("Changes in the last hour", .integer(guess.sampleCount)),
        ])
    }
}
#endif
