#if os(iOS)
import Foundation
import CoreLocation
import GlasshouseCore

/// Holds the one `CLLocationManager` the app needs.
///
/// A manager has to outlive a single read: authorization callbacks arrive on it,
/// and a freshly created manager has no cached location to report. It is
/// `@MainActor` because `CLLocationManager` is not `Sendable`.
@MainActor
final class LocationManagerBox: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManagerBox()

    let manager = CLLocationManager()
    private var authorizationContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }
    var accuracy: CLAccuracyAuthorization { manager.accuracyAuthorization }
    var lastLocation: CLLocation? { manager.location }

    /// Requests when-in-use access and waits for the user's answer.
    func requestWhenInUse() async -> CLAuthorizationStatus {
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Asks for a single fresh fix. Returns the cached one if none arrives.
    func requestFix() {
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Deliberately does not capture `manager`: CLLocationManager is not
        // Sendable, so it must not cross into the MainActor task. Read the
        // shared instance there instead — it is the same object.
        Task { @MainActor in
            let status = LocationManagerBox.shared.manager.authorizationStatus
            guard status != .notDetermined else { return }
            let waiting = authorizationContinuations
            authorizationContinuations.removeAll()
            for continuation in waiting { continuation.resume(returning: status) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}

/// Where you are, and how precisely the app is allowed to know it.
///
/// The one sensor a Simulator can genuinely drive:
/// `xcrun simctl location booted start --speed=15 --interval=1 lat,lon lat,lon`
public struct LiveLocationSource: SensorSource {
    public let id: SensorID = "core_location.position"

    public init() {}

    public func availability() async -> SensorAvailability {
        await MainActor.run {
            guard CLLocationManager.locationServicesEnabled() else {
                return .unavailable(reason: .hardwareAbsent)
            }
            return Self.map(LocationManagerBox.shared.status,
                            accuracy: LocationManagerBox.shared.accuracy)
        }
    }

    public func requestAccess() async -> SensorAvailability {
        let status = await LocationManagerBox.shared.requestWhenInUse()
        let accuracy = await MainActor.run { LocationManagerBox.shared.accuracy }
        return Self.map(status, accuracy: accuracy)
    }

    public func read() async -> SensorSample? {
        await MainActor.run { LocationManagerBox.shared.requestFix() }

        guard let location = await MainActor.run(resultType: CLLocation?.self, body: {
            LocationManagerBox.shared.lastLocation
        }) else { return nil }

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
            // Reduced accuracy is genuinely partial access — the same shape as a
            // limited photo library — so it reports as `.limited` rather than
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

    public func read() async -> SensorSample? {
        guard CLLocationManager.headingAvailable() else { return nil }
        return await MainActor.run {
            guard let heading = LocationManagerBox.shared.manager.heading else { return nil }
            return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
                SensorField("Magnetic heading", .number(heading.magneticHeading, unit: "°")),
                SensorField("True heading", .number(heading.trueHeading, unit: "°")),
                SensorField("Accuracy", .number(heading.headingAccuracy, unit: "°")),
            ])
        }
    }
}
#endif
