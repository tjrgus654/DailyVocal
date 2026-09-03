import XCTest
@testable import VocalLogic

final class EchoDesignTests: XCTestCase {

    func testMoveSetsByLevel() {
        XCTAssertEqual(VocalLogic.echoMoveSets[0], [-3, -2, 2, 3])
        XCTAssertEqual(VocalLogic.echoMoveSets[1], [-5, -4, -3, -2, 2, 3, 4, 5])
        XCTAssertEqual(VocalLogic.echoMoveSets[2], [-7, -5, -4, -3, 2, 3, 4, 5, 7])
    }

    /// Deterministic exhaustive check: for every base in the singing band and
    /// every possible roll, the generated sequence obeys the contract.
    func testSequenceContractForAllBasesAndRolls() {
        for level in 1...3 {
            let moves = VocalLogic.echoMoveSets[level - 1]
            for base in 43...72 {
                for roll in 0..<97 {
                    let seq = VocalLogic.generateEchoSequence(base: base, level: level) { roll }
                    XCTAssertEqual(seq.count, 3, "level \(level) base \(base) roll \(roll)")
                    // All notes inside the band.
                    XCTAssertTrue(seq.allSatisfy { (43...72).contains($0) }, "\(seq)")
                    // First note is the base; consecutive notes differ; the
                    // applied move is from the level's pool.
                    XCTAssertEqual(seq[0], base)
                    XCTAssertNotEqual(seq[1], seq[0])
                    XCTAssertNotEqual(seq[2], seq[1])
                    XCTAssertTrue(moves.contains(seq[1] - seq[0]), "\(seq)")
                    XCTAssertTrue(moves.contains(seq[2] - seq[1]), "\(seq)")
                }
            }
        }
    }

    func testDeterministicWithSeededRoll() {
        let a = VocalLogic.generateEchoSequence(base: 64, level: 2) { 3 }
        let b = VocalLogic.generateEchoSequence(base: 64, level: 2) { 3 }
        XCTAssertEqual(a, b)
    }
}
