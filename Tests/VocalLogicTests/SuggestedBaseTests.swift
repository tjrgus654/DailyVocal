import XCTest
@testable import VocalLogic

final class SuggestedBaseTests: XCTestCase {

    func testMaleFallbackWithoutRange() {
        // No measured range: male G3(55), female C4(60).
        XCTAssertEqual(VocalLogic.suggestedBaseMidi(prefersHigherKey: false, lowestMidi: 0, highestMidi: 0), 55)
        XCTAssertEqual(VocalLogic.suggestedBaseMidi(prefersHigherKey: true, lowestMidi: 0, highestMidi: 0), 60)
    }

    func testMeasuredRangeWinsOverKeyPreference() {
        // A measured (male-typical) range G2..G4 -> base E3 (55+... G2=43 -> 47).
        XCTAssertEqual(VocalLogic.suggestedBaseMidi(prefersHigherKey: true, lowestMidi: 43, highestMidi: 67), 47)
        // High range keeps the comfortable-above-bottom rule regardless of key pref.
        XCTAssertEqual(VocalLogic.suggestedBaseMidi(prefersHigherKey: false, lowestMidi: 55, highestMidi: 72), 59)
    }

    func testCeilingKeepsPhraseTopsInsideBand() {
        // Very high measured range: base clamps so +10 (phrase top) stays <= 72.
        let base = VocalLogic.suggestedBaseMidi(prefersHigherKey: true, lowestMidi: 66, highestMidi: 72)
        XCTAssertEqual(base, 62)
    }

    func testFloorKeepsBaseInBand() {
        // lowestMidi 40 is below the band floor 43: base floors at 43+4.
        let base = VocalLogic.suggestedBaseMidi(prefersHigherKey: false, lowestMidi: 40, highestMidi: 50)
        XCTAssertEqual(base, 44)
    }

    func testMaleTypicalProfile() {
        // Typical male measured range ~A2..E4 (45..64): base = 49 (C#3-ish),
        // a phrase rising +10 tops at 59 — comfortably below the E4 passaggio.
        let base = VocalLogic.suggestedBaseMidi(prefersHigherKey: false, lowestMidi: 45, highestMidi: 64)
        XCTAssertEqual(base, 49)
    }
}
