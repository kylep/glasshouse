import Testing
import Foundation
@testable import GlasshouseCore

/// Fixtures are **hand-authored**, not captured from a real phone.
///
/// Two reasons. First, a real export is personal data and this repository is
/// public. Second, and more importantly: Apple documents the report's contents
/// but never documents the export format, and research surfaced two competing
/// schemas. These fixtures encode both shapes as they were described, so the
/// decoder's behaviour against each is pinned — but **they are not evidence
/// that either shape is what iOS 26 actually writes.** That needs a real export.
enum Fixtures {
    /// The shape believed current: `type`/`category`, interval pairs joined by UUID.
    static let v4 = """
        {"accessor":{"identifier":"com.example.chat","identifierType":"bundleID"},"category":"microphone","identifier":"AAAA-1","kind":"intervalBegin","timeStamp":"2026-08-20T10:00:00.000-04:00","type":"access"}
        {"accessor":{"identifier":"com.example.chat","identifierType":"bundleID"},"category":"microphone","identifier":"AAAA-1","kind":"intervalEnd","timeStamp":"2026-08-20T10:00:30.000-04:00","type":"access"}
        {"accessor":{"identifier":"com.example.social","identifierType":"bundleID"},"category":"photos","identifier":"BBBB-2","kind":"intervalBegin","timeStamp":"2026-08-20T11:00:00.000-04:00","type":"access"}
        {"accessor":{"identifier":"com.example.social","identifierType":"bundleID"},"category":"photos","identifier":"BBBB-2","kind":"intervalEnd","timeStamp":"2026-08-20T11:00:05.000-04:00","type":"access"}
        {"accessor":{"identifier":"com.example.social","identifierType":"bundleID"},"category":"location","identifier":"CCCC-3","kind":"intervalBegin","timeStamp":"2026-08-20T12:00:00.000-04:00","type":"access"}
        {"timeStamp":"2026-08-20T12:05:00.000-04:00","initiatedType":"AppInitiated","context":"","domain":"analytics.example-tracker.com","type":"networkActivity","domainType":1,"firstTimeStamp":"2026-08-19T09:00:00.000-04:00","bundleID":"com.example.social","domainOwner":"","hits":42}
        {"timeStamp":"2026-08-20T12:06:00.000-04:00","initiatedType":"AppInitiated","context":"","domain":"api.example.com","type":"networkActivity","domainType":2,"firstTimeStamp":"2026-08-20T12:06:00.000-04:00","bundleID":"com.example.chat","domainOwner":"Example Inc","hits":3}
        """

    /// The older shape: `stream`/`tccService`, point events, lower-case `timestamp`.
    static let v3 = """
        {"stream":"com.apple.privacy.accounting.stream.tcc","accessor":{"identifier":"com.example.legacy","identifierType":"bundleID"},"tccService":"kTCCServiceAddressBook","identifier":"DDDD-4","kind":"event","timestamp":"2026-08-20T14:00:00.000-04:00","version":3}
        {"stream":"com.apple.privacy.accounting.stream.tcc","accessor":{"identifier":"com.example.legacy","identifierType":"bundleID"},"tccService":"kTCCServiceCamera","identifier":"EEEE-5","kind":"event","timestamp":"2026-08-20T14:05:00.000-04:00","version":3}
        """
}

@Suite("Privacy report decoding")
struct PrivacyReportDecoderTests {
    let decoder = PrivacyReportDecoder()

    @Test("Detects the current schema and pairs intervals")
    func decodesV4() {
        let result = decoder.decode(Fixtures.v4)

        #expect(result.schema == .v4)
        #expect(result.failures.isEmpty, "\(result.failures)")

        // Three accesses: two completed pairs plus one still open.
        #expect(result.accesses.count == 3)

        let microphone = result.accesses.first { $0.resource == .microphone }
        #expect(microphone?.bundleID == "com.example.chat")
        #expect(microphone?.duration == 30)
    }

    @Test("An interval still open at the window edge is kept, not discarded")
    func openIntervalsSurvive() {
        // Common and expected: the export is a snapshot, and an app may have
        // been mid-access. Dropping these would silently lose real events.
        let result = decoder.decode(Fixtures.v4)
        let location = result.accesses.first { $0.resource == .location }

        #expect(location != nil)
        #expect(location?.wasOngoing == true)
        #expect(location?.duration == nil)
    }

