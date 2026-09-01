#if os(iOS)
import Foundation
import CoreLocation
import GlasshouseCore

/// Holds the one `CLLocationManager` the app needs.
///
/// A manager has to outlive a single read: authorization and location callbacks
/// arrive on it, and a freshly created manager has no cached fix to report. It
/// is `@MainActor` because `CLLocationManager` is not `Sendable`.
@MainActor
final class LocationManagerBox: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManagerBox()

    let manager = CLLocationManager()

    fileprivate var authorizationWaiters: [SingleResume<CLAuthorizationStatus>] = []
    fileprivate var fixWaiters: [SingleResume<CLLocation>] = []
    fileprivate var headingWaiters: [SingleResume<Bool>] = []

    /// Private so nobody creates a second manager whose delegate callbacks
    /// would resume none of the waiters above.
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }
    var accuracy: CLAccuracyAuthorization { manager.accuracyAuthorization }
    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    /// Requests when-in-use access and waits for an answer.
    ///
    /// Bounded, because the user may background the app with the dialog open,
    /// or the dialog may be suppressed entirely — by Screen Time, or by a build
    /// missing its usage-description key. An unbounded wait there leaves the
    /// requesting UI spinning for the life of the process.
    func requestWhenInUse(timeout: Double = 60) async -> CLAuthorizationStatus {
        guard status == .notDetermined else { return status }

        let answered = await withTimeout(seconds: timeout) {
            await withCheckedContinuation { (continuation: CheckedContinuation<CLAuthorizationStatus?, Never>) in
                let once = SingleResume(continuation)
                Task { @MainActor in
                    let box = LocationManagerBox.shared
                    box.authorizationWaiters.append(once)
                    box.manager.requestWhenInUseAuthorization()
                }
            }
        } ?? nil

        return answered ?? status
    }

    /// Asks for a fresh fix and waits for it, rather than reading whatever
    /// happened to be cached.
    ///
    /// `requestLocation()` is asynchronous: the fix arrives via the delegate.
    /// Reading `manager.location` immediately after calling it returns nil on a
    /// newly authorized manager, so the first read after granting permission
    /// would always come back empty.
    func requestFix(timeout: Double = 10) async -> CLLocation? {
        guard isAuthorized else { return nil }

        // A recent cached fix is a perfectly good answer and avoids waking the
        // radio unnecessarily.
        if let cached = manager.location, Date().timeIntervalSince(cached.timestamp) < 30 {
            return cached
        }

        let fix = await withTimeout(seconds: timeout) {
            await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
                let once = SingleResume(continuation)
                Task { @MainActor in
                    let box = LocationManagerBox.shared
                    box.fixWaiters.append(once)
                    box.manager.requestLocation()
                }
            }
        } ?? nil

        return fix ?? manager.location
    }

    /// Starts the compass, waits for one reading, then stops it again.
    ///
    /// `manager.heading` is nil until `startUpdatingHeading()` has been called,
    /// so without this the heading sensor could never report anything at all.
    func requestHeading(timeout: Double = 5) async -> Bool {
        guard CLLocationManager.headingAvailable() else { return false }

        let arrived = await withTimeout(seconds: timeout) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
                let once = SingleResume(continuation)
                Task { @MainActor in
                    let box = LocationManagerBox.shared
                    box.headingWaiters.append(once)
                    box.manager.startUpdatingHeading()
                }
            }
        } ?? nil

        manager.stopUpdatingHeading()
        return arrived ?? (lastHeading != nil)
    }

    // MARK: - Delegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Deliberately does not capture `manager`: CLLocationManager is not
        // Sendable and must not cross into the MainActor task.
        Task { @MainActor in
            let status = LocationManagerBox.shared.manager.authorizationStatus
            guard status != .notDetermined else { return }
            LocationManagerBox.shared.drainAuthorization(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinates = locations.map {
            (lat: $0.coordinate.latitude, lon: $0.coordinate.longitude,
             alt: $0.altitude, hAcc: $0.horizontalAccuracy, vAcc: $0.verticalAccuracy,
             speed: $0.speed, course: $0.course, time: $0.timestamp)
        }
        Task { @MainActor in
            guard let last = coordinates.last else { return }
            let location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: last.lat, longitude: last.lon),
                altitude: last.alt, horizontalAccuracy: last.hAcc, verticalAccuracy: last.vAcc,
                course: last.course, speed: last.speed, timestamp: last.time
            )
            LocationManagerBox.shared.drainFix(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let magnetic = newHeading.magneticHeading
        let trueHeading = newHeading.trueHeading
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor in
            LocationManagerBox.shared.drainHeading(magnetic: magnetic, true: trueHeading, accuracy: accuracy)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Failure must resume the waiters too, or a denied or unavailable fix
        // leaves the caller waiting for its full timeout every single read.
        Task { @MainActor in
            LocationManagerBox.shared.drainFix(nil)
        }
    }

    // MARK: - Waiter plumbing

    private func drainAuthorization(_ status: CLAuthorizationStatus) {
        let waiting = authorizationWaiters
        authorizationWaiters.removeAll()
        for waiter in waiting { waiter.resume(status) }
    }

    private func drainFix(_ location: CLLocation?) {
        let waiting = fixWaiters
        fixWaiters.removeAll()
        for waiter in waiting { waiter.resume(location) }
    }

    private(set) var lastHeading: (magnetic: Double, trueHeading: Double, accuracy: Double)?

    private func drainHeading(magnetic: Double, true trueHeading: Double, accuracy: Double) {
        lastHeading = (magnetic, trueHeading, accuracy)
        let waiting = headingWaiters
        headingWaiters.removeAll()
        for waiter in waiting { waiter.resume(true) }
    }
}

