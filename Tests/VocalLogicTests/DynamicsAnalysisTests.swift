import XCTest
@testable import VocalLogic

final class DynamicsAnalysisTests: XCTestCase {

    /// Builds a linear-amplitude envelope from a dB-per-frame closure.
    static func envelope(frames: Int, db: (Double) -> Double) -> [Double] {
        (0..<frames).map { i in pow(10, db(Double(i) / Double(frames - 1)) / 20) }
    }

    // MARK: - Ideal arch (messa di voce)

    func testIdealArchDetected() {
        // Soft -> loud -> soft: -20 dB floor with a 14 dB sine arch on top.
        let trace = Self.envelope(frames: 150) { t in -20 + 14 * sin(.pi * t) }
        let m = VocalLogic.DynamicsAnalysis.analyze(amplitudes: trace)
        XCTAssertEqual(m.voicedFrames, 150)
        XCTAssertTrue(m.hasArch, "range=\(m.rangeDb) cres=\(m.crescendoDb) decres=\(m.decrescendoDb) peak=\(m.peakPosition)")
        XCTAssertEqual(m.rangeDb, 14, accuracy: 2)
        XCTAssertGreaterThanOrEqual(m.crescendoDb, 6)
        XCTAssertGreaterThanOrEqual(m.decrescendoDb, 6)
        XCTAssertEqual(m.peakPosition, 0.5, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(m.smoothness, 0.6)
        XCTAssertEqual(VocalLogic.dynamicsScore(m), 100)
    }

    func testArchFeedbackMentionsRange() {
        let trace = Self.envelope(frames: 150) { t in -20 + 14 * sin(.pi * t) }
        let m = VocalLogic.DynamicsAnalysis.analyze(amplitudes: trace)
        let tips = VocalLogic.dynamicsFeedback(for: m)
        XCTAssertTrue(tips.contains { $0.contains("아치 완성") })
        XCTAssertTrue(tips.contains { $0.contains("12dB") })
    }

    // MARK: - Negative cases

    func testFlatToneHasNoArch() {
        let trace = [Double](repeating: 0.1, count: 150)  // constant -20 dB
        let m = VocalLogic.DynamicsAnalysis.analyze(amplitudes: trace)
        XCTAssertFalse(m.hasArch)
        XCTAssertLessThan(m.rangeDb, 1)
        XCTAssertEqual(VocalLogic.dynamicsScore(m), 40)
        XCTAssertTrue(VocalLogic.dynamicsFeedback(for: m).contains { $0.contains("레인지가") })
    }

    func testCrescendoOnlyCoachedToFinishTheArch() {
        // Rises -20 -> -8 dB and stays loud: the decrescendo half is missing.
        let trace = Self.envelope(frames: 150) { t in -20 + 12 * min(1, t * 2) }
        let m = VocalLogic.DynamicsAnalysis.analyze(amplitudes: trace)
        XCTAssertFalse(m.hasArch)
        XCTAssertGreaterThanOrEqual(m.rangeDb, 6)
        XCTAssertTrue(VocalLogic.dynamicsFeedback(for: m).contains { $0.contains("디크레셴도") })
    }

    func testEarlyPeakCoachedToCenterIt() {
        // Fast rise to the peak by t=0.15, then a long slow fade: both
        // directions exist, but the apex sits too early.
        let trace = Self.envelope(frames: 150) { t in
            if t < 0.15 { return -20 + 14 * (t / 0.15) }
            return -6 - 14 * ((t - 0.15) / 0.85)  // fades to -20 dB
        }
        let m = VocalLogic.DynamicsAnalysis.analyze(amplitudes: trace)
        XCTAssertFalse(m.hasArch)
        XCTAssertGreaterThanOrEqual(m.crescendoDb, 3)
        XCTAssertGreaterThanOrEqual(m.decrescendoDb, 3)
        XCTAssertTrue(VocalLogic.dynamicsFeedback(for: m).contains { $0.contains("너무 일찍") })
    }

    func testShortTraceReturnsNone() {
        let trace = [Double](repeating: 0.1, count: 30)
        let m = VocalLogic.DynamicsAnalysis.analyze(amplitudes: trace)
        XCTAssertEqual(m, .none)
        XCTAssertEqual(VocalLogic.dynamicsScore(m), 0)
        XCTAssertTrue(VocalLogic.dynamicsFeedback(for: m).contains { $0.contains("짧았어요") })
    }

    // MARK: - Score composition

    func testScoreBands() {
        // Decrescendo missing, everything else fine: 40 + 15 + 0 + 15 + 10 + 5.
        let partial = VocalLogic.DynamicsMeasurement(
            rangeDb: 8, crescendoDb: 5, decrescendoDb: 1,
            peakPosition: 0.5, smoothness: 0.7, voicedFrames: 150)
        XCTAssertEqual(VocalLogic.dynamicsScore(partial), 85)
        // Range and both directions but jittery envelope and off-center peak:
        let jittery = VocalLogic.DynamicsMeasurement(
            rangeDb: 7, crescendoDb: 4, decrescendoDb: 4,
            peakPosition: 0.2, smoothness: 0.3, voicedFrames: 150)
        XCTAssertEqual(VocalLogic.dynamicsScore(jittery), 40 + 15 + 15 + 15)
    }

    func testMovingAverageIsCentered() {
        let input: [Double] = [1, 1, 1, 1, 1, 100, 1, 1, 1, 1, 1]
        let out = VocalLogic.DynamicsAnalysis.movingAverage(input, window: 5)
        XCTAssertEqual(out.count, input.count)
        // The spike at index 5 influences out[3..7]; its mirror pair around
        // the spike center is out[3] vs out[7].
        XCTAssertGreaterThan(out[4], out[2])
        XCTAssertEqual(out[3], out[7], accuracy: 1e-9)
    }
}
