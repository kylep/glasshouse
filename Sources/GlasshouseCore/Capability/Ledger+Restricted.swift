extension CapabilityLedger {
    /// Sensors the hardware has that no third-party app may read, and data the
    /// sandbox will not expose at any price.
    ///
    /// These rows are `.blocked`, and that is a finished state rather than a
    /// failure. Showing someone a sensor in their phone that no app is allowed
    /// to read is as instructive as showing them a reading — arguably more so,
    /// because it is the part of the sandbox that actually works.
    static let restricted: [Capability] = [
        Capability(
            id: "restricted.ambient_light",
            displayName: "Ambient light sensor",
            framework: "SensorKit",
            reveals: "How bright the room is. Fine-grained enough to infer when you wake, when you sleep, and whether you are indoors — which is exactly why it is locked away.",
            entitlement: "com.apple.developer.sensorkit.reader.allow",
            tier: .unobtainable,
            simulator: .unavailable,
            sensitivity: .intimate,
            gate: .noAccessAtAll,
            source: "https://developer.apple.com/documentation/sensorkit/srsensor",
            verified: "2026-08-30",
            status: .blocked,
            notes: "Your phone has this sensor and there is NO public API for it — the only surface anywhere in the SDK is SRSensorAmbientLightSensor, behind SensorKit's research gate. UIScreen.brightness is display backlight, not ambient light. One of the clearest cases where the sandbox holds."
        ),
        Capability(
            id: "restricted.sensorkit",
            displayName: "Raw research sensors",
            framework: "SensorKit",
            reveals: "Twenty raw streams Apple reserves for medical research: PPG, ECG, wrist temperature, keyboard typing dynamics, phone and message usage patterns, ambient pressure.",
            plistKeys: ["NSSensorKitUsageDescription"],
            entitlement: "com.apple.developer.sensorkit.reader.allow",
            tier: .unobtainable,
            simulator: .unavailable,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.sensorkit.reader.allow",
            verified: "2026-08-30",
            status: .blocked,
            notes: "Granted only for Apple-approved research studies with ethics-board sign-off, submitted via researchandcare.org. The system terminates an app whose signature lacks the entitlement. Documented and closed. SRSensorReader is deprecated in iOS 27 in favour of a generic SRReader, with no sign of the gate loosening."
        ),
        Capability(
            id: "restricted.other_app_permissions",
            displayName: "What other apps can access",
            framework: "None",
            reveals: "Which permissions your other apps hold. No app can read this — not with any entitlement, at any price, on any iOS version.",
            tier: .unobtainable,
            simulator: .unavailable,
            sensitivity: .ambient,
            gate: .noAccessAtAll,
            source: "Apple DTS, developer forums thread 818261 (March 2026)",
            verified: "2026-08-30",
            status: .blocked,
            notes: "Apple DTS answered this exact question directly: the APIs do not exist. There is not even a unified API for an app's OWN permission state — each subsystem has its own. Enumerating installed apps is equally closed: LSApplicationWorkspace needs private entitlements no third-party profile can carry, and canOpenURL is presence-only, capped, and deprecated in iOS 27. TRAP: LSApplicationWorkspace.allApplications returns real data in a Simulator and an empty array on device, so simulator-only work can 'prove' a dead API works."
        ),
        Capability(
            id: "restricted.screen_time",
            displayName: "App usage history",
            framework: "FamilyControls",
            reveals: "How long you spend in each app, how often you pick up your phone, and which websites you visit.",
            entitlement: "com.apple.developer.family-controls",
            tier: .paidPlusApproval,
            simulator: .unavailable,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/deviceactivity/deviceactivityreport",
            verified: "2026-08-30",
            status: .blocked,
            notes: "Not available to a free Personal Team at all — Apple DTS confirmed this explicitly. Even with the entitlement, app identities are opaque tokens, and the DeviceActivityReport extension runs in a read-only sandbox that Apple designed so data cannot leave it. iOS 26.4 added FamilyActivityData returning real bundle IDs, but it needs a further entitlement, is EU-only for customers, and only one app per device may hold it."
        ),
        Capability(
            id: "restricted.focus_status",
            displayName: "Focus mode",
            framework: "Intents",
            reveals: "Whether you have notifications silenced — and nothing more. Not which Focus is on, just whether you are muted relative to this app.",
            plistKeys: ["NSFocusStatusUsageDescription"],
            entitlement: "com.apple.developer.usernotifications.communication",
            tier: .paid,
            simulator: .unavailable,
            sensitivity: .personal,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/intents/infocusstatuscenter",
            verified: "2026-08-30",
            notes: "Requires the $99 program via the Communication Notifications capability. Returns a single Bool that is relative to the calling app — there is no API to learn which Focus is active. Not reachable on the current free tier."
        ),
        Capability(
            id: "restricted.journal_suggestions",
            displayName: "Journaling suggestions",
            framework: "JournalingSuggestions",
            reveals: "The OS's own summary of your day — places visited, photos taken, workouts, music played, people contacted — assembled by iOS and offered to apps.",
            entitlement: "com.apple.developer.journal.allow",
            tier: .paid,
            simulator: .unavailable,
            sensitivity: .intimate,
            gate: .asksOnce,
            source: "https://developer.apple.com/documentation/journalingsuggestions",
            verified: "2026-08-30",
            status: .blocked,
            notes: "Blocked twice over: the entitlement needs the paid program, and the framework is absent from the Simulator SDK entirely — it will not even link. Notable as the one place iOS itself does the cross-sensor aggregation this app is built to demonstrate."
        ),
        Capability(
            id: "attribution.app_privacy_report",
            displayName: "What your other apps actually did",
            framework: "Import",
            reveals: "Which apps accessed your camera, microphone, photos, contacts, or location — and every network domain they contacted — with timestamps. Exported by you from Settings, because no app can read it directly.",
            simulator: .worksFully,
            sensitivity: .intimate,
            gate: .neverAsks,
            source: "https://developer.apple.com/documentation/network/inspecting-app-activity-data",
            verified: "2026-08-30",
            notes: "The only legitimate route to cross-app attribution, and it needs no entitlement. The user exports NDJSON from Settings and shares it in. Constraints: a 7-day rolling window, switching the report off wipes it, and records carry bare bundle IDs. UNVERIFIED: research returned two conflicting schemas and Apple documents the export format nowhere — settle it against a real export before writing the decoder."
        ),
    ]
}
