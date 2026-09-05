import XCTest
@testable import VocalLogic

final class HarmonyPartTests: XCTestCase {

    func testPartOffsets() {
        XCTAssertEqual(VocalLogic.HarmonyPart.thirdAbove.offset, 4)
        XCTAssertEqual(VocalLogic.HarmonyPart.thirdBelow.offset, -4)
        XCTAssertEqual(VocalLogic.HarmonyPart.fifthAbove.offset, 7)
        XCTAssertEqual(VocalLogic.HarmonyPart.fifthBelow.offset, -7)
    }

    func testPartLadder() {
        for roll in 0..<50 {
            XCTAssertTrue([.thirdAbove, .thirdBelow].contains(
                VocalLogic.harmonyPart(level: 1, roll: { roll })), "L1 roll \(roll)")
            XCTAssertTrue([.fifthAbove, .fifthBelow].contains(
                VocalLogic.harmonyPart(level: 2, roll: { roll })), "L2 roll \(roll)")
            XCTAssertTrue(VocalLogic.HarmonyPart.allCases.contains(
                VocalLogic.harmonyPart(level: 3, roll: { roll })))
        }
        XCTAssertEqual(VocalLogic.harmonyPart(level: 0, roll: { 0 }), .thirdAbove)
        XCTAssertEqual(VocalLogic.harmonyPart(level: 9, roll: { 0 }), .thirdAbove)
    }

    func testHarmonyTarget() {
        XCTAssertEqual(VocalLogic.harmonyTarget(baseMidi: 60, part: .thirdAbove), 64)
        XCTAssertEqual(VocalLogic.harmonyTarget(baseMidi: 60, part: .fifthBelow), 53)
        // Clamped to the band edges.
        XCTAssertEqual(VocalLogic.harmonyTarget(baseMidi: 70, part: .fifthAbove), 72)
        XCTAssertEqual(VocalLogic.harmonyTarget(baseMidi: 45, part: .thirdBelow), 43)
    }

    func testHarmonyFeedbackBands() {
        XCTAssertTrue(VocalLogic.harmonyFeedback(part: .thirdAbove, cents: 8).contains("맞았습니다"))
        XCTAssertTrue(VocalLogic.harmonyFeedback(part: .fifthAbove, cents: -30).contains("센트 차이"))
        XCTAssertTrue(VocalLogic.harmonyFeedback(part: .thirdBelow, cents: 90).contains("아래로"))
        XCTAssertTrue(VocalLogic.harmonyFeedback(part: .fifthBelow, cents: -90).contains("위로"))
    }
}
