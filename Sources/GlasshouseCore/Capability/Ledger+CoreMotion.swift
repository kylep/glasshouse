extension CapabilityLedger {
    /// Core Motion.
    ///
    /// Every capability here returns nothing in the Simulator — measured, with
    /// no exceptions — and there is no injection mechanism at any layer. That
    /// makes this the framework that forced the fake/replay architecture.
    ///
    /// Note that `NSMotionUsageDescription` is required for the *derived*
    /// sensors (pedometer, altimeter, activity, headphone motion), which crash
    /// without it. Raw `CMMotionManager` streams appear not to need it, but the
    /// key is declared anyway: it costs nothing and the framework overview asks
    /// for it.
    static let coreMotion: [Capability] = [
        Capability(
            id: "core_motion.accelerometer",
            displayName: "Accelerometer",
            framework: "CoreMotion",
            reveals: "Every movement of the phone in three axes, at up to 100 samples a second. Enough to infer walking, driving, or which pocket it is in — and, in published research, enough to recover what is typed on a nearby keyboard.",
            plistKeys: ["NSMotionUsageDescription"],
            simulator: .returnsNothing,
            sensitivity: .personal,
            gate: .neverAsks,
            source: "https://developer.apple.com/documentation/coremotion/cmmotionmanager + measured: isAccelerometerAvailable == false, iOS 26.2 simulator",
            verified: "2026-08-30",
            notes: "isAccelerometerAvailable is false in the Simulator and no simctl facility injects motion data. Replay-only until device day. Measured on an iPhone 14 Pro: this produced readings with no dialog and no grant, while the pedometer and altimeter sat at notDetermined. Motion & Fitness gates the DERIVED sensors — pedometer, altimeter, activity — which expose a CMAuthorizationStatus. Raw CMMotionManager streams have no authorization API at all. NSMotionUsageDescription is still declared: it costs nothing and Apple's framework overview asks for it."
        ),
        Capability(
            id: "core_motion.gyroscope",
            displayName: "Gyroscope",
            framework: "CoreMotion",
            reveals: "The phone's rotation rate around each axis. Combined with the accelerometer it reconstructs how the device is being held and moved.",
            plistKeys: ["NSMotionUsageDescription"],
            simulator: .returnsNothing,
            sensitivity: .personal,
            gate: .neverAsks,
            source: "https://developer.apple.com/documentation/coremotion/cmmotionmanager + measured: isGyroAvailable == false",
            verified: "2026-08-30",
            notes: "Measured on an iPhone 14 Pro: this produced readings with no dialog and no grant, while the pedometer and altimeter sat at notDetermined. Motion & Fitness gates the DERIVED sensors — pedometer, altimeter, activity — which expose a CMAuthorizationStatus. Raw CMMotionManager streams have no authorization API at all. NSMotionUsageDescription is still declared: it costs nothing and Apple's framework overview asks for it."
        ),
        Capability(
            id: "core_motion.magnetometer",
            displayName: "Magnetometer",
            framework: "CoreMotion",
            reveals: "The ambient magnetic field. Indoors this is distorted by building steel in ways that are stable enough to act as a location fingerprint.",
            plistKeys: ["NSMotionUsageDescription"],
            simulator: .returnsNothing,
            sensitivity: .personal,
            gate: .neverAsks,
            source: "https://developer.apple.com/documentation/coremotion/cmmotionmanager + measured: isMagnetometerAvailable == false",
            verified: "2026-08-30",
            notes: "Measured on an iPhone 14 Pro: this produced readings with no dialog and no grant, while the pedometer and altimeter sat at notDetermined. Motion & Fitness gates the DERIVED sensors — pedometer, altimeter, activity — which expose a CMAuthorizationStatus. Raw CMMotionManager streams have no authorization API at all. NSMotionUsageDescription is still declared: it costs nothing and Apple's framework overview asks for it."
        ),
        Capability(
            id: "core_motion.device_motion",
            displayName: "Device motion",
            framework: "CoreMotion",
            reveals: "A fused reading: attitude, gravity, user acceleration, rotation rate, and calibrated magnetic field. Cleaner than any single sensor and correspondingly more revealing.",
            plistKeys: ["NSMotionUsageDescription"],
            simulator: .returnsNothing,
            sensitivity: .personal,
            gate: .neverAsks,
            source: "https://developer.apple.com/documentation/coremotion/cmmotionmanager + measured: isDeviceMotionAvailable == false",
            verified: "2026-08-30",
            notes: "Measured on an iPhone 14 Pro: this produced readings with no dialog and no grant, while the pedometer and altimeter sat at notDetermined. Motion & Fitness gates the DERIVED sensors — pedometer, altimeter, activity — which expose a CMAuthorizationStatus. Raw CMMotionManager streams have no authorization API at all. NSMotionUsageDescription is still declared: it costs nothing and Apple's framework overview asks for it."
        ),
        Capability(
            id: "core_motion.pedometer",
            displayName: "Pedometer",
            framework: "CoreMotion",
            reveals: "Steps, distance, pace, cadence, and floors climbed — including history recorded before this app was ever installed.",
            plistKeys: ["NSMotionUsageDescription"],
            simulator: .returnsNothing,
            sensitivity: .personal,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/coremotion/cmpedometer + measured: all six availability checks false",
            verified: "2026-08-30",
            notes: "Apple's docs are explicit that a missing NSMotionUsageDescription crashes the app rather than failing gracefully. Queries historical data the OS recorded independently of this app."
        ),
        Capability(
            id: "core_motion.altimeter_relative",
            displayName: "Barometric altitude",
            framework: "CoreMotion",
            reveals: "Air pressure in kilopascals and relative altitude change, precise enough to detect climbing a single flight of stairs.",
            plistKeys: ["NSMotionUsageDescription"],
            simulator: .returnsNothing,
            sensitivity: .personal,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/coremotion/cmaltimeter + measured: isRelativeAltitudeAvailable() == false",
            verified: "2026-08-30"
        ),
        Capability(
            id: "core_motion.altimeter_absolute",
            displayName: "Absolute altitude",
            framework: "CoreMotion",
            reveals: "Height above sea level. Combined with a coordinate this identifies which floor of a building you are on.",
            plistKeys: ["NSMotionUsageDescription"],
            simulator: .returnsNothing,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/coremotion/cmaltimeter/isabsolutealtitudeavailable() + measured: false",
            verified: "2026-08-30",
            notes: "iOS 15+, and hardware-gated to iPhone 12 and later. Classified intimate rather than personal because floor-level position is effectively fine-grained location."
        ),
        Capability(
            id: "core_motion.activity",
            displayName: "Motion activity",
            framework: "CoreMotion",
            reveals: "What you are doing, classified by the OS: walking, running, cycling, driving, or stationary — with a confidence level, and queryable as history.",
            plistKeys: ["NSMotionUsageDescription"],
            simulator: .returnsNothing,
            sensitivity: .personal,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager + measured: isActivityAvailable() == false",
            verified: "2026-08-30"
        ),
        Capability(
            id: "core_motion.headphone_motion",
            displayName: "Headphone motion",
            framework: "CoreMotion",
            reveals: "The orientation of your head, streamed from AirPods. Where you are looking, and when you nod.",
            plistKeys: ["NSMotionUsageDescription"],
            simulator: .returnsNothing,
            sensitivity: .personal,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager + measured: isDeviceMotionAvailable == false",
            verified: "2026-08-30",
            notes: "iOS 14+. Requires physically connected motion-capable AirPods, so device verification needs the hardware too."
        ),
    ]
}
