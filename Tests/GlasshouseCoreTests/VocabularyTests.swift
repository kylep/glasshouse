import Testing
import Foundation
@testable import GlasshouseCore

@Suite("Sensor identifiers")
struct SensorIDTests {
    @Test("A dotted identifier reports its framework group")
    func groupIsEverythingBeforeTheFirstDot() {
        #expect(SensorID("core_motion.accelerometer").group == "core_motion")
        #expect(SensorID("photos.asset_location").group == "photos")
    }

    @Test("An identifier with no dot is its own group")
    func ungroupedIdentifier() {
        #expect(SensorID("battery").group == "battery")
    }

    @Test("Identifiers survive a Codable round trip unchanged")
    func codableRoundTrip() throws {
        let original = SensorID("core_location.heading")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SensorID.self, from: data)
        #expect(decoded == original)
    }

    @Test("Identifiers sort so generated docs have a stable order")
    func sortingIsStable() {
        let ids: [SensorID] = ["photos.exif", "battery.level", "core_motion.gyroscope"]
        #expect(ids.sorted().map(\.rawValue) == [
            "battery.level", "core_motion.gyroscope", "photos.exif",
        ])
    }
}

@Suite("Sensitivity classification")
struct SensitivityTests {
    @Test("Levels order from ambient up to intimate")
    func ordering() {
        #expect(Sensitivity.ambient < .identifying)
        #expect(Sensitivity.identifying < .personal)
        #expect(Sensitivity.personal < .intimate)
    }

    @Test("Only low-sensitivity streams may collect without being switched on")
    func defaultCollectionIsConservative() {
        #expect(Sensitivity.ambient.isEnabledByDefault)
        #expect(Sensitivity.identifying.isEnabledByDefault)
        #expect(!Sensitivity.personal.isEnabledByDefault)
        #expect(!Sensitivity.intimate.isEnabledByDefault)
    }

    @Test("Every level declares a default-collection stance")
    func everyLevelIsClassified() {
        // Guards against a new case being added without revisiting the policy.
        #expect(Sensitivity.allCases.count == 4)
    }
}

@Suite("Simulator behaviour")
struct SimulatorBehaviorTests {
    @Test("Sensors that yield nothing in a simulator need device verification")
    func devicVerificationIsDerivedNotDeclared() {
        #expect(!SimulatorBehavior.worksFully.requiresDevice)
        #expect(!SimulatorBehavior.worksWithCaveats.requiresDevice)
        #expect(SimulatorBehavior.returnsNothing.requiresDevice)
        #expect(SimulatorBehavior.unavailable.requiresDevice)
    }

    @Test("Silence is expected exactly where the sensor cannot report")
    func silenceIsExpectedOnlyWhereJustified() {
        // This is the property that stops "0 samples, no error" from being
        // mistaken for a working sensor with nothing to say.
        #expect(!SimulatorBehavior.worksFully.silenceIsExpected)
        #expect(SimulatorBehavior.returnsNothing.silenceIsExpected)
    }

    @Test("Raw values are snake_case so the ledger YAML reads naturally")
    func rawValueSpelling() {
        #expect(SimulatorBehavior.worksFully.rawValue == "works_fully")
        #expect(SimulatorBehavior.returnsNothing.rawValue == "returns_nothing")
        #expect(SimulatorBehavior.unavailable.rawValue == "unavailable")
    }
}

@Suite("Signing tiers")
struct SigningTierTests {
    @Test("Cheaper tiers are reachable from more expensive ones")
    func reachability() {
        #expect(SigningTier.free.isReachable(with: .free))
        #expect(SigningTier.free.isReachable(with: .paid))
        #expect(!SigningTier.paid.isReachable(with: .free))
        #expect(!SigningTier.unobtainable.isReachable(with: .paidPlusApproval))
    }

    @Test("Nothing is reachable beyond unobtainable, including from itself upward")
    func unobtainableIsTheCeiling() {
        // SensorKit lives here: a paid account plus an approved research study.
        #expect(!SigningTier.unobtainable.isReachable(with: .paid))
    }
}

@Suite("Runtime environment")
struct RuntimeEnvironmentTests {
    @Test("The unit suite runs on the host, not a device")
    func testsRunOnHost() {
        #expect(RuntimeEnvironment.current == .host)
    }

    @Test("Only a physical device supports live sensors or enforces entitlements")
    func onlyDeviceIsReal() {
        #expect(RuntimeEnvironment.device.supportsLiveSensors)
        #expect(!RuntimeEnvironment.simulator.supportsLiveSensors)
        #expect(!RuntimeEnvironment.host.supportsLiveSensors)

        // The whole reason the capability ledger exists.
        #expect(RuntimeEnvironment.device.enforcesEntitlements)
        #expect(!RuntimeEnvironment.simulator.enforcesEntitlements)
    }
}
