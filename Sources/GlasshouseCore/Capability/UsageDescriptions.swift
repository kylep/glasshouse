/// The text iOS shows in a permission dialog, per Info.plist key.
///
/// These are separate from `Capability.reveals` because the mapping is
/// many-to-one: nine Core Motion capabilities share `NSMotionUsageDescription`,
/// and the system shows one sentence for all of them.
///
/// Two rules for writing these, both load-bearing for an app whose subject is
/// honesty about data collection:
///
/// 1. **Say what the app does with it, not what the app is.** "To show you
///    what this sensor reveals" is a reason; "Glasshouse needs this" is not.
/// 2. **Say where the data goes.** Every string here ends with the same
///    promise, because in this phase it is unconditionally true.
public enum UsageDescriptions {
    /// The promise appended to every string. If this ever stops being true,
    /// the test asserting it will fail — which is the point.
    public static let onDeviceGuarantee = "This never leaves your device."

    public static let byKey: [String: String] = [
        "NSMotionUsageDescription":
            "To show you what your phone's motion sensors record about how you move. \(onDeviceGuarantee)",

        "NSLocationWhenInUseUsageDescription":
            "To show you the precision of the location your phone can report. \(onDeviceGuarantee)",

        "NSLocationAlwaysAndWhenInUseUsageDescription":
            "To show you that location can be recorded in the background, even when no app is open. \(onDeviceGuarantee)",

        "NSLocationTemporaryUsageDescriptionDictionary":
            "To demonstrate the difference between precise and approximate location. \(onDeviceGuarantee)",

        "NSPhotoLibraryUsageDescription":
            "To show you the hidden data in your photos — where and when each one was taken. \(onDeviceGuarantee)",

        "NSCameraUsageDescription":
            "To show you what the camera hardware reports about itself and its surroundings. \(onDeviceGuarantee)",

        "NSMicrophoneUsageDescription":
            "To show you the sound level your microphone can measure at any moment. \(onDeviceGuarantee)",

        "NSContactsUsageDescription":
            "To show you how much of other people's information your address book holds. \(onDeviceGuarantee)",

        "NSCalendarsFullAccessUsageDescription":
            "To show you what your calendar reveals about where you have been and who you were with. \(onDeviceGuarantee)",

        "NSCalendarsWriteOnlyAccessUsageDescription":
            "To demonstrate a narrower permission that can add events without reading any of them.",

        "NSRemindersFullAccessUsageDescription":
            "To show you what your reminders reveal, including the places they are tied to. \(onDeviceGuarantee)",

        "NSHealthShareUsageDescription":
            "To show you the depth of the health record your devices have been building. \(onDeviceGuarantee)",

        "NSHealthClinicalHealthRecordsShareUsageDescription":
            "To show you which medical records are readable by an app you install. \(onDeviceGuarantee)",

        "NSBluetoothAlwaysUsageDescription":
            "To show you which Bluetooth devices are around you right now. \(onDeviceGuarantee)",

        "NSLocalNetworkUsageDescription":
            "To show you which devices share your network. \(onDeviceGuarantee)",

        "NSSpeechRecognitionUsageDescription":
            "To show you what speech recognition can transcribe. \(onDeviceGuarantee)",

        "NSNearbyInteractionUsageDescription":
            "To show you how precisely your phone can measure distance to nearby devices. \(onDeviceGuarantee)",

        "NSFocusStatusUsageDescription":
            "To show you that apps can learn whether your notifications are silenced. \(onDeviceGuarantee)",

        "NFCReaderUsageDescription":
            "To show you what an NFC tag held near your phone contains. \(onDeviceGuarantee)",

        "NSSensorKitUsageDescription":
            "To show you which raw sensors exist but are reserved for approved research. \(onDeviceGuarantee)",
    ]

    /// Keys required by the ledger that have no description written for them.
    /// A non-empty result is a build-blocking authoring gap: iOS shows an empty
    /// dialog, or crashes outright, when a key is missing its string.
    public static func missing(for tier: SigningTier) -> [String] {
        CapabilityLedger.requiredPlistKeys(for: tier).filter { byKey[$0] == nil }.sorted()
    }

    /// Descriptions written for keys no capability actually requires. Harmless
    /// at runtime, but it means the ledger and this table have drifted.
    public static func orphaned() -> [String] {
        let required = Set(CapabilityLedger.requiredPlistKeys(for: .unobtainable))
        return byKey.keys.filter { !required.contains($0) }.sorted()
    }
}
