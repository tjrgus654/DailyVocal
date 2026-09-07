import XCTest
@testable import VocalLogic

final class StretchLadderTests: XCTestCase {

    func testTargetsFromCeiling() {
        // Ceiling F4(65) -> [65, 66, 67].
        XCTAssertEqual(VocalLogic.stretchTargets(ceilingMidi: 65), [65, 66, 67])
        // Clamped at the band top (72).
        XCTAssertEqual(VocalLogic.stretchTargets(ceilingMidi: 71), [71, 72, 72])
    }

    func testBaseAFifthBelow() {
        XCTAssertEqual(VocalLogic.stretchBaseMidi(ceilingMidi: 65), 65 - 7)
        // Never below the band floor.
        XCTAssertEqual(VocalLogic.stretchBaseMidi(ceilingMidi: 45), 43)
    }

    func testRoundLabels() {
        XCTAssertEqual(VocalLogic.stretchRoundLabel(index: 0), "최고음 재확인")
        XCTAssertEqual(VocalLogic.stretchRoundLabel(index: 1), "한 음 위 도전")
        XCTAssertEqual(VocalLogic.stretchRoundLabel(index: 2), "두 음 위 도전")
    }

    func testReachedTolerance() {
        // base 58, target 65: performed 7 (= 65) reached; 6 (= 64) within 1 -> reached; 5 not.
        XCTAssertTrue(VocalLogic.stretchReached(performedSemitones: 7, targetMidi: 65, baseMidi: 58))
        XCTAssertTrue(VocalLogic.stretchReached(performedSemitones: 6, targetMidi: 65, baseMidi: 58))
        XCTAssertFalse(VocalLogic.stretchReached(performedSemitones: 5, targetMidi: 65, baseMidi: 58))
        XCTAssertFalse(VocalLogic.stretchReached(performedSemitones: nil, targetMidi: 65, baseMidi: 58))
    }

    func testFeedbackCoaching() {
        let reached = VocalLogic.stretchFeedback(reached: true, targetMidi: 65, baseMidi: 58, performedSemitones: 7)
        XCTAssertTrue(reached.contains("F4") && reached.contains("닿았습니다"))
        let short = VocalLogic.stretchFeedback(reached: false, targetMidi: 65, baseMidi: 58, performedSemitones: 5)
        XCTAssertTrue(short.contains("2반음 아래") && short.contains("F4"))
        let silent = VocalLogic.stretchFeedback(reached: false, targetMidi: 65, baseMidi: 58, performedSemitones: nil)
        XCTAssertTrue(silent.contains("잡히지 않았어요"))
    }

    func testNoteName() {
        XCTAssertEqual(VocalLogic.noteName(forMidi: 60), "C4")
        XCTAssertEqual(VocalLogic.noteName(forMidi: 69), "A4")
        XCTAssertEqual(VocalLogic.noteName(forMidi: 71), "B4")
    }
}
