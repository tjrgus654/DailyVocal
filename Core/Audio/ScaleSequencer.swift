//
//  ScaleSequencer.swift
//  DailyVocal
//
//  Guide-tone scale sequencer: plays 5-tone / octave / arpeggio / sustained
//  patterns through VocalAudioEngine's shared tone output, rising a semitone
//  per repetition. Stops itself after `repetitions` or `maxDuration`,
//  whichever comes first (routine steps use maxDuration to keep the guide
//  playing for the whole step).
//

import Foundation
import Observation

@MainActor
@Observable
public final class ScaleSequencer {

    public static let shared = ScaleSequencer()

    public private(set) var isPlaying = false
    public private(set) var currentNoteName = ""

    /// Semitone offset for key adjustment, clamped to ±12.
    public private(set) var transpose = 0

    private var playbackTask: Task<Void, Never>?
    /// Monotonic generation token: a cancelled (old) task can never flip
    /// `isPlaying` back to false after a newer `start()` already began.
    private var generation = 0
    private let audio = VocalAudioEngine.shared

    public enum Pattern: Sendable {
        case fiveTone      // 1-2-3-4-5-4-3-2-1
        case octaveJump    // 1-8-1
        case arpeggio      // 1-3-5-8-5-3-1
        case sustained     // single held tone

        var offsets: [Int] {
            switch self {
            case .fiveTone: return VocalLogic.guidePattern(for: .fiveToneScale)
            case .octaveJump: return VocalLogic.guidePattern(for: .octaveJump)
            case .arpeggio: return VocalLogic.guidePattern(for: .arpeggio)
            case .sustained: return VocalLogic.guidePattern(for: .sustainedNote)
            }
        }
    }

    private init() {}

    public static func pattern(for toneType: TonePatternType) -> Pattern {
        switch toneType {
        case .sirenSlide: return .arpeggio
        case .octaveJump: return .octaveJump
        case .fiveToneScale: return .fiveTone
        case .arpeggio: return .arpeggio
        case .sustainedNote: return .sustained
        }
    }

    // MARK: - Playback

    /// - Parameters:
    ///   - baseMidi: root note of the first repetition (48 = C3, 60 = C4).
    ///   - repetitions: how many semitone-rising repetitions to play.
    ///   - maxDuration: optional wall-clock cap in seconds.
    public func start(
        pattern: Pattern,
        baseMidi: Int,
        repetitions: Int = 5,
        beatsPerMinute: Double = 80,
        maxDuration: TimeInterval? = nil
    ) {
        stop()
        generation += 1

        let beat = 60.0 / beatsPerMinute.clamped(to: 40...200)
        let gate = beat * 0.85
        let deadline = maxDuration.map { Date().addingTimeInterval($0) }

        playbackTask = Task { [weak self] in
            guard let self else { return }
            let myGeneration = self.generation
            // Set inside the task body: by the time this runs, any cancelled
            // predecessor has already bailed out via its stale generation.
            self.isPlaying = true

            // Contract alignment with VocalLogic.guideToneSequence:
            // non-positive repetition counts play nothing.
            guard repetitions > 0 else {
                self.finish(generation: myGeneration)
                return
            }
            var repetition = 0
            while !Task.isCancelled {
                for offset in pattern.offsets {
                    if Task.isCancelled { break }
                    if let deadline, Date() >= deadline {
                        self.finish(generation: myGeneration)
                        return
                    }
                    // Transpose is read per note (not snapped per repetition): a mid-play key
                    // change takes effect on the next note — intended responsiveness.
                    let midi = VocalLogic.guideToneMidi(base: baseMidi + transpose, repetition: repetition, offset: offset)
                    self.currentNoteName = Self.noteName(forMidi: midi)
                    // .measurement mode lowers playback level a bit, so guide
                    // tones play slightly louder to compensate.
                    self.audio.playTone(
                        frequency: VocalAudioEngine.frequency(forMidi: Double(midi)),
                        duration: gate,
                        volume: 0.55
                    )
                    try? await Task.sleep(for: .seconds(beat))
                }
                repetition += 1
                if repetition >= repetitions { break }
                if let deadline, Date() >= deadline { break }
                // short breath between repetitions
                try? await Task.sleep(for: .seconds(beat / 2))
            }
            self.finish(generation: myGeneration)
        }
    }

    public func stop() {
        generation += 1
        playbackTask?.cancel()
        playbackTask = nil
        audio.stopAllTones()
        isPlaying = false
        currentNoteName = ""
    }

    public func setTranspose(_ semitones: Int) {
        transpose = semitones.clamped(to: -12...12)
    }

    private func finish(generation: Int) {
        guard generation == self.generation, !Task.isCancelled else { return }
        isPlaying = false
        currentNoteName = ""
        playbackTask = nil
    }

    nonisolated private static func noteName(forMidi midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let name = names[(midi % 12 + 12) % 12]
        return "\(name)\(midi / 12 - 1)"
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
