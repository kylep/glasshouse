import Testing
@testable import GlasshouseCore

@Suite("Ledger dates")
struct LedgerDateTests {
    @Test("Parses a well-formed date")
    func parsing() throws {
        let date = try #require(LedgerDate(parsing: "2026-08-30"))
        #expect(date.year == 2026)
        #expect(date.month == 8)
        #expect(date.day == 30)
    }

    @Test("Rejects malformed input", arguments: [
        "2026-8-30", "2026/08/30", "26-08-30", "2026-13-01", "2026-02-30", "", "today",
    ])
    func rejectsMalformed(_ text: String) {
        #expect(LedgerDate(parsing: text) == nil)
    }

    @Test("Accepts a leap day and rejects it in a common year")
    func leapYears() {
        #expect(LedgerDate(parsing: "2024-02-29") != nil)
        #expect(LedgerDate(parsing: "2026-02-29") == nil)
        #expect(LedgerDate(parsing: "2000-02-29") != nil)  // divisible by 400
        #expect(LedgerDate(parsing: "1900-02-29") == nil)  // divisible by 100, not 400
    }

    @Test("Round-trips through its description")
    func descriptionRoundTrip() throws {
        for text in ["2026-08-30", "1999-01-01", "2026-12-09"] {
            let date = try #require(LedgerDate(parsing: text))
            #expect(date.description == text)
        }
    }

    @Test("Counts days across month and year boundaries")
    func dayArithmetic() throws {
        let start = try #require(LedgerDate(parsing: "2026-08-30"))
        #expect(start.days(to: try #require(LedgerDate(parsing: "2026-08-31"))) == 1)
        #expect(start.days(to: try #require(LedgerDate(parsing: "2026-09-30"))) == 31)
        #expect(start.days(to: try #require(LedgerDate(parsing: "2027-08-30"))) == 365)
        #expect(start.days(to: try #require(LedgerDate(parsing: "2026-08-29"))) == -1)
        // Across a leap day.
        let beforeLeap = try #require(LedgerDate(parsing: "2024-02-28"))
        #expect(beforeLeap.days(to: try #require(LedgerDate(parsing: "2024-03-01"))) == 2)
    }

    @Test("The epoch is where it should be")
    func epoch() throws {
        #expect(try #require(LedgerDate(parsing: "1970-01-01")).daysSinceEpoch == 0)
    }
}

@Suite("Capability ledger")
struct CapabilityLedgerTests {
    /// The most recent date any ledger row may claim to have been verified.
    ///
    /// A fixed date rather than "now", so the suite cannot start failing on a
    /// calendar boundary with no code change — but that means **bump this when
    /// adding a row verified later than it**. The failure is the point: it
    /// forces a deliberate look at whether the new claim really was checked.
    static let latestVerification: LedgerDate = "2026-09-01"

