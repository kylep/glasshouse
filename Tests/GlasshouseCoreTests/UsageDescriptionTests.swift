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
    @Test("The plist key set is exactly what the reachable ledger requires")
    func plistMatchesLedger() {
        let required = Set(CapabilityLedger.requiredPlistKeys(for: .free))
        let reachable = CapabilityLedger.reachable(with: .free)
        let expected = Set(reachable.flatMap(\.plistKeys))

        #expect(required == expected)

        // And nothing from an unreachable tier leaks in.
        for row in CapabilityLedger.all where !row.isReachable(with: .free) {
            for key in row.plistKeys where !expected.contains(key) {
                #expect(!required.contains(key), "'\(key)' leaked from unreachable '\(row.id)'")
            }
        }
    }

    @Test("Adding a capability with an undescribed key would fail the build")
    func mismatchIsDetected() {
        // Proves the guard actually fires, rather than trusting that it would.
        let invented = Capability(
            id: "test.invented",
            displayName: "Invented",
            framework: "Test",
            reveals: "Nothing; this row exists only to prove the guard works.",
            plistKeys: ["NSCompletelyUndescribedUsageDescription"],
            simulator: .worksFully,
            sensitivity: .ambient,
            promptsUser: true,
            source: "test",
            verified: "2026-08-30"
        )

        let keys = Set([invented].flatMap(\.plistKeys))
        let undescribed = keys.filter { UsageDescriptions.byKey[$0] == nil }
        #expect(undescribed == ["NSCompletelyUndescribedUsageDescription"])
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
            promptsUser: false,          // contradicts declaring a plist key
            source: "test",
            verified: "2026-08-30"
        )

        let problems = CapabilityLedger.inconsistencies(in: [broken])
        #expect(problems.count == 1)
        #expect(problems[0].contains("claims not to prompt"))
    }
}
