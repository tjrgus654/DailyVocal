import XCTest
@testable import VocalLogic

final class SustainStatsTests: XCTestCase {

    func testEmptyTimesReturnZero() {
        XCTAssertEqual(VocalLogic.SustainStats.longestRun(times: []), 0)
    }

    func testContinuousRunIsMeasuredToEnd() {
        // 10 s of frames at ~43 fps with no gaps.
        let times = stride(from: 0.0, through: 10.0, by: 1.0 / 43).map { $0 }
        XCTAssertEqual(VocalLogic.SustainStats.longestRun(times: times), 10.0, accuracy: 0.03)
    }

    func testShortDetectorDropsAreBridged() {
        // A single dropped frame (~23 ms gaps) must not split the run.
        var times: [Double] = []
        for i in 0..<430 where i % 50 != 7 {
            times.append(Double(i) / 43.0)
        }
        XCTAssertEqual(VocalLogic.SustainStats.longestRun(times: times), 9.98, accuracy: 0.05)
    }

    func testLongestOfMultipleRunsWins() {
        // Runs of 4 s, 12 s (with one bridged micro-gap), 6 s.
        var times: [Double] = []
        func run(_ from: Double, _ seconds: Double, dropEvery: Int? = nil) {
            var i = 0
            var t = from
            while t < from + seconds {
                if dropEvery.map({ i % $0 != 3 }) ?? true { times.append(t) }
                t += 1.0 / 40.0
                i += 1
            }
        }
        run(0, 4)
        run(5, 12, dropEvery: 60)
        run(20, 6)
        XCTAssertEqual(VocalLogic.SustainStats.longestRun(times: times), 12.0, accuracy: 0.06)
    }

    func testGapBeyondToleranceSplits() {
        // A 3 s run, 0.4 s of silence, then a 2 s run — only real detector
        // frame spacing (25 fps), not 1 s steps.
        let times = stride(from: 0.0, to: 3.0, by: 0.04).map { $0 }
            + stride(from: 3.4, to: 5.4, by: 0.04).map { $0 }
        XCTAssertEqual(VocalLogic.SustainStats.longestRun(times: times), 2.96, accuracy: 0.03)
    }

    func testFeedbackBands() {
        let caution = VocalLogic.SustainStats.feedback(seconds: 12, isFemale: nil)
        XCTAssertTrue(caution.contains("15초 미만"))
        let belowNorm = VocalLogic.SustainStats.feedback(seconds: 18, isFemale: false)
        XCTAssertTrue(belowNorm.contains("평균"))
        XCTAssertTrue(belowNorm.contains("2.8초"))  // 20.8 - 18
        let femaleAbove = VocalLogic.SustainStats.feedback(seconds: 18.5, isFemale: true)
        XCTAssertTrue(femaleAbove.contains("평균 이상"))
        let none = VocalLogic.SustainStats.feedback(seconds: 0, isFemale: nil)
        XCTAssertTrue(none.contains("잡히지 않았어요"))
    }
}
