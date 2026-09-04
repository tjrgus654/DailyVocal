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

    /// Property-style fuzz: 500 random draws across all levels and bases must
    /// never violate the contract (band, adjacency, level move pool).
    func testFuzzSequenceContract() {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: seed >> 33)) % 1_000_000
        }
        let moves = VocalLogic.echoMoveSets
        for _ in 0..<500 {
            let level = 1 + rnd() % 3
            let base = 43 + rnd() % 30
            let seq = VocalLogic.generateEchoSequence(base: base, level: level, roll: rnd)
            XCTAssertTrue(seq.allSatisfy { (43...72).contains($0) })
            XCTAssertEqual(seq.count, 3)
            XCTAssertNotEqual(seq[1], seq[0])
            XCTAssertNotEqual(seq[2], seq[1])
            XCTAssertTrue(moves[level - 1].contains(seq[1] - seq[0]))
            XCTAssertTrue(moves[level - 1].contains(seq[2] - seq[1]))
        }
    }

    func testDeterministicWithSeededRoll() {
        let a = VocalLogic.generateEchoSequence(base: 64, level: 2) { 3 }
        let b = VocalLogic.generateEchoSequence(base: 64, level: 2) { 3 }
        XCTAssertEqual(a, b)
    }
}