/// Where you are, and how precisely the app is allowed to know it.
///
/// The one sensor a Simulator can genuinely drive:
/// `xcrun simctl location booted start --speed=15 --interval=1 lat,lon lat,lon`
public struct LiveLocationSource: SensorSource {
    public let id: SensorID = "core_location.position"

    public init() {}

    public func availability() async -> SensorAvailability {
        // `locationServicesEnabled()` can block, and Apple warns against calling
        // it on the main thread — so it is read off the MainActor first.
        let servicesOn = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        guard servicesOn else { return .unavailable(reason: .hardwareAbsent) }

        return await MainActor.run {
            Self.map(LocationManagerBox.shared.status, accuracy: LocationManagerBox.shared.accuracy)
        }
    }

    public func requestAccess() async -> SensorAvailability {
        let status = await LocationManagerBox.shared.requestWhenInUse()
        let accuracy = await MainActor.run { LocationManagerBox.shared.accuracy }
        return Self.map(status, accuracy: accuracy)
    }

    public func read() async -> SensorSample? {
        guard let location = await LocationManagerBox.shared.requestFix() else { return nil }
        let reduced = await MainActor.run { LocationManagerBox.shared.accuracy } == .reducedAccuracy

        var fields: [SensorField] = [
            SensorField("Coordinate", .coordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )),
            SensorField("Accuracy", .number(location.horizontalAccuracy, unit: "m")),
            SensorField("Precision granted", .text(reduced ? "approximate" : "precise")),
        ]

        if location.verticalAccuracy >= 0 {
            fields.append(SensorField("Altitude", .number(location.altitude, unit: "m")))
        }
        if location.speed >= 0 {
            fields.append(SensorField("Speed", .number(location.speed, unit: "m/s")))
        }
        if location.course >= 0 {
            fields.append(SensorField("Course", .number(location.course, unit: "°")))
        }
        fields.append(SensorField("Fix taken", .time(location.timestamp.timeIntervalSince1970)))

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }

    static func map(_ status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) -> SensorAvailability {
        switch status {
        case .notDetermined: .needsPermission
        case .denied: .denied
        case .restricted: .restricted
        case .authorizedAlways, .authorizedWhenInUse:
            // Reduced accuracy is genuinely partial access — the same shape as
            // a limited photo library — so it reports as `.limited` rather than
            // overstating what the app can see.
            accuracy == .reducedAccuracy ? .limited : .ready
        @unknown default: .needsPermission
        }
    }
}

/// Which way the phone is pointing. Needs the magnetometer, so it is
/// device-only — `headingAvailable()` is false in every Simulator.
public struct LiveHeadingSource: SensorSource {
    public let id: SensorID = "core_location.heading"

    public init() {}

    public func availability() async -> SensorAvailability {
        guard CLLocationManager.headingAvailable() else {
            return .unavailable(reason: RuntimeEnvironment.current == .simulator
                ? .simulator
                : .hardwareAbsent)
        }
        return await MainActor.run {
            LiveLocationSource.map(LocationManagerBox.shared.status,
                                   accuracy: LocationManagerBox.shared.accuracy)
        }
    }

    /// There is no separate compass permission. Heading declares the same
    /// usage-description key as location, so this asks the location question —
    /// and granting it here grants location too, and vice versa.
    ///
    /// Without this override the protocol default applied, which asks for
    /// nothing and merely re-reads the current state: the button was inert.
    public func requestAccess() async -> SensorAvailability {
        _ = await LocationManagerBox.shared.requestWhenInUse()
        return await availability()
    }

    public func read() async -> SensorSample? {
        guard CLLocationManager.headingAvailable(),
              await LocationManagerBox.shared.requestHeading(),
              let reading = await MainActor.run(resultType: (magnetic: Double, trueHeading: Double, accuracy: Double)?.self, body: {
                  LocationManagerBox.shared.lastHeading
              })
        else { return nil }

        var fields: [SensorField] = [
            SensorField("Magnetic heading", .number(reading.magnetic, unit: "°")),
            SensorField("Accuracy", .number(reading.accuracy, unit: "°")),
        ]
        // True heading is -1 unless location updates are also active. Reporting
        // -1 as a bearing would be worse than omitting it.
        if reading.trueHeading >= 0 {
            fields.append(SensorField("True heading", .number(reading.trueHeading, unit: "°")))
        }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }
}
#endif
