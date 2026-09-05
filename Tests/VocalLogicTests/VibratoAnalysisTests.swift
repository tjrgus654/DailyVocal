import XCTest
@testable import VocalLogic

final class VibratoAnalysisTests: XCTestCase {

    /// Synthesizes a sustained note with sinusoidal pitch modulation.
    /// `rateHz` oscillations per second, `extentCents` peak deviation.
    static func syntheticNote(
        baseHz: Double, rateHz: Double, extentCents: Double,
        frameRate: Double, seconds: Double
    ) -> [Double] {
        let frameCount = Int(frameRate * seconds)
        return (0..<frameCount).map { i in
            let t = Double(i) / frameRate
            let cents = extentCents * sin(2 * .pi * rateHz * t)
            return baseHz * pow(2, cents / 1200)
        }
    }

    // MARK: - Ideal vibrato

    func testIdealVibratoIsDetected() {
        // 5.5 Hz ±50 cents — squarely inside the trained-singer band.
        let trace = Self.syntheticNote(
            baseHz: 220, rateHz: 5.5, extentCents: 50, frameRate: 50, seconds: 4)
        let m = VocalLogic.VibratoAnalysis.analyze(frequencies: trace, frameRate: 50)
        XCTAssertEqual(m.voicedFrames, 200)
        XCTAssertTrue(m.hasVibrato, "rate=\(m.rateHz) extent=\(m.extentCents) reg=\(m.regularity)")
        XCTAssertEqual(m.rateHz, 5.5, accuracy: 0.3)
        XCTAssertEqual(m.extentCents, 50, accuracy: 8)
        XCTAssertGreaterThanOrEqual(m.regularity, 0.8)
    }

    func testVibratoWithDriftStillMeasured() {
        // ±60 cents at 6 Hz ON TOP of a 150-cent sag over 4 s: the detrend
        // step must remove the drift without destroying the modulation.
        let frameCount = 200
        let trace = (0..<frameCount).map { i -> Double in
            let t = Double(i) / 50
            let drift = -150.0 * t / 4
            let cents = 60 * sin(2 * .pi * 6.0 * t) + drift
            return 330 * pow(2, cents / 1200)
        }
        let m = VocalLogic.VibratoAnalysis.analyze(frequencies: trace, frameRate: 50)
        XCTAssertTrue(m.hasVibrato, "rate=\(m.rateHz) extent=\(m.extentCents) reg=\(m.regularity)")
        XCTAssertEqual(m.rateHz, 6.0, accuracy: 0.3)
        XCTAssertEqual(m.extentCents, 60, accuracy: 10)
    }

    // MARK: - Negative cases

    func testStraightToneHasNoVibrato() {
        let trace = [Double](repeating: 220, count: 200)
        let m = VocalLogic.VibratoAnalysis.analyze(frequencies: trace, frameRate: 50)
        XCTAssertFalse(m.hasVibrato)
        XCTAssertEqual(m.rateHz, 0)
        XCTAssertEqual(m.regularity, 0)
        XCTAssertEqual(m.voicedFrames, 200)
    }

    func testSlowDriftAloneIsNotVibrato() {
        // A 100-cent rise over 4 s with no oscillation.
        let trace = (0..<200).map { i -> Double in
            220 * pow(2, (100.0 * Double(i) / 199) / 1200)
        }
        let m = VocalLogic.VibratoAnalysis.analyze(frequencies: trace, frameRate: 50)
        XCTAssertFalse(m.hasVibrato)
    }

    func testSlowWobbleOutsideBandRejected() {
        // 3 Hz wobble: below the 3.5 Hz vibrato floor.
        let trace = Self.syntheticNote(
            baseHz: 196, rateHz: 3.0, extentCents: 80, frameRate: 50, seconds: 4)
        let m = VocalLogic.VibratoAnalysis.analyze(frequencies: trace, frameRate: 50)
        XCTAssertFalse(m.hasVibrato, "rate=\(m.rateHz)")
    }