    @Test("The ledger is structurally consistent")
    func noInconsistencies() {
        let problems = CapabilityLedger.inconsistencies()
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    @Test("Identifiers are unique")
    func uniqueIdentifiers() {
        let ids = CapabilityLedger.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every row is reachable by lookup")
    func lookupFindsEveryRow() {
        for row in CapabilityLedger.all {
            #expect(CapabilityLedger[row.id]?.id == row.id)
        }
    }

    @Test("An unknown identifier looks up to nothing")
    func unknownLookup() {
        #expect(CapabilityLedger["nope.not_a_sensor"] == nil)
    }

    @Test("The ledger is not trivially small")
    func hasSubstance() {
        // A guard against the ledger being silently emptied by a bad refactor.
        #expect(CapabilityLedger.all.count >= 40)
    }
}

@Suite("Ledger slices")
struct LedgerSliceTests {
    @Test("Free tier excludes paid capabilities and includes free ones")
    func reachabilityFiltering() {
        let free = CapabilityLedger.reachable(with: .free).map(\.id)
        #expect(free.contains("core_location.position"))
        #expect(free.contains("health.vitals"))       // free-team signable
        #expect(!free.contains("wifi.ssid"))          // needs $99
        #expect(!free.contains("restricted.sensorkit"))
    }

    @Test("A paid tier reaches more than a free one, but never the unobtainable")
    func paidReachesMore() {
        let free = CapabilityLedger.reachable(with: .free).count
        let paid = CapabilityLedger.reachable(with: .paid).count
        #expect(paid > free)

        let paidIDs = Set(CapabilityLedger.reachable(with: .paid).map(\.id))
        #expect(!paidIDs.contains("restricted.sensorkit"))
    }

    @Test("The device checklist is derived from simulator behaviour, not declared")
    func deviceChecklistIsDerived() {
        let needsDevice = Set(CapabilityLedger.requiringDeviceVerification.map(\.id))

        // Core Motion is measured as returning nothing, so all of it lands here.
        #expect(needsDevice.contains("core_motion.accelerometer"))
        #expect(needsDevice.contains("bluetooth.scan"))
        #expect(needsDevice.contains("device.battery"))

        // Things the simulator genuinely does should not.
        #expect(!needsDevice.contains("core_location.position"))
        #expect(!needsDevice.contains("photos.asset_location"))
        #expect(!needsDevice.contains("contacts.all"))
    }

    @Test("The never-asked set is exactly what iOS lets through ungated")
    func neverAskedCapabilities() {
        let silent = Set(CapabilityLedger.neverAsked.map(\.id))

        // The quietly alarming ones — the app's most instructive category.
        #expect(silent.contains("pasteboard.shape"))
        #expect(silent.contains("device.battery"))
        #expect(silent.contains("device.identifier_for_vendor"))
        #expect(silent.contains("network.path"))
        #expect(silent.contains("vision.text"))

        // Anything behind a dialog must not be in it.
        #expect(!silent.contains("core_location.position"))
        #expect(!silent.contains("contacts.all"))
        #expect(!silent.contains("health.vitals"))

        // Nor the notifying clipboard read. It raises no dialog, which is why
        // the old boolean swept it in here — but iOS does tell you afterwards,
        // so calling it ungated was the misleading claim this split fixes.
        #expect(!silent.contains("pasteboard.contents"))
        #expect(CapabilityLedger["pasteboard.contents"]?.gate == .tellsYouAfter)

        // Nor the ones no app may read. Same absence of a dialog, opposite reason.
        #expect(!silent.contains("restricted.ambient_light"))
        #expect(CapabilityLedger["restricted.ambient_light"]?.gate == .noAccessAtAll)
    }

    @Test("A meaningful share of the ledger is never asked about")
    func neverAskedSetIsSubstantial() {
        // Pins the claim the app makes on its front screen.
        let silent = CapabilityLedger.neverAsked.count
        #expect(silent >= 15, "only \(silent) capabilities are read without iOS asking")
        #expect(silent < CapabilityLedger.all.count / 2,
                "most capabilities should still be behind a permission")
    }

    @Test("Required plist keys cover the free tier and exclude paid-only ones")
    func plistKeyGeneration() {
        let keys = CapabilityLedger.requiredPlistKeys(for: .free)

        #expect(keys.contains("NSMotionUsageDescription"))
        #expect(keys.contains("NSLocationWhenInUseUsageDescription"))
        #expect(keys.contains("NSContactsUsageDescription"))
        #expect(keys.contains("NSHealthShareUsageDescription"))

        // iOS 17 split keys, not the deprecated single one.
        #expect(keys.contains("NSCalendarsFullAccessUsageDescription"))
        #expect(!keys.contains("NSCalendarsUsageDescription"))

        // Paid-tier capabilities must not leak their keys into a free build.
        #expect(!keys.contains("NFCReaderUsageDescription"))
        #expect(!keys.contains("NSFocusStatusUsageDescription"))

        #expect(keys == keys.sorted(), "keys must be sorted for stable plist generation")
        #expect(Set(keys).count == keys.count, "keys must be deduplicated")
    }

    @Test("Frameworks group in a stable, sorted order")
    func frameworkGrouping() {
        let grouped = CapabilityLedger.byFramework
        #expect(grouped.map(\.framework) == grouped.map(\.framework).sorted())
        #expect(grouped.reduce(0) { $0 + $1.capabilities.count } == CapabilityLedger.all.count)
    }
}

@Suite("Ledger provenance")
struct LedgerProvenanceTests {
    @Test("Nothing was verified in the future")
    func noFutureVerification() {
        let latest = CapabilityLedgerTests.latestVerification
        for row in CapabilityLedger.all {
            #expect(row.verified <= latest, "'\(row.id)' claims verification later than the suite allows — bump latestVerification if that is genuine")
        }
    }

