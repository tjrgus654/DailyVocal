import XCTest
@testable import VocalLogic

final class DailySummaryTests: XCTestCase {

    func testHiddenBeforeSecondSession() {
        XCTAssertNil(VocalLogic.dailySummaryLine(routineSessions: 0, techniqueMeasures: 3, bestScore: 90))
        XCTAssertNil(VocalLogic.dailySummaryLine(routineSessions: 1, techniqueMeasures: 3, bestScore: 90))
    }

    func testShownFromSecondSession() {
        XCTAssertEqual(
            VocalLogic.dailySummaryLine(routineSessions: 2, techniqueMeasures: 3, bestScore: 84),
            "오늘의 마무리: 루틴 2회 · 테크닉 측정 3회 · 최고 84점")
    }

    func testOmitsEmptyParts() {
        // No technique measures: the segment drops entirely.
        XCTAssertEqual(
            VocalLogic.dailySummaryLine(routineSessions: 2, techniqueMeasures: 0, bestScore: 70),
            "오늘의 마무리: 루틴 2회 · 최고 70점")
        // No scores at all.
        XCTAssertEqual(
            VocalLogic.dailySummaryLine(routineSessions: 3, techniqueMeasures: 1, bestScore: nil),
            "오늘의 마무리: 루틴 3회 · 테크닉 측정 1회")
    }
}
