#if canImport(AVFoundation) && os(macOS)
import XCTest
import AVFoundation
@testable import VocalLogic

/// macOS-only REAL-RUN pipeline integration tests (executed by the CI
/// typecheck workflow's `swift test`). A synthesized voice buffer follows the
/// same frame path the mic tap uses — YIN pitch, per-frame RMS, and the
/// Goertzel magnitude spectrum — so every analyzer (pitch / vibrato /
/// dynamics / formants / sustain) is measured on audio that actually went
/// through buffers and frames. Only the physical microphone is excluded;
/// that is the standard CI pattern (simctl has no audio injection).
final class AudioPipelineIntegrationTests: XCTestCase {

    static let sampleRate: Double = 44_100

    /// Harmonic voice: instantaneous f0 with decaying harmonics, formant
    /// emphasis around 700 Hz (아-vowel-ish F1), optional vibrato and an
    /// optional messa-di-voce amplitude arch.
    static func synthesizeVoice(
        seconds: Double, f0: Double = 220,
        vibratoRate: Double = 0, vibratoCents: Double = 0,
        archRangeDb: Double = 0
    ) -> [Float] {
        let n = Int(seconds * sampleRate)
        var out = [Float](repeating: 0, count: n)
        // Phase integration: vibrato is frequency modulation, so the phase
        // must accumulate (2π·∫f dt). Using 2π·f(t)·t instead tears the
        // waveform — YIN confidence collapses to 0 and nothing is voiced.
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let cents = vibratoRate > 0 ? vibratoCents * sin(2 * .pi * vibratoRate * t) : 0
            let instF0 = f0 * pow(2, cents / 1200)
            let amp = archRangeDb > 0
                ? pow(10, (-20 + archRangeDb * sin(.pi * t / seconds)) / 20)
                : 0.25
            var s = 0.0
            for h in 1...20 {
                let f = instF0 * Double(h)
                if f > 16_000 { break }
                let harmonicGain = 1.0 / Double(h)
                let formant = 1.0 + 3.0 * exp(-pow((f - 700) / 180, 2))
                s += harmonicGain * formant * sin(phase * Double(h) + Double(h))
            }
            phase += 2 * .pi * instF0 / sampleRate
            out[i] = Float(s * amp / 8)
        }
        return out
    }

    /// Slices the buffer exactly like the engine's render tap would.
    static func frames(of samples: [Float], frame: Int = 2048, hop: Int = 1024) -> [[Float]] {
        var out: [[Float]] = []
        var start = 0
        while start + frame <= samples.count {
            out.append(Array(samples[start..<start + frame]))
            start += hop
        }
        return out
    }

    func testBufferDecodePathAcceptsSynthesizedVoice() {
        // The buffer type the tap receives decodes our signal without loss.
        let samples = Self.synthesizeVoice(seconds: 0.2)
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        let roundTrip = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: samples.count))
        XCTAssertEqual(roundTrip.count, samples.count)
        let meanAmp = Double(roundTrip.reduce(0.0) { $0 + abs(Double($1)) }) / Double(samples.count)
        XCTAssertGreaterThan(meanAmp, 0.01, "signal carries energy")
        XCTAssertLessThan(meanAmp, 0.5, "signal is not clipped")
    }

    func testYINDetectsPitchFromBufferFrames() {
        let frames = Self.frames(of: Self.synthesizeVoice(seconds: 2.0))
        let detector = YINPitchDetector(sampleRate: Self.sampleRate)
        let estimates = frames.map { detector.detect(in: $0) }
        let voiced = estimates.filter(\.isVoiced)
        XCTAssertGreaterThanOrEqual(Double(voiced.count) / Double(estimates.count), 0.9,
                                     "voiced ratio over \(estimates.count) frames")
        let medianF = VocalLogic.median(voiced.map { $0.frequency })
        XCTAssertEqual(medianF, 220, accuracy: 3, "median pitch of the harmonic stack")
    }

    func testVibratoMeasuredEndToEnd() {
        // 5.5 Hz ±70¢ synthesis -> frames -> YIN -> autocorrelation analysis.
        let hop = 1024
        let frames = Self.frames(of: Self.synthesizeVoice(seconds: 4.0, vibratoRate: 5.5, vibratoCents: 70), hop: hop)
        let detector = YINPitchDetector(sampleRate: Self.sampleRate)
        let freqs = frames.map { detector.detect(in: $0) }.filter(\.isVoiced).map(\.frequency)
        let m = VocalLogic.VibratoAnalysis.analyze(frequencies: freqs, frameRate: Self.sampleRate / Double(hop))
        XCTAssertTrue(m.hasVibrato, "rate=\(m.rateHz) extent=\(m.extentCents) reg=\(m.regularity)")
        XCTAssertEqual(m.rateHz, 5.5, accuracy: 0.5)
        XCTAssertEqual(m.extentCents, 70, accuracy: 15)
    }

    func testDynamicsArchMeasuredThroughFrameRMS() {
        // 14 dB amplitude arch -> per-frame RMS (the tap's vDSP_rmsqv math)
        // -> messa di voce analysis.
        let frames = Self.frames(of: Self.synthesizeVoice(seconds: 4.0, archRangeDb: 14))
        let amplitudes: [Double] = frames.map { frame in
            let energy = frame.reduce(Float(0)) { $0 + $1 * $1 }
            return sqrt(Double(energy) / Double(frame.count))
        }
        let m = VocalLogic.DynamicsAnalysis.analyze(amplitudes: amplitudes)
        XCTAssertTrue(m.hasArch, "range=\(m.rangeDb) cres=\(m.crescendoDb) decres=\(m.decrescendoDb) peak=\(m.peakPosition)")
        XCTAssertEqual(m.rangeDb, 14, accuracy: 3)
        XCTAssertEqual(m.peakPosition, 0.5, accuracy: 0.15)
    }

    func testFormantPeakMeasuredThroughGoertzelSpectrum() {
        // The formant emphasis at 700 Hz must surface as the F1-band peak of
        // the same 512-bin Goertzel spectrum the vowel game consumes.
        let frame = Self.frames(of: Self.synthesizeVoice(seconds: 0.3))[5]
        let mags = VocalLogic.SpectralAnalysis.magnitudeSpectrum(frame, sampleRate: Self.sampleRate, binCount: 512)
        XCTAssertEqual(mags.count, 512)
        let f1 = VocalLogic.peakFrequency(magnitudes: mags, sampleRate: Self.sampleRate, band: 250...1000)
        XCTAssertNotNil(f1)
        XCTAssertEqual(f1!, 700, accuracy: 130, "F1 band peak (harmonics at 660/880 weighted by the 700Hz gaussian)")
    }

    func testSustainRunFromFrameTimes() {
        // Continuous voiced synthesis -> the sustain measurement sees one long run.
        let hop = 1024
        let frames = Self.frames(of: Self.synthesizeVoice(seconds: 3.0), hop: hop)
        let detector = YINPitchDetector(sampleRate: Self.sampleRate)
        let times: [Double] = frames.indices
            .filter { detector.detect(in: frames[$0]).isVoiced }
            .map { Double($0 * hop) / Self.sampleRate }
        let run = VocalLogic.SustainStats.longestRun(times: times)
        XCTAssertEqual(run, 3.0, accuracy: 0.15)
    }
}
#endif
