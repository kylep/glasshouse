extension CapabilityLedger {
    /// HealthKit.
    ///
    /// Two findings here contradict widespread belief, both verified twice:
    /// HealthKit is signable by a **free** Personal Team, and
    /// `isHealthDataAvailable()` returns **true** in the iOS 26.2 Simulator.
    /// That combination makes it the deepest data source the project can
    /// develop against without hardware.
    ///
    /// One caveat kept deliberately visible: whether `requestAuthorization`
    /// actually presents its sheet in a Simulator is still unverified.
    static let health: [Capability] = [
        Capability(
            id: "health.vitals",
            displayName: "Vital signs",
            framework: "HealthKit",
            reveals: "Heart rate, heart rate variability, resting and walking heart rate, blood oxygen, respiratory rate, body temperature, and atrial fibrillation burden — much of it recorded continuously by a watch, going back years.",
            plistKeys: ["NSHealthShareUsageDescription"],
            entitlement: "com.apple.developer.healthkit",
            tier: .free,
            simulator: .worksWithCaveats,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/healthkit/data-types + measured: isHealthDataAvailable() == true, iOS 26.2 simulator",
            verified: "2026-08-30",
            notes: "Free-team signable — confirmed by both Apple's capability matrix and Xcode's own DVTPortalCachedPortalCapabilities.json. Nothing is seeded, so tests must write their own samples first. UNVERIFIED: whether the authorization sheet appears in a Simulator."
        ),
        Capability(
            id: "health.activity",
            displayName: "Activity and fitness",
            framework: "HealthKit",
            reveals: "Steps, distance, flights climbed, active and resting energy, exercise minutes, VO2 max, and workout history including GPS routes.",
            plistKeys: ["NSHealthShareUsageDescription"],
            entitlement: "com.apple.developer.healthkit",
            tier: .free,
            simulator: .worksWithCaveats,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/healthkit/data-types",
            verified: "2026-08-30",
            notes: "Workout routes carry HKWorkoutRouteTypeIdentifier — a full GPS track per workout, which is location history arriving through a health permission."
        ),
        Capability(
            id: "health.sleep_and_mind",
            displayName: "Sleep and state of mind",
            framework: "HealthKit",
            reveals: "When you sleep and how well, mindfulness sessions, and — since iOS 18 — logged mood and emotional state.",
            plistKeys: ["NSHealthShareUsageDescription"],
            entitlement: "com.apple.developer.healthkit",
            tier: .free,
            simulator: .worksWithCaveats,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/healthkit/hkstateofmind",
            verified: "2026-08-30",
            notes: "HKStateOfMind is iOS 18+."
        ),
        Capability(
            id: "health.reproductive",
            displayName: "Reproductive health",
            framework: "HealthKit",
            reveals: "Menstrual cycle, ovulation, pregnancy, and sexual activity — among the most sensitive categories on the device, and in some jurisdictions legally consequential.",
            plistKeys: ["NSHealthShareUsageDescription"],
            entitlement: "com.apple.developer.healthkit",
            tier: .free,
            simulator: .worksWithCaveats,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/healthkit/data-types",
            verified: "2026-08-30",
            notes: "Listed separately from other vitals deliberately. If any category should be excluded from Phase 2 export by default, it is this one — see docs/phase-2-boundary.md."
        ),
        Capability(
            id: "health.clinical_records",
            displayName: "Clinical records",
            framework: "HealthKit",
            reveals: "Medical records synced from healthcare providers: conditions, medications, immunisations, lab results, procedures.",
            plistKeys: ["NSHealthClinicalHealthRecordsShareUsageDescription", "NSHealthShareUsageDescription"],
            entitlement: "com.apple.developer.healthkit.access",
            tier: .paid,
            simulator: .returnsNothing,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit.access",
            verified: "2026-08-30",
            notes: "Requires the separate .healthkit.access entitlement array, and NSHealthRequiredReadAuthorizationTypeIdentifiers must list at least three types or authorization fails. Verifiable Health Records additionally needs an Apple request form."
        ),
    ]
}
