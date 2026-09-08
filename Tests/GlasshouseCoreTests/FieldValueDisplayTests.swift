import Foundation
import Testing
@testable import GlasshouseCore

@Suite("Field value display")
struct FieldValueDisplayTests {
    @Test("Large numbers lose their meaningless decimals")
    func largeNumbers() {
        // The bug this was written for: free storage reached the screen as
        // "34.3138427734375 GB".
        #expect(FieldValue.number(34.3138427734375, unit: "GB").displayText == "34.3 GB")
        #expect(FieldValue.number(1234.5678, unit: "MB").displayText == "1235 MB")
    }

    @Test("Small numbers keep the precision that carries the signal")
    func smallNumbers() {
        #expect(FieldValue.number(0.4213, unit: "g").displayText == "0.421 g")
        #expect(FieldValue.number(9.8066, unit: "m/s²").displayText == "9.81 m/s²")
    }

    @Test("Trailing zeros are dropped")
    func trailingZeros() {
        #expect(FieldValue.number(50, unit: "%").displayText == "50 %")
        #expect(FieldValue.number(1.50).displayText == "1.5")
    }

    @Test("Negative values round like positive ones")
    func negatives() {
        #expect(FieldValue.number(-4.0, unit: "h").displayText == "-4 h")
        #expect(FieldValue.number(-0.1234).displayText == "-0.123")
    }

    @Test("Times are dates, not raw seconds")
    func times() {
        // plainDescription renders "t=0", which is a debug form and was
        // reaching the UI.
        #expect(!FieldValue.time(0).displayText.hasPrefix("t="))
    }

    @Test("Non-numeric values are unchanged")
    func passthrough() {
        #expect(FieldValue.text("Speaker").displayText == "Speaker")
        #expect(FieldValue.boolean(false).displayText == "no")
        #expect(FieldValue.integer(1200, unit: "items").displayText.hasSuffix("items"))
    }

    @Test("Coordinates keep full precision")
    func coordinates() {
        let value = FieldValue.coordinate(latitude: 37.334886, longitude: -122.008988)
        #expect(value.displayText.contains("37.334886"))
    }
}
