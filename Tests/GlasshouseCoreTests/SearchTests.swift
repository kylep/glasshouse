import Testing
@testable import GlasshouseCore

@Suite("Capability search")
struct CapabilitySearchTests {
    private func ids(_ query: String) -> [String] {
        CapabilityLedger.search(query).map(\.id.rawValue)
    }

    @Test("An empty query matches everything")
    func emptyQuery() {
        #expect(CapabilityLedger.search("").count == CapabilityLedger.all.count)
        #expect(CapabilityLedger.search("   ").count == CapabilityLedger.all.count)
    }

    @Test("Matches on a sensor's name")
    func byName() {
        #expect(ids("bluetooth").contains("bluetooth.scan"))
        #expect(ids("barometric").contains("core_motion.altimeter_relative"))
    }

    @Test("Matches on identifier, with separators treated as spaces")
    func byIdentifier() {
        // Typing the identifier the way it is written should work, and so
        // should typing it the way it is spoken.
        #expect(ids("core_motion.gyroscope").contains("core_motion.gyroscope"))
        #expect(ids("core motion gyroscope").contains("core_motion.gyroscope"))
    }

    @Test("Matches on framework")
    func byFramework() {
        let healthKit = ids("healthkit")
        #expect(healthKit.contains("health.vitals"))
        #expect(!healthKit.contains("device.battery"))
    }

    @Test("Finds sensors by what they reveal, not what they are called")
    func byMeaning() {
        // The whole reason this searches `reveals`. None of these queries
        // appears in the name of the capability it should find.
        #expect(ids("nearby").contains("bluetooth.scan"))
        #expect(ids("where each photo was taken").contains("photos.asset_location"))
        #expect(ids("stairs").contains("core_motion.altimeter_relative"))
        #expect(ids("fingerprint").contains("device.uptime"))
    }

    @Test("Finds the ungated set by its consent label")
    func byConsentState() {
        // "never asks" is the phrase a person would search for, and it appears
        // in no other field.
        let never = ids("never asks")
        #expect(never.contains("device.battery"))
        #expect(never.contains("pasteboard.shape"))
        #expect(!never.contains("contacts.all"))
    }

    @Test("Finds the most sensitive capabilities by class")
    func bySensitivity() {
        let intimate = ids("intimate")
        #expect(intimate.contains("health.vitals"))
        #expect(!intimate.contains("device.thermal"))
    }

    @Test("Adding a word narrows, never widens")
    func narrowing() {
        // The rule people expect from a search box even if they could not
        // state it. Every extra word must be an additional constraint.
        let broad = CapabilityLedger.search("motion").count
        let narrow = CapabilityLedger.search("motion heart").count
        #expect(narrow <= broad)

        for query in ["photo", "photo location", "photo location taken"] {
            #expect(CapabilityLedger.search(query).count <= CapabilityLedger.search("photo").count)
        }
    }

    @Test("Case and punctuation are ignored")
    func caseInsensitive() {
        #expect(ids("BLUETOOTH").contains("bluetooth.scan"))
        #expect(ids("Bluetooth, devices!").contains("bluetooth.scan"))
    }

    @Test("A query matching nothing returns nothing rather than everything")
    func noMatches() {
        // The failure mode worth guarding: a filter that falls back to "show
        // everything" tells the user their search worked when it did not.
        #expect(CapabilityLedger.search("zzzznotasensor").isEmpty)
    }

    @Test("Searching within a subset stays within it")
    func searchesWithinASubset() {
        let ungated = CapabilityLedger.neverAsked
        let found = CapabilityLedger.search("battery", within: ungated)
        #expect(found.allSatisfy { $0.gate == .neverAsks })
    }
}
