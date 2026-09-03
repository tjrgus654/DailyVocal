import XCTest
@testable import VocalLogic

final class NoteMathTests: XCTestCase {

    func testMidiFrequencyRoundTrip() {
        for midi in stride(from: 36, through: 88, by: 7) {
            let freq = VocalLogic.frequency(forMidi: Double(midi))
            let back = VocalLogic.midiNumber(forFrequency: freq)
            XCTAssertEqual(back, Double(midi), accuracy: 1e-9)
        }
    }

    func testNoteNames() {
        XCTAssertEqual(VocalLogic.noteAndCents(fromFrequency: 440.0).note, "A4")
        XCTAssertEqual(VocalLogic.noteAndCents(fromFrequency: 261.6256).note, "C4")
        XCTAssertEqual(VocalLogic.noteAndCents(fromFrequency: 329.6276).note, "E4")
        XCTAssertEqual(VocalLogic.midiNumber(forNoteName: "C4"), 60)
        XCTAssertEqual(VocalLogic.midiNumber(forNoteName: "F#3"), 54)
        XCTAssertEqual(VocalLogic.midiNumber(forNoteName: "Bb4"), 70)
        XCTAssertNil(VocalLogic.midiNumber(forNoteName: "H4"))
    }

    func testCentsWithinNote() {
        // 442 Hz is +7.85 cents above A4=440.
        let cents = VocalLogic.noteAndCents(fromFrequency: 442.0).cents
        XCTAssertEqual(cents, 7.85, accuracy: 0.02)
        // Exactly one semitone up stays in-tune at the next note.
        let sharp = VocalLogic.noteAndCents(fromFrequency: 440.0 * pow(2.0, 1.0 / 12.0))
        XCTAssertEqual(sharp.note, "A#4")
        XCTAssertEqual(sharp.cents, 0, accuracy: 1e-6)
    }

    func testA4CalibrationShiftsReading() {
        // With the reference tuned to 442, a 442 Hz tone reads as exact A4.
        let calibrated = VocalLogic.noteAndCents(fromFrequency: 442.0, a4: 442.0)
        XCTAssertEqual(calibrated.note, "A4")
        XCTAssertEqual(calibrated.cents, 0, accuracy: 1e-9)
        // Non-positive / out-of-range inputs degrade gracefully.
        XCTAssertEqual(VocalLogic.noteAndCents(fromFrequency: 0).note, "--")
    }

    func testDegenerateFrequencyInputs() {
        // Negative and zero frequencies return the silent placeholder tuple.
        for bad in [0.0, -1.0, -440.0] {
            let result = VocalLogic.noteAndCents(fromFrequency: bad)
            XCTAssertEqual(result.note, "--")
            XCTAssertEqual(result.midi, 0)
            XCTAssertEqual(result.cents, 0)
            XCTAssertEqual(VocalLogic.midiNumber(forFrequency: bad), 0)
        }
        // Extreme-but-valid input stays representable.
        XCTAssertTrue(VocalLogic.midiNumber(forFrequency: 1.0) < 0) // sub-audio -> negative midi is fine
        XCTAssertGreaterThan(VocalLogic.midiNumber(forFrequency: 21000.0), 135)
    }

    func testDurationLabelBoundaries() {
        XCTAssertEqual(VocalLogic.durationLabel(seconds: 0), "0초")
        XCTAssertEqual(VocalLogic.durationLabel(seconds: 59), "59초")
        XCTAssertEqual(VocalLogic.durationLabel(seconds: 60), "1분 0초")
        XCTAssertEqual(VocalLogic.durationLabel(seconds: 61), "1분 1초")
        XCTAssertEqual(VocalLogic.durationLabel(seconds: 900), "15분 0초")
        XCTAssertEqual(VocalLogic.durationLabel(seconds: 3599), "59분 59초")
    }

    func testClampBoundsRespectedByEchoBand() {
        // The echo band 43...72 must map inside the canvas display band G2...D5.
        XCTAssertTrue((43...72).contains(VocalLogic.midiNumber(forNoteName: "G2")!))
        XCTAssertTrue((43...72).contains(VocalLogic.midiNumber(forNoteName: "C5")!))
    }
}
