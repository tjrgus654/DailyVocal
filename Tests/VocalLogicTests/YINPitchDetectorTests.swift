import XCTest
@testable import VocalLogic

final class YINPitchDetectorTests: XCTestCase {

    private let sampleRate = 48000.0

    /// Synthetic harmonic tone mirroring the self-test signal of the web
    /// prototype (fundamental + 2 overtones, stationary — an envelope would
    /// bias the parabolic refinement and measure the envelope, not YIN).
    private func synthTone(_ f0: Double, seconds: Double = 0.35) -> [Float] {
        let n = Int(sampleRate * seconds)
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            return Float((sin(2 * .pi * f0 * t)
                          + 0.3 * sin(2 * .pi * 2 * f0 * t)
                          + 0.12 * sin(2 * .pi * 3 * f0 * t)) * 0.6)
        }
    }

    func testAccurateAcrossVocalRange() {
        let detector = YINPitchDetector(sampleRate: sampleRate)
        let cases = [82.41, 110.0, 220.0, 329.63, 440.0, 659.25]
        for expected in cases {
            let estimate = detector.detect(in: synthTone(expected))
            XCTAssertGreaterThan(estimate.frequency, 0, "unvoiced for \(expected) Hz")
            let centsError = 1200 * log2(estimate.frequency / expected)
            XCTAssertEqual(abs(centsError), 0, accuracy: 0.5,
                           "\(expected) Hz -> \(estimate.frequency) Hz (\(centsError)¢)")
            XCTAssertTrue(estimate.isVoiced)
        }
    }

    func testSilenceAndQuietNoiseRejected() {
        let detector = YINPitchDetector(sampleRate: sampleRate)
        let silence = [Float](repeating: 0, count: Int(sampleRate * 0.3))
        XCTAssertEqual(detector.detect(in: silence).frequency, 0)

        var noise = [Float](repeating: 0, count: Int(sampleRate * 0.3))
        var seed: UInt32 = 1234
        for i in noise.indices {
            seed = seed &* 1_103_515_245 &+ 12_345
            noise[i] = Float(Double(seed % 10_000) / 10_000.0 - 0.5) * 0.005
        }
        XCTAssertFalse(detector.detect(in: noise).isVoiced)
    }

    func testOctaveStability() {
        // The detector must prefer the true fundamental, not an overtone.
        let detector = YINPitchDetector(sampleRate: sampleRate)
        let estimate = detector.detect(in: synthTone(130.81)) // C3
        XCTAssertEqual(estimate.frequency, 130.81, accuracy: 0.5)
    }
}
