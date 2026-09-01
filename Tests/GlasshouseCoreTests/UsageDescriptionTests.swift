import Testing
@testable import GlasshouseCore

/// These tests are the link that makes the ledger load-bearing rather than
/// decorative. `scripts/bootstrap.sh` generates Info.plist from the ledger, so a
/// capability with no usage description would produce an empty system dialog —
/// or, for several frameworks, an outright crash.
@Suite("Usage descriptions")
struct UsageDescriptionTests {
    @Test("Every plist key the free tier needs has a description")
    func noMissingDescriptions() {
        let missing = UsageDescriptions.missing(for: .free)
        #expect(missing.isEmpty, "no usage description for: \(missing.joined(separator: ", "))")
    }

    @Test("Every plist key any capability could need has a description")
    func completeAcrossAllTiers() {
        // Covers paid and unobtainable rows too, so that raising the signing
        // tier later cannot silently ship an empty dialog.
        let missing = UsageDescriptions.missing(for: .unobtainable)
        #expect(missing.isEmpty, "no usage description for: \(missing.joined(separator: ", "))")
    }

    @Test("No description exists for a key nothing requires")
    func noOrphans() {
        let orphaned = UsageDescriptions.orphaned()
        #expect(orphaned.isEmpty, "described but unused: \(orphaned.joined(separator: ", "))")
    }

    @Test("Descriptions say where the data goes")
    func statesTheGuarantee() {
        // Every string that grants access to data promises it stays local. The
        // one exception is write-only calendar access, which reads nothing.
        let exempt = ["NSCalendarsWriteOnlyAccessUsageDescription"]

        for (key, text) in UsageDescriptions.byKey where !exempt.contains(key) {
            #expect(
                text.contains(UsageDescriptions.onDeviceGuarantee),
                "'\(key)' does not state the on-device guarantee"
            )
        }
    }

    @Test("Descriptions give a reason rather than naming the app")
    func explainsWhyNotWho() {
        for (key, text) in UsageDescriptions.byKey {
            #expect(text.count > 30, "'\(key)' is too short to be a real explanation")
            #expect(text.hasSuffix("."), "'\(key)' should be a complete sentence")

            // "Glasshouse needs access to X" is a non-explanation, and it is the
            // shape App Review rejects. Say what it is for instead.
            #expect(
                !text.lowercased().contains("needs access"),
                "'\(key)' asserts a need instead of giving a reason"
            )
        }
    }
}

@Suite("Generated build inputs")
struct GeneratedBuildInputTests {
    @Test("The generated plist contains these exact keys for a free build")
    func plistMatchesLedger() {
        // Pinned literally rather than recomputed from the ledger. Deriving the
        // expectation the same way the implementation does would assert only
        // that a function equals itself; this fails if a capability's keys
        // change, which is the thing worth catching.
        #expect(Set(CapabilityLedger.requiredPlistKeys(for: .free)) == [
            "NSBluetoothAlwaysUsageDescription",
            "NSCalendarsFullAccessUsageDescription",
            "NSCalendarsWriteOnlyAccessUsageDescription",
            "NSCameraUsageDescription",
            "NSContactsUsageDescription",
            "NSHealthShareUsageDescription",
            "NSLocalNetworkUsageDescription",
            "NSLocationAlwaysAndWhenInUseUsageDescription",
            "NSLocationTemporaryUsageDescriptionDictionary",
            "NSLocationWhenInUseUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSMotionUsageDescription",
            "NSNearbyInteractionUsageDescription",
            "NSPhotoLibraryUsageDescription",
            "NSRemindersFullAccessUsageDescription",
            "NSSpeechRecognitionUsageDescription",
        ])
    }

    @Test("Keys belonging only to paid capabilities never reach a free build")
    func paidKeysDoNotLeak() {
        let free = Set(CapabilityLedger.requiredPlistKeys(for: .free))

        // These appear in the ledger, on rows above the free tier. If tier
        // filtering broke, they would silently start shipping.
        #expect(!free.contains("NFCReaderUsageDescription"))
        #expect(!free.contains("NSFocusStatusUsageDescription"))
        #expect(!free.contains("NSSensorKitUsageDescription"))
        #expect(!free.contains("NSHealthClinicalHealthRecordsShareUsageDescription"))

        // ...and they really are present at a higher tier, so the assertions
        // above are testing filtering rather than absence.
        let everything = Set(CapabilityLedger.requiredPlistKeys(for: .unobtainable))
        #expect(everything.isSuperset(of: [
            "NFCReaderUsageDescription", "NSFocusStatusUsageDescription",
            "NSSensorKitUsageDescription",
        ]))
    }

    @Test("A capability with an undescribed key is caught by the real guard")
    func mismatchIsDetected() {
        // Calls UsageDescriptions.missing itself, so deleting that function
        // fails this test. The previous version reimplemented the check inline
        // and would have passed with the guard removed entirely.
        let invented = Capability(
            id: "test.invented",
            displayName: "Invented",
            framework: "Test",
            reveals: "Nothing; this row exists only to prove the guard works.",
            plistKeys: ["NSCompletelyUndescribedUsageDescription"],
            simulator: .worksFully,
            sensitivity: .ambient,
            gate: .asksOnce,
            source: "test",
            verified: "2026-08-30"
        )

        #expect(UsageDescriptions.missing(in: [invented]) == ["NSCompletelyUndescribedUsageDescription"])
        // And a row whose keys ARE described comes back clean.
        #expect(UsageDescriptions.missing(in: CapabilityLedger.reachable(with: .free)).isEmpty)
    }

    @Test("The ledger's own consistency check catches an authoring mistake")
    func inconsistencyCheckFires() {
        let broken = Capability(
            id: "test.broken",
            displayName: "Broken",
            framework: "Test",
            reveals: "A row with a purpose string but no prompt.",
            plistKeys: ["NSMotionUsageDescription"],
            simulator: .worksFully,
            sensitivity: .ambient,
            gate: .neverAsks,            // contradicts declaring a plist key
            source: "test",
            verified: "2026-08-30"
        )

        let problems = CapabilityLedger.inconsistencies(in: [broken])
        #expect(problems.count == 1)
        #expect(problems[0].contains("declares an Info.plist key"))
    }
}
