//
//  YINPitchDetector.swift
//  5VocalMaster
//
//  YIN fundamental-frequency (F0) estimator.
//  Pure value type: no shared state, safe to call from any thread.
//  The O(N*W) difference function is SIMD-accelerated with Accelerate (vDSP)
//  on Apple platforms; other toolchains (swift test on Windows) build the
//  mathematically identical scalar fallback.
//

#if canImport(Accelerate)
import Accelerate
#endif

/// Result of a single-frame pitch analysis.
public struct PitchEstimate: Equatable, Sendable {
    /// Estimated F0 in Hz. 0 when the frame is considered unvoiced.
    public var frequency: Double
    /// 1 - CMNDF minimum, clamped to 0...1. Higher means a more periodic signal.
    public var confidence: Double

    public var isVoiced: Bool { frequency > 0 && confidence >= 0.55 }

    public static let silent = PitchEstimate(frequency: 0, confidence: 0)
}

public struct YINPitchDetector: Sendable {
    public let sampleRate: Double
    public let minFrequency: Double
    public let maxFrequency: Double
    /// Absolute threshold for the CMNDF dip search (YIN paper default: 0.1...0.15).
    public let threshold: Float
    /// Fallback search rejects the frame when the global CMNDF minimum is above this.
    public let fallbackMaxCMNDF: Float

    public init(
        sampleRate: Double,
        minFrequency: Double = 65.0,    // C2
        maxFrequency: Double = 1050.0,  // ~C6
        threshold: Float = 0.15,
        fallbackMaxCMNDF: Float = 0.45
    ) {
        self.sampleRate = sampleRate
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        self.threshold = threshold
        self.fallbackMaxCMNDF = fallbackMaxCMNDF
    }

    /// Runs YIN over `samples`. Requires at least 2 * 256 samples.
    public func detect(in samples: [Float]) -> PitchEstimate {
        let window = samples.count / 2
        guard window >= 256, sampleRate > 0 else { return .silent }

        // tau range needed to cover [minFrequency, maxFrequency]
        let maxTau = min(Int(sampleRate / minFrequency), window - 2)
        let minTau = max(2, Int(sampleRate / maxFrequency))
        guard maxTau - minTau >= 3, samples.count >= window + maxTau + 1 else { return .silent }

        // Step 1: difference function  d[tau] = sum_{i<window} (x[i+tau] - x[i])^2
        // Sign of the subtraction is irrelevant (result is squared), so vDSP_vsub
        // argument order does not affect the outcome.
        var d = [Float](repeating: 0, count: maxTau + 2)
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for tau in 1...maxTau {
                var sumOfSquares: Float = 0
                #if canImport(Accelerate)
                var diff = [Float](repeating: 0, count: window)
                vDSP_vsub(base, 1, base + tau, 1, &diff, 1, vDSP_Length(window))
                vDSP_svesq(diff, 1, &sumOfSquares, vDSP_Length(window))
                #else
                // Scalar fallback: identical math, no Accelerate required.
                var accumulator: Float = 0
                for i in 0..<window {
                    let delta = samples[i + tau] - samples[i]
                    accumulator += delta * delta
                }
                sumOfSquares = accumulator
                #endif
                d[tau] = sumOfSquares
            }
        }

        // Step 2: cumulative mean normalized difference function (CMNDF)
        var cmndf = [Float](repeating: 1, count: maxTau + 2)
        var runningSum: Float = 0
        for tau in 1...maxTau {
            runningSum += d[tau]
            cmndf[tau] = runningSum > 0 ? d[tau] * Float(tau) / runningSum : 1
        }

        // Step 3: first dip below threshold, then descend to its local minimum
        var tauEstimate = 0
        var tau = minTau
        while tau < maxTau {
            if cmndf[tau] < threshold {
                while tau + 1 < maxTau && cmndf[tau + 1] < cmndf[tau] {
                    tau += 1
                }
                tauEstimate = tau
                break
            }
            tau += 1
        }

        // Fallback: global minimum in the search range, gated by a confidence floor
        if tauEstimate == 0 {
            var minValue: Float = .greatestFiniteMagnitude
            for t in minTau..<maxTau where cmndf[t] < minValue {
                minValue = cmndf[t]
                tauEstimate = t
            }
            guard minValue < fallbackMaxCMNDF else { return .silent }
        }

        guard tauEstimate >= 1, tauEstimate + 1 <= maxTau else { return .silent }

        // Step 4: parabolic refinement around the chosen dip
        let s0 = cmndf[tauEstimate - 1]
        let s1 = cmndf[tauEstimate]
        let s2 = cmndf[tauEstimate + 1]
        let denominator = 2 * (2 * s1 - s2 - s0)
        var shift: Float = 0
        if abs(denominator) > 1e-9 {
            shift = (s2 - s0) / denominator
        }

        let refinedTau = Double(tauEstimate) + Double(shift)
        guard refinedTau > 1 else { return .silent }

        let f0 = sampleRate / refinedTau
        guard f0 >= minFrequency * 0.95, f0 <= maxFrequency * 1.05 else { return .silent }

        let confidence = Swift.max(0, Swift.min(1, Double(1 - s1)))
        return PitchEstimate(frequency: f0, confidence: confidence)
    }
}
