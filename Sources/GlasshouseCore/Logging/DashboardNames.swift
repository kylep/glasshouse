import Foundation

/// Shorter labels for the Dashboard, where a name shares its row with a
/// sparkline and a value.
///
/// The ledger's `displayName` is written to be unambiguous in a list of sixty
/// capabilities — "Clipboard contents (silent)" earns every word there. On a
/// Dashboard row it truncates to "Clipboard conte…", which is worse than any
/// abbreviation. These are only for that row; every other screen keeps the
/// full name.
public enum DashboardNames {
    /// Longest name a row can show before the sparkline starts losing width.
    /// Measured, not guessed: at `.subheadline` on the narrowest supported
    /// phone this is where truncation began.
    public static let budget = 16

    public static func short(for sensor: SensorID) -> String {
        if let override = overrides[sensor] { return override }
        return CapabilityLedger[sensor]?.displayName ?? sensor.rawValue
    }

    /// Only names that do not fit. A signal absent from here is one whose real
    /// name is already short enough, and adding it would be a second name to
    /// keep in step with the ledger for no gain.
    static let overrides: [SensorID: String] = [
        "core_motion.altimeter_relative": "Baro. altitude",
        "core_motion.altimeter_absolute": "Abs. altitude",
        "bluetooth.scan": "Bluetooth nearby",
        "health.activity": "Activity",
        "health.sleep_and_mind": "Sleep and mind",
        // The two clipboard capabilities differ only in whether iOS shows the
        // paste banner, which no short label can carry. Naming each for what it
        // actually plots keeps them apart on the row.
        "pasteboard.shape": "Clipboard items",
        "pasteboard.contents": "Clipboard text",
        // Named for what is actually plotted. The capability covers language,
        // region, and calendar; the chart is the UTC offset alone, and calling
        // that "Language" would be a puzzle rather than a label.
        "device.locale": "Time zone",
    ]
}
