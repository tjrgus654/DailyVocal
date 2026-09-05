import XCTest
@testable import VocalLogic

final class MelodyContourTests: XCTestCase {

    func testContourLengths() {
        XCTAssertEqual(VocalLogic.MelodyContour.ascending.noteCount, 4)
        XCTAssertEqual(VocalLogic.MelodyContour.descending.noteCount, 4)
        XCTAssertEqual(VocalLogic.MelodyContour.arch.noteCount, 6)
        XCTAssertEqual(VocalLogic.MelodyContour.wave.noteCount, 6)
    }

    func testContourLevelLadder() {
        // Deterministic roll: L1 only up/down, L2 only arch/wave.
        for roll in 0..<50 {
            let l1 = VocalLogic.melodyContour(level: 1, roll: { roll })
            XCTAssertTrue([.ascending, .descending].contains(l1), "\(l1) at roll \(roll)")
            let l2 = VocalLogic.melodyContour(level: 2, roll: { roll })
            XCTAssertTrue([.arch, .wave].contains(l2), "\(l2) at roll \(roll)")
            let l3 = VocalLogic.melodyContour(level: 3, roll: { roll })
            XCTAssertTrue(VocalLogic.MelodyContour.allCases.contains(l3))
        }
        // Clamp outside 1...3.
        XCTAssertEqual(VocalLogic.melodyContour(level: 0, roll: { 0 }), .ascending)
        XCTAssertEqual(VocalLogic.melodyContour(level: 9, roll: { 1 }), .descending)
    }

    func testAscendingPhraseOnlyRises() {
        let phrase = VocalLogic.melodyPhrase(contour: .ascending, baseMidi: 60, roll: { 0 })
        XCTAssertEqual(phrase.count, 4)
        XCTAssertEqual(phrase.first, 60)
        // Step with roll 0 = 1 semitone.
        XCTAssertEqual(phrase, [60, 61, 62, 63])
        for (a, b) in zip(phrase, phrase.dropFirst()) {
            XCTAssertGreaterThan(b, a, "ascending phrase must rise: \(phrase)")
        }
    }

    func testDescendingPhraseOnlyFalls() {
        let phrase = VocalLogic.melodyPhrase(contour: .descending, baseMidi: 67, roll: { 0 })
        XCTAssertEqual(phrase, [67, 66, 65, 64])
        for (a, b) in zip(phrase, phrase.dropFirst()) {
            XCTAssertLessThan(b, a, "descending phrase must fall: \(phrase)")
        }
    }

    func testArchRisesThenFalls() {
        let phrase = VocalLogic.melodyPhrase(contour: .arch, baseMidi: 60, roll: { 0 })
        XCTAssertEqual(phrase.count, 6)
        // 6 notes: indices 0..4 generate steps; up while count < 3.
        XCTAssertEqual(phrase, [60, 61, 62, 63, 62, 61])
        let peak = phrase.max()!
        XCTAssertNotEqual(peak, phrase.first!, "arch must rise above the start")
        XCTAssertNotEqual(peak, phrase.last!, "arch must fall before the end")
    }

    func testWaveAlternatesEveryTwoNotes() {
        let phrase = VocalLogic.melodyPhrase(contour: .wave, baseMidi: 60, roll: { 0 })
        XCTAssertEqual(phrase.count, 6)
        // Direction flips every two notes: up,up then down,down then up
        // (all ±1 with roll 0) -> 60,61,60,59,60,61.
        XCTAssertEqual(phrase, [60, 61, 60, 59, 60, 61])
    }

    func testPhraseStaysInBandForAllBases() {
        for base in 43...72 {
            for contour in VocalLogic.MelodyContour.allCases {
                let phrase = VocalLogic.melodyPhrase(contour: contour, baseMidi: base, roll: { 7 })
                XCTAssertEqual(phrase.first!, base, "\(contour) from \(base)")
                XCTAssertTrue(phrase.allSatisfy { (43...72).contains($0) },
                              "\(contour) from \(base): \(phrase)")
            }
        }
    }

    func testDeterministicUnderFixedRoll() {
        let rollValues = [3, 1, 4, 1, 5, 9, 2, 6]
        func phrase(_ run: Int) -> [Int] {
            var i = 0
            return VocalLogic.melodyPhrase(contour: .arch, baseMidi: 55, roll: {
                defer { i += 1 }
                return rollValues[i % rollValues.count] + run * 0
            })
        }
        XCTAssertEqual(phrase(0), phrase(1), "same roll sequence must give the same phrase")
    }

    // MARK: - Dictation ladder (phrase length grows with level)

    func testMelodyLengthLadder() {
        XCTAssertEqual(VocalLogic.melodyLength(level: 1), 4)
        XCTAssertEqual(VocalLogic.melodyLength(level: 2), 6)
        XCTAssertEqual(VocalLogic.melodyLength(level: 3), 8)
        // Clamped outside 1...3.
        XCTAssertEqual(VocalLogic.melodyLength(level: 0), 4)
        XCTAssertEqual(VocalLogic.melodyLength(level: 9), 8)
    }

    func testLadderPhraseShapes() {
        // L3 arch (8 notes, roll 0): rise through 4, then fall — symmetric.
        let arch8 = VocalLogic.melodyPhrase(contour: .arch, baseMidi: 60, roll: { 0 }, noteCount: 8)
        XCTAssertEqual(arch8, [60, 61, 62, 63, 64, 63, 62, 61])
        // L3 wave (8 notes): flip every two notes.
        let wave8 = VocalLogic.melodyPhrase(contour: .wave, baseMidi: 60, roll: { 0 }, noteCount: 8)
        XCTAssertEqual(wave8, [60, 61, 60, 59, 60, 61, 60, 59])
        // L1 lengths apply to every contour.
        for contour in VocalLogic.MelodyContour.allCases {
            let phrase = VocalLogic.melodyPhrase(contour: contour, baseMidi: 60, roll: { 0 }, noteCount: 4)
            XCTAssertEqual(phrase.count, 4, "\(contour)")
        }
        // Degenerate noteCount is floored at 2, never crashes.
        XCTAssertEqual(VocalLogic.melodyPhrase(contour: .ascending, baseMidi: 60, roll: { 0 }, noteCount: 0).count, 2)
    }

    func testLadderPhrasesStayInBand() {
        for level in 1...3 {
            let length = VocalLogic.melodyLength(level: level)
            for base in 43...72 {
                for contour in VocalLogic.MelodyContour.allCases {
                    let phrase = VocalLogic.melodyPhrase(
                        contour: contour, baseMidi: base, roll: { 7 }, noteCount: length)
                    XCTAssertEqual(phrase.count, length)
                    XCTAssertEqual(phrase.first!, base, "\(contour) L\(level) from \(base)")
                    XCTAssertTrue(phrase.allSatisfy { (43...72).contains($0) },
                                  "\(contour) L\(level) from \(base): \(phrase)")
                }
            }
        }
    }
}