    @Test("An interval end with no beginning is kept as a point event")
    func orphanedEnd() {
        // The access started before the 7-day window opened. Real, and worth
        // keeping rather than treating as corrupt.
        let orphan = """
            {"accessor":{"identifier":"com.example.app","identifierType":"bundleID"},"category":"camera","identifier":"X-1","kind":"intervalEnd","timeStamp":"2026-08-20T10:00:00.000-04:00","type":"access"}
            """
        let result = decoder.decode(orphan)
        #expect(result.accesses.count == 1)
        #expect(result.failures.isEmpty)
    }

    @Test("Network records carry Apple's own tracker flag")
    func networkActivity() {
        let result = decoder.decode(Fixtures.v4)
        #expect(result.contacts.count == 2)

        let tracker = result.contacts.first { $0.domain.contains("tracker") }
        #expect(tracker?.flaggedAsTracker == true)   // domainType 1
        #expect(tracker?.hits == 42)
        #expect(tracker?.owner == nil)               // empty string becomes nil

        let ordinary = result.contacts.first { $0.domain == "api.example.com" }
        #expect(ordinary?.flaggedAsTracker == false) // domainType 2
        #expect(ordinary?.owner == "Example Inc")
    }

    @Test("The older schema decodes too, including its different date key")
    func decodesV3() {
        let result = decoder.decode(Fixtures.v3)

        #expect(result.schema == .v3)
        #expect(result.failures.isEmpty, "\(result.failures)")
        #expect(result.accesses.count == 2)

        let resources = Set(result.accesses.map(\.resource))
        #expect(resources == [.contacts, .camera])   // kTCCServiceAddressBook → contacts
    }

    @Test("An unrecognised shape fails loudly instead of decoding to nothing")
    func unknownSchemaIsReported() {
        // The failure mode that matters most. This data cannot be re-fetched —
        // the window is 7 days and turning the report off erases it — so a
        // silent empty result would be far worse than a visible error.
        let result = decoder.decode("""
            {"someFutureFormat":true,"payload":{"a":1}}
            """)

        #expect(result.schema == .unknown)
        #expect(result.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].reason.contains("unrecognised"))
    }

    @Test("One bad line does not lose the rest of the file")
    func partialFailure() {
        let mixed = """
            {"accessor":{"identifier":"com.example.a","identifierType":"bundleID"},"category":"camera","identifier":"1","kind":"intervalBegin","timeStamp":"2026-08-20T10:00:00.000-04:00","type":"access"}
            this is not json at all
            {"accessor":{"identifier":"com.example.a","identifierType":"bundleID"},"category":"camera","identifier":"1","kind":"intervalEnd","timeStamp":"2026-08-20T10:00:10.000-04:00","type":"access"}
            """
        let result = decoder.decode(mixed)

        #expect(result.accesses.count == 1)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].line == 2)
    }

    @Test("An unknown category is reported rather than silently dropped")
    func unknownCategory() {
        let result = decoder.decode("""
            {"accessor":{"identifier":"com.example.a","identifierType":"bundleID"},"category":"somethingNew","identifier":"1","kind":"intervalBegin","timeStamp":"2026-08-20T10:00:00.000-04:00","type":"access"}
            """)
        #expect(result.accesses.isEmpty)
        #expect(result.failures.first?.reason.contains("somethingNew") == true)
    }

    @Test("Blank lines and trailing newlines are not failures")
    func toleratesWhitespace() {
        let result = decoder.decode("\n\n" + Fixtures.v4 + "\n\n")
        #expect(result.failures.isEmpty)
        #expect(result.accesses.count == 3)
    }

    @Test("Empty input yields an empty result, not a crash")
    func emptyInput() {
        let result = decoder.decode("")
        #expect(result.isEmpty)
        #expect(result.failures.isEmpty)
        #expect(result.schema == .unknown)
    }

