import Testing
@testable import VoiceCore

@Suite struct CleanupBenchStatsTests {
    @Test func percentileUsesNearestRank() {
        let values: [Double] = [10, 1, 9, 2, 8, 3, 7, 4, 6, 5]
        #expect(LatencyStats.percentile(values, 90) == 9)
        #expect(LatencyStats.percentile(values, 50) == 5)
        #expect(LatencyStats.percentile(values, 100) == 10)
        #expect(LatencyStats.percentile([4], 90) == 4)
    }

    @Test func percentileOfNothingIsZero() {
        #expect(LatencyStats.percentile([], 90) == 0)
    }

    @Test func percentileClampsOutOfRange() {
        #expect(LatencyStats.percentile([1, 2, 3], 0) == 1)
        #expect(LatencyStats.percentile([1, 2, 3], 150) == 3)
        #expect(LatencyStats.percentile([1, 2, 3], -5) == 1)
    }
}
