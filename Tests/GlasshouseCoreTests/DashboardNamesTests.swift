import Testing
@testable import GlasshouseCore

@Suite("Dashboard names")
struct DashboardNamesTests {
    @Test("Every charted signal fits the Dashboard row")
    func chartedNamesFit() {
        for featured in ChartableSignals.featured {
            let name = DashboardNames.short(for: featured.sensor)
            #expect(
                name.count <= DashboardNames.budget,
                "\(featured.sensor.rawValue) shows \"\(name)\" (\(name.count) chars), which truncates"
            )
        }
    }

    @Test("Overrides name real capabilities")
    func overridesAreReal() {
        for sensor in DashboardNames.overrides.keys {
            #expect(CapabilityLedger[sensor] != nil, "\(sensor.rawValue) is not in the ledger")
        }
    }

    @Test("No override restates a name that already fits")
    func noPointlessOverrides() {
        // A second name for a signal is a second thing to keep in step with the
        // ledger. One that buys no width is pure cost, so it should be deleted
        // rather than left to rot.
        for (sensor, short) in DashboardNames.overrides {
            let full = CapabilityLedger[sensor]?.displayName ?? ""
            #expect(full.count > DashboardNames.budget || short != full,
                    "\(sensor.rawValue) is already short enough")
        }
    }

    @Test("Signals without an override fall back to the ledger")
    func fallsBackToLedger() {
        #expect(DashboardNames.short(for: "device.battery") == "Battery")
    }
}

@Suite("Chart windows")
struct ChartWindowTests {
    @Test("Windows are ordered and bounded")
    func ordering() {
        let ordered = ChartWindow.allCases
        for (earlier, later) in zip(ordered, ordered.dropFirst()) {
            #expect(earlier.seconds < later.seconds)
        }
        #expect(ChartWindow.month.seconds == 2_592_000)
    }

    @Test("Start is measured back from the given moment")
    func startFrom() {
        #expect(ChartWindow.day.start(from: 1_000_000) == 1_000_000 - 86_400)
    }

    @Test("The Dashboard omits the hour")
    func dashboardChoices() {
        #expect(!ChartWindow.dashboardChoices.contains(.hour))
        #expect(ChartWindow.dashboardChoices.first == .day)
    }
}