    func testShortTraceReturnsNone() {
        let trace = Self.syntheticNote(
            baseHz: 220, rateHz: 5.5, extentCents: 50, frameRate: 50, seconds: 0.6)
        let m = VocalLogic.VibratoAnalysis.analyze(frequencies: trace, frameRate: 50)
        XCTAssertEqual(m, .none)
    }

    func testUnvoicedFramesAreFiltered() {
        // Real traces lose unvoiced frames, so the survivors are unevenly
        // spaced: the times-based overload resamples onto a uniform grid and
        // must still recover the true rate.
        let frameRate = 50.0
        let clean = Self.syntheticNote(
            baseHz: 247, rateHz: 5.0, extentCents: 70, frameRate: frameRate, seconds: 4)
        var times: [Double] = []
        var freqs: [Double] = []
        for (i, f) in clean.enumerated() {
            if i % 10 == 5 { continue }  // simulated unvoiced dropouts
            times.append(Double(i) / frameRate)
            freqs.append(f)
        }
        let m = VocalLogic.VibratoAnalysis.analyze(times: times, frequencies: freqs)
        XCTAssertTrue(m.hasVibrato, "rate=\(m.rateHz) extent=\(m.extentCents)")
        XCTAssertEqual(m.rateHz, 5.0, accuracy: 0.35)
        XCTAssertEqual(m.extentCents, 70, accuracy: 12)
    }

    // MARK: - Score & coaching

    func testVibratoScoreBands() {
        let ideal = VocalLogic.VibratoMeasurement(rateHz: 5.5, extentCents: 70, regularity: 0.9, voicedFrames: 200)
        XCTAssertEqual(VocalLogic.vibratoScore(ideal), 100)
        // In-band rate but shallow extent and low regularity.
        let shallow = VocalLogic.VibratoMeasurement(rateHz: 5.5, extentCents: 20, regularity: 0.5, voicedFrames: 200)
        XCTAssertEqual(VocalLogic.vibratoScore(shallow), 50 + 25 + 7 + 0)
        // Slow-but-valid vibrato.
        let slow = VocalLogic.VibratoMeasurement(rateHz: 3.8, extentCents: 80, regularity: 0.75, voicedFrames: 200)
        XCTAssertEqual(VocalLogic.vibratoScore(slow), 50 + 10 + 15 + 10)
        // No vibrato at all.
        XCTAssertEqual(VocalLogic.vibratoScore(.none), 0)
    }

    func testFeedbackCoachingText() {
        let ideal = VocalLogic.VibratoMeasurement(rateHz: 5.5, extentCents: 70, regularity: 0.9, voicedFrames: 200)
        let tips = VocalLogic.vibratoFeedback(for: ideal)
        XCTAssertTrue(tips.contains { $0.contains("이상적인") })

        let wobble = VocalLogic.VibratoMeasurement(rateHz: 3.8, extentCents: 90, regularity: 0.8, voicedFrames: 200)
        XCTAssertTrue(VocalLogic.vibratoFeedback(for: wobble).contains { $0.contains("워블") })

        let trill = VocalLogic.VibratoMeasurement(rateHz: 7.2, extentCents: 90, regularity: 0.8, voicedFrames: 200)
        XCTAssertTrue(VocalLogic.vibratoFeedback(for: trill).contains { $0.contains("떨림") })

        let short = VocalLogic.VibratoMeasurement(rateHz: 5.5, extentCents: 70, regularity: 0.9, voicedFrames: 20)
        XCTAssertTrue(VocalLogic.vibratoFeedback(for: short).contains { $0.contains("짧았어요") })

        let straight = VocalLogic.VibratoMeasurement(rateHz: 0, extentCents: 5, regularity: 0.1, voicedFrames: 200)
        XCTAssertTrue(VocalLogic.vibratoFeedback(for: straight).contains { $0.contains("직진") })
    }
}
