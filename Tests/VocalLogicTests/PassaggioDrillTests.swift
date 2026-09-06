import XCTest
@testable import VocalLogic

final class PassaggioDrillTests: XCTestCase {

    func testBaritoneArchCrossesZoneTwice() {
        // Baritone zone E4..G4 (64...67): arch 62,64,65,67,68,67,65,64.
        let seq = VocalLogic.passaggioSequence(voiceType: .baritone)
        XCTAssertEqual(seq, [62, 64, 65, 67, 68, 67, 65, 64])
    }

    func testEveryMaleVoiceTypeCrossesItsZone() {
        for type in [VocalLogic.VoiceType.tenor, .baritone, .bass] {
            let zone = VocalLogic.passaggioZone(for: type)!
            let seq = VocalLogic.passaggioSequence(voiceType: type)
            // Both zone edges appear — the arch enters below and exits above.
            XCTAssertTrue(seq.contains(zone.lowerBound), "\(type)")
            XCTAssertTrue(seq.contains(zone.upperBound), "\(type)")
            // Rises through, falls back: first half ascending, final note = lo.
            XCTAssertEqual(seq.first, zone.lowerBound - 2, "\(type)")
            XCTAssertEqual(seq.last, zone.lowerBound, "\(type)")
            XCTAssertEqual(seq.count, 8, "\(type)")
        }
    }

    func testUndeterminedFallsBackToBaritoneZone() {
        let seq = VocalLogic.passaggioSequence(voiceType: .undetermined)
        XCTAssertEqual(seq, VocalLogic.passaggioSequence(voiceType: .baritone))
    }

    func testFemaleZoneClampsIntoSingingBand() {
        // Soprano zone 74...78 is above the band top (72): the drill must
        // stay inside the band rather than leave it.
        let seq = VocalLogic.passaggioSequence(voiceType: .soprano)
        XCTAssertTrue(seq.allSatisfy { (43...72).contains($0) }, "\(seq)")
    }
}
