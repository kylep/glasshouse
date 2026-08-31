extension CapabilityLedger {
    /// Everything readable without ever asking.
    ///
    /// This is the most instructive group in the app. Not because any single
    /// reading is alarming, but because nothing here triggers a prompt, appears
    /// in Settings, or leaves any trace the user can inspect. Several of these
    /// are also durable fingerprinting signals when combined.
    static let deviceState: [Capability] = [
        Capability(
            id: "device.battery",
            displayName: "Battery",
            framework: "UIKit",
            reveals: "Charge level and whether you are plugged in. Historically a tracking signal precisely because it is granular, changes predictably, and needs no permission — browsers removed the equivalent web API for that reason.",
            simulator: .returnsNothing,
            sensitivity: .identifying,
            promptsUser: false,
            source: "https://developer.apple.com/documentation/uikit/uidevice/batterylevel + measured: level -1.0, monitoring cannot be enabled",
            verified: "2026-08-30",
            notes: "Measured trap: `simctl status_bar override --batteryLevel` is status-bar chrome only and never reaches UIDevice. isBatteryMonitoringEnabled refuses to become true in a Simulator, so this is replay-only until device day."
        ),
        Capability(
            id: "device.thermal",
            displayName: "Thermal state",
            framework: "Foundation",
            reveals: "How hot the phone is, which tracks what it has been doing — gaming, navigating, charging in the sun.",
            simulator: .worksWithCaveats,
            sensitivity: .ambient,
            promptsUser: false,
            source: "https://developer.apple.com/documentation/foundation/processinfo/thermalstate",
            verified: "2026-08-30",
            notes: "Readable but pinned to .nominal in a Simulator; it never varies, so treat it as a constant rather than a signal here."
        ),
        Capability(
            id: "device.low_power_mode",
            displayName: "Low Power Mode",
            framework: "Foundation",
            reveals: "Whether you have switched on Low Power Mode — a small signal about your battery anxiety and how far you are from a charger.",
            simulator: .worksWithCaveats,
            sensitivity: .ambient,
            promptsUser: false,
            source: "https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled",
            verified: "2026-08-30",
            notes: "Always false in a Simulator, though it can be toggled in the simulated Settings app."
        ),
        Capability(
            id: "device.storage",
            displayName: "Storage",
            framework: "Foundation",
            reveals: "How much space you have free. Stable and finely grained enough to help fingerprint a device across apps.",
            simulator: .worksWithCaveats,
            sensitivity: .identifying,
            promptsUser: false,
            source: "https://developer.apple.com/documentation/foundation/urlresourcevalues",
            verified: "2026-08-30",
            notes: "Reports the host Mac's volume in a Simulator, so values are unrealistic. Also one of Apple's five required-reason API categories — needs a declared reason if this ever ships to the App Store."
        ),
        Capability(
            id: "device.uptime",
            displayName: "Uptime",
            framework: "Foundation",
            reveals: "How long since you last restarted. Combined with other signals, boot time is a well-known cross-app device fingerprint.",
            simulator: .worksWithCaveats,
            sensitivity: .identifying,
            promptsUser: false,
            source: "https://developer.apple.com/documentation/foundation/processinfo/systemuptime",
            verified: "2026-08-30",
            notes: "A required-reason API category (system boot time). Reflects the simulator process rather than a device."
        ),
        Capability(
            id: "device.identifier_for_vendor",
            displayName: "Vendor identifier",
            framework: "UIKit",
            reveals: "A stable ID that links everything this developer's apps see you do — no permission, no prompt, and it survives until you delete every one of their apps.",
            simulator: .worksFully,
            sensitivity: .identifying,
            promptsUser: false,
            source: "https://developer.apple.com/documentation/uikit/uidevice/identifierforvendor",
            verified: "2026-08-30",
            notes: "Nil before first unlock after reboot, and Apple warns it can change when installing test builds via Xcode."
        ),
        Capability(
            id: "device.locale",
            displayName: "Language and region",
            framework: "Foundation",
            reveals: "Your language, region, time zone, calendar, and measurement system. Individually mundane; together a meaningful narrowing of who you are.",
            simulator: .worksFully,
            sensitivity: .identifying,
            promptsUser: false,
            source: "https://developer.apple.com/documentation/foundation/locale",
            verified: "2026-08-30",
            notes: "Time zone is the strongest element — it is coarse location that no permission gates."
        ),
        Capability(
            id: "device.accessibility",
            displayName: "Accessibility settings",
            framework: "UIKit",
            reveals: "Whether you use VoiceOver, larger text, reduced motion, or increased contrast. These can imply disability, and no permission gates them.",
            simulator: .worksFully,
            sensitivity: .personal,
            promptsUser: false,
            source: "https://developer.apple.com/documentation/uikit/uiaccessibility",
            verified: "2026-08-30",
            notes: "Classified personal rather than identifying because these settings can reveal a health characteristic. Scriptable via `simctl ui increase_contrast` and `content_size`."
        ),
        Capability(
            id: "pasteboard.shape",
            displayName: "Clipboard contents (silent)",
            framework: "UIKit",
            reveals: "Whether your clipboard holds a URL, a number, or text — and it can be checked without the 'pasted from' banner ever appearing. An app can know you copied a link, silently.",
            simulator: .worksFully,
            sensitivity: .personal,
            promptsUser: false,
            source: "https://developer.apple.com/documentation/uikit/uipasteboard",
            verified: "2026-08-30",
            notes: "Apple documents the no-notification surface explicitly: numberOfItems, types, hasStrings, hasURLs, hasImages, hasColors, and the whole detectPatterns(for:) family. Reading .string or .url raises the banner; these do not. This distinction is one of the best things the app can demonstrate — show both, and label which one notified the user."
        ),
        Capability(
            id: "pasteboard.contents",
            displayName: "Clipboard contents (notified)",
            framework: "UIKit",
            reveals: "The actual text or URL on your clipboard. Reading this does show you a banner — which is exactly the contrast worth seeing next to the silent version.",
            simulator: .worksFully,
            sensitivity: .personal,
            promptsUser: false,
            source: "https://developer.apple.com/documentation/uikit/uipasteboard",
            verified: "2026-08-30",
            notes: "promptsUser is false because no permission dialog is involved — the iOS 16+ banner is a notification after the fact, not a gate. That asymmetry is the teaching point. Drive fixtures with `simctl pbcopy`."
        ),
        Capability(
            id: "device.screen_capture",
            displayName: "Screen recording",
            framework: "UIKit",
            reveals: "Whether your screen is being recorded or mirrored right now, and when you take a screenshot of this app.",
            simulator: .worksFully,
            sensitivity: .ambient,
            promptsUser: false,
            source: "https://developer.apple.com/documentation/uikit/uiscreen/iscaptured",
            verified: "2026-08-30",
            notes: "UIScreen.isCaptured (iOS 11+) and the screenshot notification. There is still no public API to *prevent* a screenshot, and isCaptured updates around capture start, so content can leak before a handler runs."
        ),
    ]
}
