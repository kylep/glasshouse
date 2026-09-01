extension CapabilityLedger {
    /// Core Location.
    ///
    /// The one genuinely drivable sensor in the Simulator: `simctl location`
    /// sets fixed points, runs four named scenarios, and interpolates waypoint
    /// tracks with speed and update-interval control. Heading is the exception,
    /// because it needs the magnetometer.
    ///
    /// Use the modern async surface — `CLLocationUpdate.liveUpdates()` (iOS 17),
    /// `CLServiceSession` (iOS 18), `CLMonitor` (iOS 17) — rather than the
    /// delegate API. Heading still requires `CLLocationManager`.
    static let coreLocation: [Capability] = [
        Capability(
            id: "core_location.position",
            displayName: "Location",
            framework: "CoreLocation",
            reveals: "Where you are, to within a few metres, with altitude, speed, and course. Sampled over time it is the single most identifying stream on the device — four coarse points are enough to uniquely identify most people.",
            plistKeys: ["NSLocationWhenInUseUsageDescription"],
            simulator: .worksFully,
            sensitivity: .personal,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/corelocation/cllocationupdate + measured: locationServicesEnabled() == true",
            verified: "2026-08-30",
            notes: "Drive deterministically with `xcrun simctl location <dev> start --speed=N --interval=N lat,lon lat,lon`. Scenarios: City Run, City Bicycle Ride, Freeway Drive, Apple."
        ),
        Capability(
            id: "core_location.heading",
            displayName: "Compass heading",
            framework: "CoreLocation",
            reveals: "Which way the phone is pointing, magnetic and true.",
            plistKeys: ["NSLocationWhenInUseUsageDescription"],
            simulator: .returnsNothing,
            sensitivity: .personal,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/corelocation/cllocationmanager + measured: headingAvailable() == false",
            verified: "2026-08-30",
            notes: "Needs the magnetometer, which the Simulator lacks. Heading is also the one part of Core Location with no modern async replacement — still CLLocationManager plus delegate."
        ),
        Capability(
            id: "core_location.accuracy_authorization",
            displayName: "Precise vs approximate",
            framework: "CoreLocation",
            reveals: "Whether you granted precise location or the reduced, roughly-neighbourhood-sized version — and lets an app ask you to upgrade, one purpose at a time.",
            plistKeys: [
                "NSLocationWhenInUseUsageDescription",
                "NSLocationTemporaryUsageDescriptionDictionary",
            ],
            simulator: .worksWithCaveats,
            sensitivity: .ambient,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/corelocation/cllocationmanager/requesttemporaryfullaccuracyauthorization(withpurposekey:)",
            verified: "2026-08-30",
            notes: "iOS 14+. `simctl privacy location` sets the when-in-use bit only and has no accuracy dimension, so the reduced/precise distinction cannot be scripted. Worth surfacing prominently: most people do not know the toggle exists."
        ),
        Capability(
            id: "core_location.significant_change",
            displayName: "Significant location change",
            framework: "CoreLocation",
            reveals: "Your movements between places, delivered even when the app is not running — and it will relaunch the app in the background to deliver them.",
            plistKeys: ["NSLocationAlwaysAndWhenInUseUsageDescription", "NSLocationWhenInUseUsageDescription"],
            simulator: .worksWithCaveats,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/corelocation/cllocationmanager + measured: significantLocationChangeMonitoringAvailable() == true",
            verified: "2026-08-30",
            notes: "requestAlwaysAuthorization() silently does nothing unless BOTH plist keys are present — an easy and invisible mistake. Background delivery makes this a location history, which is why it is classified intimate."
        ),
        Capability(
            id: "core_location.region_monitoring",
            displayName: "Geofencing",
            framework: "CoreLocation",
            reveals: "Notifies an app when you enter or leave a place it cares about — home, work, a specific shop — without the app running.",
            plistKeys: ["NSLocationAlwaysAndWhenInUseUsageDescription", "NSLocationWhenInUseUsageDescription"],
            simulator: .worksWithCaveats,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/corelocation/clmonitor + measured: isMonitoringAvailable(for: CLCircularRegion.self) == true",
            verified: "2026-08-30",
            notes: "UNVERIFIED whether enter/exit events actually fire when location is driven by `simctl location start`. The API reports available; delivery is unproven. Confirm before trusting a passing test."
        ),
        Capability(
            id: "core_location.visits",
            displayName: "Visits",
            framework: "CoreLocation",
            reveals: "Where you stopped and for how long, inferred by the OS. Not a track of movement but a diary of places — home, work, the clinic you spent an hour at.",
            plistKeys: ["NSLocationAlwaysAndWhenInUseUsageDescription", "NSLocationWhenInUseUsageDescription"],
            simulator: .returnsNothing,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/corelocation/clvisit",
            verified: "2026-08-30",
            notes: "Visit detection needs real dwell patterns and device motion, so it is very unlikely to fire in a Simulator. There is no availability API to check, which makes its silence indistinguishable from 'no visits yet' — treat as device-only."
        ),
    ]
}
