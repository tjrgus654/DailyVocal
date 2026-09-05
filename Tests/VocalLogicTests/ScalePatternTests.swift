import XCTest
@testable import VocalLogic

final class ScalePatternTests: XCTestCase {

    func testPatternIntervalsAreTheStandardLadder() {
        XCTAssertEqual(VocalLogic.ScalePattern.pentatonicUp.offsets, [0, 2, 4, 7, 9])
        XCTAssertEqual(VocalLogic.ScalePattern.majorScale.offsets, [0, 2, 4, 5, 7, 9, 11, 12])
        XCTAssertEqual(VocalLogic.ScalePattern.arpeggioSweep.offsets, [0, 4, 7, 12, 7, 4, 0])
    }

    func testLevelToPattern() {
        XCTAssertEqual(VocalLogic.scalePattern(level: 1), .pentatonicUp)
        XCTAssertEqual(VocalLogic.scalePattern(level: 2), .majorScale)
        XCTAssertEqual(VocalLogic.scalePattern(level: 3), .arpeggioSweep)
        // Clamped outside 1...3.
        XCTAssertEqual(VocalLogic.scalePattern(level: 0), .pentatonicUp)
        XCTAssertEqual(VocalLogic.scalePattern(level: 9), .arpeggioSweep)
    }

    func testSequenceFromBase() {
        // C4 (60) major scale climbs to C5 (72).
        XCTAssertEqual(
            VocalLogic.scaleSequence(baseMidi: 60, pattern: .majorScale),
            [60, 62, 64, 65, 67, 69, 71, 72])
        XCTAssertEqual(
            VocalLogic.scaleSequence(baseMidi: 55, pattern: .arpeggioSweep),
            [55, 59, 62, 67, 62, 59, 55])
    }

    func testSequenceIsClampedToSingingBand() {
        // A4 (69) major scale would reach 81; the band caps at 72.
        let top = VocalLogic.scaleSequence(baseMidi: 69, pattern: .majorScale)
        XCTAssertTrue(top.allSatisfy { (43...72).contains($0) }, "\(top)")
        XCTAssertEqual(top.last, 72)
        // Below the band from an unusually low base.
        let low = VocalLogic.scaleSequence(baseMidi: 40, pattern: .pentatonicUp)
        XCTAssertTrue(low.allSatisfy { (43...72).contains($0) }, "\(low)")
        XCTAssertEqual(low.first, 43)
    }

    func testEveryPatternStartsOnTheBaseAndStaysInBand() {
        for pattern in VocalLogic.ScalePattern.allCases {
            for base in 43...72 {
                let seq = VocalLogic.scaleSequence(baseMidi: base, pattern: pattern)
                XCTAssertEqual(seq.count, pattern.offsets.count)
                XCTAssertEqual(seq.first, base, "\(pattern) from \(base)")
                XCTAssertTrue(seq.allSatisfy { (43...72).contains($0) }, "\(pattern) from \(base): \(seq)")
            }
        }
    }
}