    @Test("No row is stale as of when it was authored")
    func freshWhenWritten() {
        #expect(CapabilityLedger.stale(asOf: CapabilityLedgerTests.latestVerification).isEmpty)
    }

    @Test("Staleness is detected once the limit passes")
    func stalenessTriggers() {
        // 91 days after authoring, everything written that day should be flagged.
        let later: LedgerDate = "2026-12-31"
        #expect(CapabilityLedgerTests.latestVerification.days(to: later) > 90)
        #expect(CapabilityLedger.stale(asOf: later).count == CapabilityLedger.all.count)
    }

    @Test("Blocked capabilities all explain themselves")
    func blockedRowsAreDocumented() {
        for row in CapabilityLedger.all where row.status == .blocked {
            let notes = row.notes ?? ""
            #expect(!notes.isEmpty, "'\(row.id)' is blocked with no explanation")
        }
    }

    @Test("The impossible things are recorded as blocked, not omitted")
    func impossibilitiesAreDocumented() {
        // Documenting what cannot be read is part of what the app is for, so
        // these must be present rather than quietly left out of the ledger.
        let blocked = Set(CapabilityLedger.all.filter { $0.status == .blocked }.map(\.id))
        #expect(blocked.contains("restricted.ambient_light"))
        #expect(blocked.contains("restricted.sensorkit"))
        #expect(blocked.contains("restricted.other_app_permissions"))
    }
}

@Suite("Shared permissions")
struct SharedPermissionTests {
    @Test("Heading and location are one grant, not two")
    func headingSharesLocation() {
        // The bug this models: iOS has no separate compass permission, so the
        // app offered to ask for something iOS would never ask about.
        let shared = CapabilityLedger.sharingPermission(with: "core_location.heading").map(\.id)
        #expect(shared.contains("core_location.position"))
    }

    @Test("Calendar and contacts really are separate grants")
    func genuinelySeparateGrants() {
        // The control case. These declare different usage-description keys and
        // do each show their own dialog, which is why they behaved differently
        // from the compass.
        let calendarShares = CapabilityLedger.sharingPermission(with: "calendar.events").map(\.id)
        #expect(!calendarShares.contains("contacts.all"))

        let contactShares = CapabilityLedger.sharingPermission(with: "contacts.all").map(\.id)
        #expect(contactShares.isEmpty)
    }

    @Test("One Motion & Fitness grant covers every Core Motion reader")
    func motionIsOneGrant() {
        let group = CapabilityLedger.permissionGroup(for: "core_motion.accelerometer")
        #expect(group.contains("core_motion.gyroscope"))
        #expect(group.contains("core_motion.pedometer"))
        #expect(group.contains("core_motion.altimeter_relative"))
        #expect(group.count >= 9, "expected all Core Motion readers, got \(group.count)")
    }

    @Test("The photo library and photo locations are one grant")
    func photosShareOneGrant() {
        let shared = CapabilityLedger.sharingPermission(with: "photos.library").map(\.id)
        #expect(shared.contains("photos.asset_location"))
    }

    @Test("Sharing is symmetric, and never includes the capability itself")
    func sharingIsSymmetric() {
        for row in CapabilityLedger.all where !row.plistKeys.isEmpty {
            for sibling in CapabilityLedger.sharingPermission(with: row.id) {
                #expect(sibling.id != row.id, "'\(row.id)' lists itself as a sibling")
                let back = CapabilityLedger.sharingPermission(with: sibling.id).map(\.id)
                #expect(back.contains(row.id), "'\(row.id)' and '\(sibling.id)' disagree about sharing")
            }
        }
    }

    @Test("A capability with no usage key shares nothing")
    func ungatedSharesNothing() {
        // Battery needs no permission, so there is no grant to share.
        #expect(CapabilityLedger.sharingPermission(with: "device.battery").isEmpty)
        #expect(CapabilityLedger.permissionGroup(for: "device.battery") == ["device.battery"])
    }
}
