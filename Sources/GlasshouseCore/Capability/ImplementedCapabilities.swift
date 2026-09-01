/// Which capabilities have a working live adapter.
///
/// Declared here rather than derived, because the adapters live in
/// `GlasshouseSensors`, which is iOS-only and therefore invisible to both the
/// macOS test suite and the documentation generator.
///
/// A hand-maintained list would go stale immediately, so it does not get to:
/// `ProjectInvariantTests.implementedListMatchesAdapters` parses the adapter
/// sources and fails the build if this disagrees with them.
public enum ImplementedCapabilities {
    public static let ids: Set<String> = [
        // No permission required.
        "device.accessibility",
        "device.battery",
        "device.identifier_for_vendor",
        "device.locale",
        "device.screen_capture",
        "device.thermal",
        "av.audio_route",
        "av.camera_hardware",
        "device.low_power_mode",
        "device.storage",
        "device.uptime",
        "network.path",
        "pasteboard.contents",
        "pasteboard.shape",
        "telephony.radio_technology",

        // Behind a permission prompt.
        "bluetooth.scan",
        "calendar.events",
        "contacts.all",
        "health.activity",
        "health.vitals",
        "core_location.accuracy_authorization",
        "core_location.heading",
        "core_location.position",
        "core_motion.accelerometer",
        "core_motion.activity",
        "core_motion.altimeter_absolute",
        "core_motion.altimeter_relative",
        "core_motion.device_motion",
        "core_motion.headphone_motion",
        "core_motion.magnetometer",
        "core_motion.gyroscope",
        "core_motion.pedometer",
        "photos.asset_location",
        "photos.library",
        "reminders.all",
    ]

    /// Ledger rows with no adapter yet. Honest rather than hidden — the app
    /// shows these as "not built yet" instead of omitting them.
    public static var unimplemented: [Capability] {
        CapabilityLedger.all
            .filter { !ids.contains($0.id.rawValue) }
            .sorted { $0.id < $1.id }
    }
}
