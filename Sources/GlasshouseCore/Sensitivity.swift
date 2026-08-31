/// How much a sensor reveals about the person holding the phone.
///
/// This is the input to storage and retention decisions, not a label applied
/// after the fact. A sensor's sensitivity determines its data protection class
/// and whether it is collected by default — see `docs/data-classification.md`.
public enum Sensitivity: String, Codable, Sendable, CaseIterable, Comparable {
    /// Reveals something about the device's environment but little about the
    /// person: thermal state, locale, uptime, disk capacity.
    case ambient

    /// Can fingerprint or correlate this device across contexts even though it
    /// carries no content: identifierForVendor, BLE neighbourhood, network path.
    case identifying

    /// Content authored by or about the person: contacts, calendar, photos,
    /// pasteboard contents, coarse location.
    case personal

    /// Data that is dangerous in aggregate and effectively impossible to
    /// un-share: health records, precise location history, biometrics, audio.
    case intimate

    /// Whether a stream at this level may be collected without the person
    /// explicitly switching it on first.
    public var isEnabledByDefault: Bool {
        switch self {
        case .ambient, .identifying: true
        case .personal, .intimate: false
        }
    }

    private var severity: Int {
        switch self {
        case .ambient: 0
        case .identifying: 1
        case .personal: 2
        case .intimate: 3
        }
    }

    public static func < (lhs: Sensitivity, rhs: Sensitivity) -> Bool {
        lhs.severity < rhs.severity
    }
}
