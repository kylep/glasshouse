import GlasshouseCore

/// Live adapters over Apple's sensor frameworks.
///
/// Everything in this target is iOS-only and deliberately thin. It cannot be
/// unit tested on macOS, so it must contain no logic worth testing: parse,
/// transform, and decide in `GlasshouseCore`, and let this target do nothing
/// but hand raw framework output across the protocol boundary.
public enum GlasshouseSensors {
    /// Whether this build can install live adapters at all.
    public static var canInstallLiveAdapters: Bool {
        RuntimeEnvironment.current.supportsLiveSensors
    }

    /// Every sensor with a real implementation, in a registry.
    ///
    /// Capabilities with no adapter fall back to `UnimplementedSource`, which
    /// reports "not built yet" rather than disappearing. That is deliberate: an
    /// app about honest disclosure should not quietly hide its own gaps.
    ///
    /// Note this returns live adapters **even in the Simulator**. They report
    /// their own unavailability accurately there, and exercising the real
    /// availability paths is far more useful than substituting fakes that would
    /// only confirm what the ledger already says.
    public static func liveRegistry() -> SensorRegistry {
        #if os(iOS)
        SensorRegistry([
            // No permission required — the quietly alarming set.
            LiveBatterySource(),
            LiveSystemStateSource(),
            LiveLocaleSource(),
            LiveVendorIdentifierSource(),
            LiveAccessibilitySource(),
            LiveScreenCaptureSource(),
            LivePasteboardShapeSource(),
            LivePasteboardContentSource(),
            LiveNetworkPathSource(),

            // Behind a permission dialog.
            LiveLocationSource(),
            LiveHeadingSource(),
            LivePhotoLibrarySource(),
            LivePhotoLocationSource(),
            LiveContactsSource(),
            LiveCalendarSource(),
            LiveRemindersSource(),

            // Device-only; report unavailable in a Simulator, which is the
            // behaviour worth demonstrating rather than hiding.
            LiveAccelerometerSource(),
            LiveGyroscopeSource(),
            LiveAltimeterSource(),
            LivePedometerSource(),
        ])
        #else
        SensorRegistry()
        #endif
    }
}
