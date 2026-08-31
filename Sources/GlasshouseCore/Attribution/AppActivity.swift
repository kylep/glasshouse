/// What another app did, according to iOS.
///
/// These are the normalised results of importing an App Privacy Report. They
/// are the only legitimate way a sandboxed app can learn what *other* apps
/// accessed — there is no API for it at any entitlement tier, so the user
/// exports the data from Settings and shares it in.

/// A resource another app touched.
///
/// The names are Apple's, normalised across the two export schema versions
/// seen in the wild.
public enum AccessedResource: String, Sendable, Hashable, Codable, CaseIterable {
    case camera
    case microphone
    case photos
    case contacts
    case location
    case mediaLibrary = "media_library"
    case screenRecording = "screen_recording"
    case calendar
    case reminders

    /// Plain-language name for display.
    public var displayName: String {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .photos: "Photos"
        case .contacts: "Contacts"
        case .location: "Location"
        case .mediaLibrary: "Media library"
        case .screenRecording: "Screen recording"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        }
    }

    /// How alarming it is that an app touched this.
    public var sensitivity: Sensitivity {
        switch self {
        case .camera, .microphone, .screenRecording, .location: .intimate
        case .photos, .contacts, .calendar, .reminders: .personal
        case .mediaLibrary: .identifying
        }
    }
}

/// One app's use of one resource, over a period.
public struct ResourceAccess: Sendable, Hashable, Codable {
    /// The accessing app's bundle identifier. Reports carry no display name.
    public let bundleID: String
    public let resource: AccessedResource

    /// Seconds since 1970.
    public let began: Double

    /// Nil when the interval was still open at the edge of the report window,
    /// which is common and is not an error.
    public let ended: Double?

    public init(bundleID: String, resource: AccessedResource, began: Double, ended: Double?) {
        self.bundleID = bundleID
        self.resource = resource
        self.began = began
        self.ended = ended
    }

    /// How long the access lasted, if it finished.
    public var duration: Double? {
        ended.map { $0 - began }
    }

    /// Whether the access was still open when the report was exported.
    public var wasOngoing: Bool { ended == nil }
}

/// One app's contact with one internet domain.
public struct NetworkContact: Sendable, Hashable, Codable {
    public let bundleID: String
    public let domain: String

    /// Number of times over the report window.
    public let hits: Int

    /// Whether iOS itself flagged the domain as one that tracks people across
    /// apps and websites. Apple's own judgement, not an inference.
    public let flaggedAsTracker: Bool

    /// Whether the app initiated the connection, as opposed to content it loaded.
    public let appInitiated: Bool

    /// Who owns the domain, where the report says. Usually empty, which is why
    /// an offline enrichment dataset is worth bundling.
    public let owner: String?

    public let firstSeen: Double
    public let lastSeen: Double

    public init(
        bundleID: String,
        domain: String,
        hits: Int,
        flaggedAsTracker: Bool,
        appInitiated: Bool,
        owner: String?,
        firstSeen: Double,
        lastSeen: Double
    ) {
        self.bundleID = bundleID
        self.domain = domain
        self.hits = hits
        self.flaggedAsTracker = flaggedAsTracker
        self.appInitiated = appInitiated
        self.owner = owner
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}

/// Everything one import produced.
public struct PrivacyReportImport: Sendable, Hashable, Codable {
    public let accesses: [ResourceAccess]
    public let contacts: [NetworkContact]

    /// Lines that could not be decoded, with the reason. Surfaced rather than
    /// swallowed: a schema change must be visible, not silently drop records.
    public let failures: [DecodingFailure]

    /// Which schema the file appeared to use.
    public let schema: PrivacyReportSchema

    public init(
        accesses: [ResourceAccess],
        contacts: [NetworkContact],
        failures: [DecodingFailure],
        schema: PrivacyReportSchema
    ) {
        self.accesses = accesses
        self.contacts = contacts
        self.failures = failures
        self.schema = schema
    }

    public var isEmpty: Bool { accesses.isEmpty && contacts.isEmpty }

    /// Distinct apps mentioned anywhere in the import.
    public var apps: [String] {
        Set(accesses.map(\.bundleID) + contacts.map(\.bundleID)).sorted()
    }
}

/// A line that could not be decoded.
public struct DecodingFailure: Sendable, Hashable, Codable {
    /// 1-based line number in the source file.
    public let line: Int
    public let reason: String

    public init(line: Int, reason: String) {
        self.line = line
        self.reason = reason
    }
}