    @Test("Timestamps parse with and without fractional seconds")
    func dateParsing() {
        #expect(PrivacyReportDecoder.parseDate("2026-08-20T10:00:00.000-04:00") != nil)
        #expect(PrivacyReportDecoder.parseDate("2026-08-20T10:00:00-04:00") != nil)
        #expect(PrivacyReportDecoder.parseDate("2026-08-20T14:00:00Z") != nil)
        #expect(PrivacyReportDecoder.parseDate("not a date") == nil)
        #expect(PrivacyReportDecoder.parseDate(nil) == nil)
    }
}

@Suite("Privacy report history")
struct PrivacyReportHistoryTests {
    let decoder = PrivacyReportDecoder()

    @Test("Re-importing the same export does not duplicate anything")
    func mergingIsIdempotent() {
        // The user will re-import weekly, and windows overlap. Double-counting
        // would inflate claims about other people's apps.
        var history = PrivacyReportHistory()
        let report = decoder.decode(Fixtures.v4)

        history.merge(report)
        let afterFirst = history.accesses.count
        history.merge(report)

        #expect(history.accesses.count == afterFirst)
        #expect(history.contacts.count == 2)
    }

    @Test("History accumulates across schema versions")
    func mergesAcrossSchemas() {
        var history = PrivacyReportHistory()
        history.merge(decoder.decode(Fixtures.v4))
        history.merge(decoder.decode(Fixtures.v3))

        #expect(history.apps.contains("com.example.legacy"))
        #expect(history.apps.contains("com.example.social"))
    }

    @Test("Overlapping windows take the larger hit count rather than summing")
    func hitsDoNotAccumulate() {
        var history = PrivacyReportHistory()
        history.merge(decoder.decode(Fixtures.v4))

        let laterWindow = """
            {"timeStamp":"2026-08-27T12:05:00.000-04:00","initiatedType":"AppInitiated","context":"","domain":"analytics.example-tracker.com","type":"networkActivity","domainType":1,"firstTimeStamp":"2026-08-26T09:00:00.000-04:00","bundleID":"com.example.social","domainOwner":"","hits":10}
            """
        history.merge(decoder.decode(laterWindow))

        let tracker = history.contacts.first { $0.domain.contains("tracker") }
        #expect(tracker?.hits == 42, "should keep the larger count, not sum to 52")
        // The observed span widens across both imports.
        #expect(tracker?.lastSeen ?? 0 > tracker?.firstSeen ?? 0)
    }

    @Test("Answers which apps touched a resource")
    func appsByResource() {
        var history = PrivacyReportHistory()
        history.merge(decoder.decode(Fixtures.v4))

        let photoApps = history.apps(touching: .photos)
        #expect(photoApps.count == 1)
        #expect(photoApps[0].bundleID == "com.example.social")
    }

    @Test("Surfaces apps contacting domains iOS flagged as trackers")
    func trackerAttribution() {
        var history = PrivacyReportHistory()
        history.merge(decoder.decode(Fixtures.v4))

        #expect(history.trackers.count == 1)
        let offenders = history.appsContactingTrackers
        #expect(offenders.count == 1)
        #expect(offenders[0].bundleID == "com.example.social")
    }

    @Test("Total duration ignores intervals that never ended")
    func durationExcludesOpenIntervals() {
        // Under-reporting is the honest direction; inventing an end time is not.
        var history = PrivacyReportHistory()
        history.merge(decoder.decode(Fixtures.v4))

        #expect(history.totalDuration(bundleID: "com.example.chat", resource: .microphone) == 30)
        #expect(history.totalDuration(bundleID: "com.example.social", resource: .location) == 0)
    }

    @Test("Ranks each app by the most sensitive thing it touched")
    func deepestReach() {
        var history = PrivacyReportHistory()
        history.merge(decoder.decode(Fixtures.v4))

        let reach = Dictionary(uniqueKeysWithValues: history.deepestReachPerApp.map { ($0.bundleID, $0.resource) })
        #expect(reach["com.example.chat"] == .microphone)
        // social touched both photos (personal) and location (intimate).
        #expect(reach["com.example.social"] == .location)
    }

    @Test("An empty history reports itself as empty")
    func emptyHistory() {
        #expect(PrivacyReportHistory().isEmpty)
    }
}
