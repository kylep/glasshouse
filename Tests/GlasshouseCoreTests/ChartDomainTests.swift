import Testing
@testable import GlasshouseCore

@Suite("Chart Y domain")
struct ChartDomainTests {
    @Test("A flat series still gets a low-to-high band")
    func flatSeries() {
        // The bug: a constant 60% volume drew 60 at the top of the chart and 61
        // at the bottom, because the domain had no width.
        let domain = ChartDomain.y(for: [60, 60, 60])
        #expect(domain.lowerBound < 60)
        #expect(domain.upperBound > 60)
    }

    @Test("A constant zero does not collapse")
    func constantZero() {
        let domain = ChartDomain.y(for: [0, 0])
        #expect(domain.lowerBound < domain.upperBound)
    }

    @Test("Varying values keep a margin around them")
    func varyingSeries() {
        let domain = ChartDomain.y(for: [10, 20])
        #expect(domain.lowerBound < 10)
        #expect(domain.upperBound > 20)
    }

    @Test("Negative flat values are handled")
    func negativeFlat() {
        let domain = ChartDomain.y(for: [-4, -4])
        #expect(domain.lowerBound < -4)
        #expect(domain.upperBound > -4)
    }

    @Test("Counts never get a negative axis")
    func nonNegativeStaysNonNegative() {
        // An empty clipboard drew an axis running down to -0.4 items.
        #expect(ChartDomain.y(for: [0, 0]).lowerBound == 0)
        #expect(ChartDomain.y(for: [0, 1, 2]).lowerBound == 0)
    }

    @Test("Genuinely negative signals keep their room")
    func negativesKeepHeadroom() {
        // A UTC offset of -4 hours is real and must not be clamped away.
        #expect(ChartDomain.y(for: [-4, -4]).lowerBound < -4)
        #expect(ChartDomain.y(for: [-2, 3]).lowerBound < -2)
    }

    @Test("No values yields a usable range rather than crashing")
    func empty() {
        #expect(ChartDomain.y(for: []).lowerBound < ChartDomain.y(for: []).upperBound)
    }
}
