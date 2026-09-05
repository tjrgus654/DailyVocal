import XCTest
@testable import VocalLogic

final class DrillTempoTests: XCTestCase {

    func testClamp() {
        XCTAssertEqual(VocalLogic.DrillTempo.clamped(30), 40)
        XCTAssertEqual(VocalLogic.DrillTempo.clamped(40), 40)
        XCTAssertEqual(VocalLogic.DrillTempo.clamped(50), 50)
        XCTAssertEqual(VocalLogic.DrillTempo.clamped(80), 80)
        XCTAssertEqual(VocalLogic.DrillTempo.clamped(200), 80)
    }

    func testTimingsAtDefault() {
        // 50 BPM -> beat 1.2s: note 1.02 / gap 0.18 / window 1.8 —
        // within rounding of the previous fixed timings (0.9/0.25/1.8).
        let t = VocalLogic.DrillTempo.timings(bpm: 50)
        XCTAssertEqual(t.note, 1.02, accuracy: 0.001)
        XCTAssertEqual(t.gap, 0.18, accuracy: 0.001)
        XCTAssertEqual(t.window, 1.8, accuracy: 0.001)
    }

    func testTimingsScaleWithBpm() {
        let slow = VocalLogic.DrillTempo.timings(bpm: 40)
        let fast = VocalLogic.DrillTempo.timings(bpm: 80)
        // Faster BPM -> strictly shorter note and window.
        XCTAssertLessThan(fast.note, slow.note)
        XCTAssertLessThan(fast.window, slow.window)
        // 40 BPM: beat 1.5s -> note 1.275 / window 2.25.
        XCTAssertEqual(slow.note, 1.275, accuracy: 0.001)
        XCTAssertEqual(slow.window, 2.25, accuracy: 0.001)
        // 80 BPM: beat 0.75s -> note 0.6375 / window 1.125.
        XCTAssertEqual(fast.note, 0.6375, accuracy: 0.001)
        XCTAssertEqual(fast.window, 1.125, accuracy: 0.001)
    }

    func testTimingsClampOutOfRangeBpm() {
        XCTAssertEqual(
            VocalLogic.DrillTempo.timings(bpm: 10).note,
            VocalLogic.DrillTempo.timings(bpm: 40).note,
            accuracy: 1e-9)
        XCTAssertEqual(
            VocalLogic.DrillTempo.timings(bpm: 500).window,
            VocalLogic.DrillTempo.timings(bpm: 80).window,
            accuracy: 1e-9)
    }

    func testNotePlusGapFillsOneBeat() {
        for bpm in [40, 50, 63, 80] {
            let t = VocalLogic.DrillTempo.timings(bpm: bpm)
            XCTAssertEqual(t.note + t.gap, 60.0 / Double(VocalLogic.DrillTempo.clamped(bpm)), accuracy: 1e-9,
                           "note+gap must equal exactly one beat at \(bpm) BPM")
        }
    }
}
