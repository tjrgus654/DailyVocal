//
//  PitchTrackerViewModel.swift
//  DailyVocal
//
//  Real-time pitch measurement session: target selection, accuracy scoring,
//  haptic feedback (edge-triggered, throttled), trajectory history, and
//  persistence of a session summary that extends the user's vocal range.
//

import SwiftUI
import SwiftData
import AVFoundation

public struct PitchPoint: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: TimeInterval
    public let frequency: Double
    public let noteName: String
    public let cents: Double
    public let isOnPitch: Bool
    public let isVoiced: Bool
}

@MainActor
@Observable
public final class PitchTrackerViewModel {

    // MARK: - Session state

    public private(set) var isListening = false
    public private(set) var pitchHistory: [PitchPoint] = []
    public private(set) var accuracyScore = 0.0
    public private(set) var voicedFrameCount = 0
    public private(set) var sessionLowestFrequency = 0.0
    public private(set) var sessionHighestFrequency = 0.0
    /// Karaoke-style 0...100 score of the just-finished session (nil until finished).
    /// Target label of the just-finished session, captured BEFORE the echo
    /// guides are cleared ("E4-G4-C5" or the single target note).
    public private(set) var lastSessionTargetLabel = ""
    public private(set) var lastSessionScore: Int?
    public private(set) var lastSessionGrade: String = ""
    /// Pitch-class histogram of the current/last session (index 0=C ... 11=B,
    /// octaves folded). Mirrors the "mirror for your ear" pattern of pitch
    /// monitors: shows which notes the voice actually lives on.
    public private(set) var noteBinCounts = Array(repeating: 0, count: 12)
    /// All voiced frequencies this session — the median feeds the speech-pitch
    /// voice-type screen in speak mode.
    public private(set) var voicedFrequencies: [Double] = []
    /// Vowel game: the current round's target vowel and remaining rounds.
    public private(set) var vowelTarget: VocalLogic.TrainingVowel = .a
    public private(set) var vowelRoundIndex = 0
    public private(set) var vowelScores: [Int] = []
    public private(set) var lastVowelTips: [String] = []

    // MARK: - Sustain-check state (vibrato / dynamics share the phase shape)

    /// Shared phase machine for the guided sustained-note checks and the
    /// ear-training answer wait.
    public enum SustainPhase: Equatable {
        case idle
        /// Waiting for the guide tone to finish before the record window opens.
        case guide
        case recording
        /// Ear training: the two notes played, waiting for the answer buttons.
        case waitingAnswer
        case done
    }
    public private(set) var vibratoPhase: SustainPhase = .idle
    public private(set) var vibratoResult: VocalLogic.VibratoMeasurement?
    public private(set) var vibratoTips: [String] = []
    private var vibratoTrace: [(time: TimeInterval, frequency: Double)] = []
    /// Guide tone + tail, then the sustained-note record window.
    private static let vibratoGuideDuration = 1.6
    private static let vibratoRecordDuration = 5.5

    public private(set) var dynamicsPhase: SustainPhase = .idle
    public private(set) var dynamicsResult: VocalLogic.DynamicsMeasurement?
    public private(set) var dynamicsTips: [String] = []
    /// Per-frame smoothed RMS from the engine (messa di voce envelope).
    private var dynamicsAmps: [Double] = []
    private static let dynamicsGuideDuration = 1.6
    private static let dynamicsRecordDuration = 7.0

    /// Single-note mode: timestamps of voiced frames, feeding the maximum
    /// phonation time (longest continuous hold) measurement.
    private var singleVoicedTimes: [Double] = []
    /// Longest hold of the just-finished single-note session (seconds).
    public private(set) var lastSustainSeconds: Double = 0
    public private(set) var lastSustainTip: String?

    // MARK: - Interval game state

    public private(set) var intervalPhase: SustainPhase = .idle
    public private(set) var intervalTarget: VocalLogic.TrainingInterval = .unison
    public private(set) var intervalRoundIndex = 0
    public private(set) var intervalScores: [Int] = []
    public private(set) var lastIntervalFeedback: String?
    private var intervalBaseMidi = 60
    /// Fractional midis sung during the current record window.
    private var intervalMidis: [Double] = []
    private static let intervalDemoDuration = 0.9
    private static let intervalDemoGap = 0.35
    private static let intervalRecordDuration = 3.0

    // MARK: - Ear training state

    public private(set) var earPhase: SustainPhase = .idle
    public private(set) var earTrial: (baseMidi: Int, offset: Int)?
    public private(set) var earRoundIndex = 0
    public let earTotalRounds = 10
    public private(set) var earCorrect = 0
    public private(set) var earLevel = min(3, max(1, UserDefaults.standard.integer(forKey: "earTrainingLevel") == 0 ? 1 : UserDefaults.standard.integer(forKey: "earTrainingLevel")))
    private var earCorrectStreak = 0
    private var earWrongStreak = 0
    public private(set) var lastEarFeedback: String?
    private static let earNoteDuration = 0.8
    private static let earNoteGap = 0.5

    public var targetNoteName = "E4" {
        didSet { syncTargetFrequency() }
    }
    public private(set) var targetMidi = 64
    /// Follows the current A4 calibration (no stored copy: a calibration
    /// change must not leave the guide tone on the old pitch).
    public var targetFrequency: Double {
        VocalAudioEngine.frequency(forMidi: Double(targetMidi))
    }

    /// Joined note names of the current echo/scale/melody sequence, e.g.
    /// "C4-E4-G4" (empty in single mode). Used by the completion alert and
    /// the stored record so both always agree.
    public var echoTargetLabel: String {
        [.echo, .scale, .melody].contains(mode) && !echoTargetMidis.isEmpty
            ? VocalLogic.echoLabel(midis: echoTargetMidis)
            : ""
    }

    /// Listen-first ear training (SingTrue-style, strongest research backing):
    /// the target plays twice, the user sings with visuals HIDDEN, and the
    /// trajectory is revealed only when the session ends.
    public var isListenFirstMode = false

    /// Training mode. `echo` plays a random 3-note sequence in the comfortable
    /// range (Pfordresher & Greenspon 2024: wide-range imitation is the only
    /// pitch-matching drill with experimental support), then opens one
    /// sing-back window per note; scoring follows the active window's target.
    public enum TrackerMode: String, CaseIterable, Identifiable {
        case single = "단음 유지"
        case echo = "에코 3음"
        case speak = "말하기 10초"
        case vowel = "모음 게임"
        case vibrato = "비브라토 체크"
        case dynamics = "다이내믹스 아치"
        case scale = "스케일 따라부르기"
        case melody = "멜로디 따라부르기"
        case interval = "음정 게임"
        case ear = "귀훈련"
        public var id: String { rawValue }
    }
    public var mode: TrackerMode = .single {
        willSet {
            if newValue != mode && isListening { stopTracking() }
        }
    }

    /// MIDI numbers of the current echo sequence (empty in single mode).
    public private(set) var echoTargetMidis: [Int] = []
    /// Index of the echo window currently accepting frames.
    public private(set) var activeEchoIndex = 0
    private var echoPhaseTask: Task<Void, Never>?
    /// Restart guard: a stale phase task must never advance windows.
    private var echoGeneration = 0

    /// Adaptive echo difficulty 1...3 (Singing Carrots principle: raise only
    /// after success — 80%+ promotes, two consecutive sub-50% sessions
    /// demote). Wider interval sets at higher levels.
    public private(set) var echoLevel = min(3, max(1, UserDefaults.standard.integer(forKey: "echoDifficultyLevel")))
    private var echoFailStreak = 0
    /// Set when the level changed at the end of a session (+1/-1), for the
    /// completion alert.
    public private(set) var lastEchoLevelDelta: Int?

    /// Target the scoring/display should follow right now.
    public var activeTargetMidi: Int {
        [.echo, .scale, .melody].contains(mode) && !echoTargetMidis.isEmpty
            ? echoTargetMidis[min(activeEchoIndex, echoTargetMidis.count - 1)]
            : targetMidi
    }
    public var activeTargetFrequency: Double {
        VocalAudioEngine.frequency(forMidi: Double(activeTargetMidi))
    }
    public var activeTargetName: String {
        VocalAudioEngine.noteAndCents(fromFrequency: activeTargetFrequency).note
    }

    /// Pitch frames arriving before this date are the guide tone leaking back
    /// through the microphone, not the user's voice — they are ignored.
    private var ignorePitchUntil = Date.distantPast

    private var onPitchHitCount = 0
    private var totalCentsMagnitude = 0.0
    private var wasOnPitch = false
    private var lastHapticAt = Date.distantPast
    private var sessionStartDate = Date()

    // MARK: - Services

    let audio = VocalAudioEngine.shared
    private let haptics = HapticManager.shared
    private var modelContext: ModelContext?
    // deinit runs nonisolated; only mutated on the main actor and the object
    // is already unreferenced there when deinit reads it.
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?

    private static let historyLimit = 120
    private static let onPitchCentsTolerance = 25.0
    /// Echo flow timings (seconds): note duration in the listen phase, pause
    /// between the two plays, and the length of each sing-back window.
    private static let echoNoteDuration = 1.0
    private static let echoListenGap = 0.5
    private static let echoWindowDuration = 2.6
    /// Sequence-drill tempo (BPM): one beat splits into note (85%) + gap
    /// (15%); the sing window is 1.5 beats (VocalLogic.DrillTempo).
    public var sequenceBpm = VocalLogic.DrillTempo.clamped(
        UserDefaults.standard.object(forKey: "sequenceBpm") as? Int ?? VocalLogic.DrillTempo.defaultBpm
    ) {
        didSet { UserDefaults.standard.set(sequenceBpm, forKey: "sequenceBpm") }
    }

    public init() {
        syncTargetFrequency()
        // The engine callback is a single slot owned by the ACTIVE tracking
        // session (registered in startTracking, cleared in stopTracking).
        // Registering here would let throwaway view-models created during
        // tab switches steal the callback with a dead weak reference.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
            Task { @MainActor in
                // A phone call or Siri tears the audio graph down; end the
                // session cleanly instead of leaving a ghost "감지 중" state.
                self?.stopTracking()
            }
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    // The engine callback captures self weakly, so a destroyed view model is
    // simply never called again. Views clear the callback in onDisappear when
    // they own the tracking session (see clearEngineCallback()).

    public func clearEngineCallback() {
        if audio.onPitchUpdate != nil {
            audio.onPitchUpdate = nil
        }
    }

    public func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    // MARK: - Target

    private func syncTargetFrequency() {
        targetMidi = VocalAudioEngine.midiNumber(forNoteName: targetNoteName) ?? 64
    }

    public func setTargetNote(_ name: String) {
        guard VocalAudioEngine.midiNumber(forNoteName: name) != nil else { return }
        targetNoteName = name
        haptics.buttonTap()
    }

    /// Plays the target tone once. While it sounds (plus a short tail), the
    /// incoming pitch is ignored so the speaker->mic feedback is not scored.
    public func playTargetTone() {
        haptics.buttonTap()
        ignorePitchUntil = Date().addingTimeInterval(1.6)
        audio.playTone(frequency: targetFrequency, duration: 1.2, volume: 0.5)
    }

    // MARK: - Session control

    public func startTracking() {
        guard !isListening else { return }
        pitchHistory.removeAll()
        onPitchHitCount = 0
        voicedFrameCount = 0
        totalCentsMagnitude = 0
        accuracyScore = 0
        sessionLowestFrequency = 0
        sessionHighestFrequency = 0
        wasOnPitch = false
        lastSessionScore = nil
        lastSessionGrade = ""
        lastSessionTargetLabel = ""
        lastEchoLevelDelta = nil
        lastSustainSeconds = 0
        lastSustainTip = nil
        singleVoicedTimes = []
        echoHistory = []
        noteBinCounts = Array(repeating: 0, count: 12)
        voicedFrequencies.removeAll()
        sessionStartDate = Date()
        isListening = true

        audio.onPitchUpdate = { [weak self] frequency, noteName, cents, voiced in
            self?.handlePitchUpdate(frequency: frequency, noteName: noteName, cents: cents, voiced: voiced)
        }
        audio.startMicrophone()

        if mode == .vowel {
            startVowelGame()
        } else if mode == .vibrato {
            startVibratoCheck()
        } else if mode == .dynamics {
            startDynamicsCheck()
        } else if mode == .interval {
            startIntervalGame()
        } else if mode == .ear {
            startEarGame()
        } else if mode == .speak {
            echoPhaseTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, self.mode == .speak else { return }
                self.stopTracking()
            }
        } else if mode == .echo {
            startEchoFlow()
        } else if mode == .scale {
            startScaleFlow()
        } else if mode == .melody {
            startMelodyFlow()
        } else if isListenFirstMode {
            // Ear-training flow: hear the target twice first, then sing with
            // the visuals hidden (revealed on stop).
            playTargetTone()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                self.playTargetTone()
            }
        }
        haptics.buttonTap()
    }

    public func stopTracking() {
        guard isListening else { return }
        // Capture before the guides are cleared below — the alert and the
        // persisted record read this after the sequence is gone. Scale runs
        // store the game label (not the note ladder) so the growth
        // dashboard's recommendation can trace the score back to the game.
        lastSessionTargetLabel = mode == .scale
            ? VocalLogic.gameLabel(for: .scale)
            : (mode == .melody
               ? VocalLogic.gameLabel(for: .melody)
               : (echoTargetLabel.isEmpty ? targetNoteName : echoTargetLabel))
        isListening = false
        echoPhaseTask?.cancel()
        echoPhaseTask = nil
        echoGeneration += 1
        // Clear the echo guides so a later single-note session does not
        // render ghost target lines from the previous sequence.
        echoTargetMidis = []
        activeEchoIndex = 0
        if mode == .vibrato {
            vibratoPhase = .idle
            vibratoTrace = []
        }
        if mode == .dynamics {
            dynamicsPhase = .idle
            dynamicsAmps = []
        }
        if mode == .interval {
            intervalPhase = .idle
            intervalMidis = []
        }
        if mode == .ear {
            earPhase = .idle
            earTrial = nil
        }
        ignorePitchUntil = Date.distantPast
        audio.isSpectrumWanted = false
        LiveActivityManager.shared.endLiveActivity()
        audio.stopMicrophone()
        audio.onPitchUpdate = nil
        haptics.buttonTap()
        finishSession()
        persistSessionSummary()
    }

    // MARK: - Vowel game flow

    private func startVowelGame() {
        audio.isSpectrumWanted = true
        echoGeneration += 1
        LiveActivityManager.shared.startGameActivity(
            gameMode: "모음 게임",
            totalRounds: VocalLogic.vowelGameRounds(level: echoLevel).count
        )
        let generation = echoGeneration
        vowelRoundIndex = 0
        vowelScores = []
        let rounds = VocalLogic.vowelGameRounds(level: echoLevel)
        playVowelRound(rounds: rounds, generation: generation)
    }

    private func playVowelRound(rounds: [VocalLogic.TrainingVowel], generation: Int) {
        guard vowelRoundIndex < rounds.count else {
            finishVowelGame()
            return
        }
        vowelTarget = rounds[vowelRoundIndex]
        LiveActivityManager.shared.updateGameRound(vowelRoundIndex + 1, of: rounds.count)
        ignorePitchUntil = .distantFuture
        echoPhaseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // 1) Demo: synthesize the target vowel (formant filtering).
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            let f0 = VocalLogic.frequency(forMidi: Double(self.targetMidi))
            let (f1, f2, f3) = VocalLogic.formants(for: self.vowelTarget)
            self.audio.playVowelTone(f0: f0, f1: f1, f2: f2, f3: f3, duration: 1.2)
            try? await Task.sleep(for: .seconds(1.4))
            // 2) Record: open the gate for 3 seconds of user mimicry.
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.vowelMagnitudes = []
            self.ignorePitchUntil = Date()
            try? await Task.sleep(for: .seconds(3.0))
            // 3) Score and advance.
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.scoreVowelRound()
            self.vowelRoundIndex += 1
            self.playVowelRound(rounds: rounds, generation: generation)
        }
    }

    /// Accumulated magnitude spectra for the current vowel round (filled by
    /// the engine callback in vowel mode).
    private var vowelMagnitudes: [[Double]] = []

    private func scoreVowelRound() {
        defer { vowelMagnitudes = [] }
        guard !vowelMagnitudes.isEmpty else {
            vowelScores.append(0)
            lastVowelTips = ["소리가 너무 작았어요 — 다음 라운드에서 더 또렷하게 발성해주세요"]
            return
        }
        // Average the magnitude frames, then score against the target formants.
        let binCount = vowelMagnitudes[0].count
        var avg = [Double](repeating: 0, count: binCount)
        for frame in vowelMagnitudes {
            for i in 0..<binCount { avg[i] += frame[i] }
        }
        for i in 0..<binCount { avg[i] /= Double(vowelMagnitudes.count) }
        let strength = VocalLogic.formantStrength(
            magnitudes: avg, sampleRate: audio.analysisSampleRate, vowel: vowelTarget)
        vowelScores.append(VocalLogic.vowelRoundScore(strength: strength))
        if let mf = VocalLogic.measuredFormants(magnitudes: avg, sampleRate: audio.analysisSampleRate) {
            lastVowelTips = VocalLogic.vowelDirectionFeedback(target: vowelTarget, userF1: mf.f1, userF2: mf.f2)
        }
        if lastVowelTips.isEmpty {
            lastVowelTips = ["포먼트가 목표와 잘 맞습니다"]
        }
    }

    private func finishVowelGame() {
        guard !vowelScores.isEmpty else { return }
        accuracyScore = Double(vowelScores.reduce(0, +)) / Double(vowelScores.count)
        lastSessionScore = Int(accuracyScore.rounded())
        lastSessionGrade = VocalLogic.sessionGrade(forScore: lastSessionScore ?? 0)
        lastSessionTargetLabel = "모음 게임"
        haptics.routineCompleted()
        // End the session properly: stop the mic and persist the vowel-game
        // result instead of leaving the mic on for stopTracking() to
        // overwrite the score with a single-note accuracy ratio.
        isListening = false
        audio.isSpectrumWanted = false
        LiveActivityManager.shared.endLiveActivity()
        audio.stopMicrophone()
        audio.onPitchUpdate = nil
        persistSessionSummary()
    }

    // MARK: - Vibrato check flow

    /// Guide tone once, then a 5.5 s sustained-note window, then autocorrelation
    /// analysis of the pitch trace (rate / extent / regularity) with coaching.
    private func startVibratoCheck() {
        echoGeneration += 1
        let generation = echoGeneration
        vibratoPhase = .guide
        vibratoResult = nil
        vibratoTips = []
        vibratoTrace = []
        // Hold scoring off while the guide tone sounds through the speaker.
        ignorePitchUntil = .distantFuture
        LiveActivityManager.shared.startGameActivity(gameMode: "비브라토", totalRounds: 1)
        LiveActivityManager.shared.updateGameRound(1, of: 1)

        echoPhaseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.playTargetTone()
            try? await Task.sleep(for: .seconds(Self.vibratoGuideDuration))
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.vibratoPhase = .recording
            self.ignorePitchUntil = Date()
            try? await Task.sleep(for: .seconds(Self.vibratoRecordDuration))
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.finishVibratoCheck()
        }
    }

    private func finishVibratoCheck() {
        vibratoPhase = .done
        lastSessionTargetLabel = "비브라토 체크"
        let times = vibratoTrace.map { $0.time }
        let freqs = vibratoTrace.map { $0.frequency }
        let result = VocalLogic.VibratoAnalysis.analyze(times: times, frequencies: freqs)
        vibratoResult = result
        vibratoTips = VocalLogic.vibratoFeedback(for: result)
        let score = VocalLogic.vibratoScore(result)
        accuracyScore = Double(score)
        lastSessionScore = voicedFrameCount >= 10 ? score : nil
        lastSessionGrade = VocalLogic.sessionGrade(forScore: score)
        haptics.routineCompleted()
        // Same ownership pattern as the vowel game: end the session here so
        // a later stopTracking() cannot overwrite the vibrato score.
        isListening = false
        LiveActivityManager.shared.endLiveActivity()
        audio.stopMicrophone()
        audio.onPitchUpdate = nil
        persistSessionSummary()
    }

    /// Messa di voce flow: guide tone once, then a 7 s window to swell the
    /// note soft→loud→soft on one breath; the RMS envelope is scored.
    private func startDynamicsCheck() {
        echoGeneration += 1
        let generation = echoGeneration
        dynamicsPhase = .guide
        dynamicsResult = nil
        dynamicsTips = []
        dynamicsAmps = []
        ignorePitchUntil = .distantFuture
        LiveActivityManager.shared.startGameActivity(gameMode: "다이내믹스", totalRounds: 1)
        LiveActivityManager.shared.updateGameRound(1, of: 1)

        echoPhaseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.playTargetTone()
            try? await Task.sleep(for: .seconds(Self.dynamicsGuideDuration))
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.dynamicsPhase = .recording
            self.ignorePitchUntil = Date()
            try? await Task.sleep(for: .seconds(Self.dynamicsRecordDuration))
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.finishDynamicsCheck()
        }
    }

    private func finishDynamicsCheck() {
        dynamicsPhase = .done
        lastSessionTargetLabel = "다이내믹스 아치"
        let result = VocalLogic.DynamicsAnalysis.analyze(amplitudes: dynamicsAmps)
        dynamicsResult = result
        dynamicsTips = VocalLogic.dynamicsFeedback(for: result)
        let score = VocalLogic.dynamicsScore(result)
        accuracyScore = Double(score)
        lastSessionScore = voicedFrameCount >= 10 ? score : nil
        lastSessionGrade = VocalLogic.sessionGrade(forScore: score)
        haptics.routineCompleted()
        // Same ownership pattern as the vowel/vibrato finishes: end here so a
        // later stopTracking() cannot overwrite the dynamics score.
        isListening = false
        LiveActivityManager.shared.endLiveActivity()
        audio.stopMicrophone()
        audio.onPitchUpdate = nil
        persistSessionSummary()
    }

    // MARK: - Interval game flow

    /// Per round: base note + target note sound, then a 3 s window to sing
    /// the SECOND note; the median sung midi becomes the performed interval.
    private func startIntervalGame() {
        echoGeneration += 1
        let generation = echoGeneration
        intervalPhase = .guide
        intervalRoundIndex = 0
        intervalScores = []
        lastIntervalFeedback = nil
        let rounds = VocalLogic.intervalRounds(level: echoLevel) { Int.random(in: 0..<1_000_000) }
        LiveActivityManager.shared.startGameActivity(gameMode: "음정 게임", totalRounds: rounds.count)
        playIntervalRound(rounds: rounds, generation: generation)
    }

    private func playIntervalRound(rounds: [VocalLogic.TrainingInterval], generation: Int) {
        guard intervalRoundIndex < rounds.count else {
            finishIntervalGame()
            return
        }
        intervalTarget = rounds[intervalRoundIndex]
        LiveActivityManager.shared.updateGameRound(intervalRoundIndex + 1, of: rounds.count)
        intervalPhase = .guide
        ignorePitchUntil = .distantFuture
        echoPhaseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.intervalBaseMidi = self.targetMidi
            // 1) Demo: the base, a short gap, then the target note above it.
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.audio.playTone(
                frequency: VocalAudioEngine.frequency(forMidi: Double(self.intervalBaseMidi)),
                duration: Self.intervalDemoDuration, volume: 0.5)
            try? await Task.sleep(for: .seconds(Self.intervalDemoDuration + Self.intervalDemoGap))
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.audio.playTone(
                frequency: VocalAudioEngine.frequency(forMidi: Double(self.intervalBaseMidi + self.intervalTarget.semitones)),
                duration: Self.intervalDemoDuration, volume: 0.5)
            try? await Task.sleep(for: .seconds(Self.intervalDemoDuration + 0.3))
            // 2) Record: 3 s to sing the target note alone.
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.intervalMidis = []
            self.intervalPhase = .recording
            self.ignorePitchUntil = Date()
            try? await Task.sleep(for: .seconds(Self.intervalRecordDuration))
            // 3) Score and advance.
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.scoreIntervalRound()
            self.intervalRoundIndex += 1
            self.playIntervalRound(rounds: rounds, generation: generation)
        }
    }

    private func scoreIntervalRound() {
        defer { intervalMidis = [] }
        guard let performed = VocalLogic.performedSemitones(midiEstimates: intervalMidis, baseMidi: intervalBaseMidi) else {
            intervalScores.append(0)
            lastIntervalFeedback = "소리가 잡히지 않았어요 — 다음 라운드에서 두 번째 음을 또렷하게 불러주세요"
            return
        }
        intervalScores.append(VocalLogic.intervalScore(target: intervalTarget, userSemitones: performed))
        lastIntervalFeedback = VocalLogic.intervalFeedback(target: intervalTarget, userSemitones: performed)
    }

    private func finishIntervalGame() {
        guard !intervalScores.isEmpty else { return }
        accuracyScore = Double(intervalScores.reduce(0, +)) / Double(intervalScores.count)
        lastSessionScore = Int(accuracyScore.rounded())
        lastSessionGrade = VocalLogic.sessionGrade(forScore: lastSessionScore ?? 0)
        lastSessionTargetLabel = VocalLogic.gameLabel(for: .interval)
        haptics.routineCompleted()
        isListening = false
        LiveActivityManager.shared.endLiveActivity()
        audio.stopMicrophone()
        audio.onPitchUpdate = nil
        persistSessionSummary()
    }

    // MARK: - Ear training flow

    /// Pure listening game: two notes play, the user answers higher/same/
    /// lower. Streak-based level progression, 10 trials per session.
    private func startEarGame() {
        echoGeneration += 1
        let generation = echoGeneration
        earPhase = .guide
        earRoundIndex = 0
        earCorrect = 0
        earTrial = nil
        lastEarFeedback = nil
        LiveActivityManager.shared.startGameActivity(gameMode: "귀훈련", totalRounds: earTotalRounds)
        playEarTrial(generation: generation)
    }

    private func playEarTrial(generation: Int) {
        guard earRoundIndex < earTotalRounds else {
            finishEarGame()
            return
        }
        let trial = VocalLogic.earTrainingTrial(level: earLevel) { Int.random(in: 0..<1_000_000) }
        earTrial = trial
        earPhase = .guide
        LiveActivityManager.shared.updateGameRound(earRoundIndex + 1, of: earTotalRounds)
        echoPhaseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.audio.playTone(
                frequency: VocalAudioEngine.frequency(forMidi: Double(trial.baseMidi)),
                duration: Self.earNoteDuration, volume: 0.5)
            try? await Task.sleep(for: .seconds(Self.earNoteDuration + Self.earNoteGap))
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.audio.playTone(
                frequency: VocalAudioEngine.frequency(forMidi: Double(trial.baseMidi + trial.offset)),
                duration: Self.earNoteDuration, volume: 0.5)
            try? await Task.sleep(for: .seconds(Self.earNoteDuration + 0.2))
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.earPhase = .waitingAnswer
        }
    }

    /// Answer button handler (higher / same / lower).
    public func answerEar(_ answer: VocalLogic.PitchComparison) {
        guard mode == .ear, earPhase == .waitingAnswer, let trial = earTrial else { return }
        haptics.buttonTap()
        let correct = VocalLogic.earTrainingAnswer(offset: trial.offset) == answer
        if correct {
            earCorrect += 1
            earCorrectStreak += 1
            earWrongStreak = 0
            lastEarFeedback = "정답! \(earCorrect)/\(earRoundIndex + 1)"
        } else {
            earWrongStreak += 1
            earCorrectStreak = 0
            lastEarFeedback = "아쉬워요 — 정답은 \(VocalLogic.earTrainingAnswer(offset: trial.offset).rawValue)"
        }
        let newLevel = VocalLogic.earTrainingLevel(
            currentLevel: earLevel, correctStreak: earCorrectStreak, wrongStreak: earWrongStreak)
        if newLevel != earLevel {
            earLevel = newLevel
            UserDefaults.standard.set(earLevel, forKey: "earTrainingLevel")
        }
        earPhase = .guide
        earTrial = nil
        earRoundIndex += 1
        // Brief pause so the feedback is readable, then the next trial.
        echoPhaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.1))
            guard let self, !Task.isCancelled else { return }
            self.playEarTrial(generation: self.echoGeneration)
        }
    }

    private func finishEarGame() {
        accuracyScore = Double(earCorrect) / Double(earTotalRounds) * 100.0
        lastSessionScore = Int(accuracyScore.rounded())
        lastSessionGrade = VocalLogic.sessionGrade(forScore: lastSessionScore ?? 0)
        lastSessionTargetLabel = VocalLogic.gameLabel(for: .ear)
        haptics.routineCompleted()
        earPhase = .done
        isListening = false
        LiveActivityManager.shared.endLiveActivity()
        audio.stopMicrophone()
        audio.onPitchUpdate = nil
        persistSessionSummary()
    }

    // MARK: - Echo sequence flow

    private func generateEchoSequence() -> [Int] {
        VocalLogic.generateEchoSequence(base: targetMidi, level: echoLevel) {
            Int.random(in: 0..<1_000_000)
        }
    }

    private func startEchoFlow() {
        echoGeneration += 1
        let generation = echoGeneration
        echoTargetMidis = generateEchoSequence()
        activeEchoIndex = 0
        // Hold scoring off while the guide sequence sounds through the
        // speaker; the listen phase below decides when frames count again.
        ignorePitchUntil = .distantFuture

        echoPhaseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Listen: the sequence plays twice.
            for _ in 0..<2 {
                for midi in self.echoTargetMidis {
                    guard !Task.isCancelled, generation == self.echoGeneration else { return }
                    self.audio.playTone(
                        frequency: VocalAudioEngine.frequency(forMidi: Double(midi)),
                        duration: Self.echoNoteDuration,
                        volume: 0.5
                    )
                    try? await Task.sleep(for: .seconds(Self.echoNoteDuration + Self.echoListenGap))
                }
                try? await Task.sleep(for: .seconds(0.3))
            }
            // Sing: one window per note; scoring follows the active window.
            // The generation check must also cover the ignore-gate release:
            // a stale task waking here must not re-open scoring on a fresh
            // session that is still in its listen phase.
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.ignorePitchUntil = Date()
            for index in self.echoTargetMidis.indices {
                guard !Task.isCancelled, generation == self.echoGeneration else { return }
                self.activeEchoIndex = index
                try? await Task.sleep(for: .seconds(Self.echoWindowDuration))
            }
            guard generation == self.echoGeneration else { return }
            self.stopTracking()
        }
    }

    /// Scale sing-through: the engine plays the pattern ladder once (own
    /// synthesis — no copyrighted backing), then one window per note with
    /// scoring following the active target, same as echo.
    private func startScaleFlow() {
        let pattern = VocalLogic.scalePattern(level: echoLevel)
        startSequenceDrill(
            midis: VocalLogic.scaleSequence(baseMidi: targetMidi, pattern: pattern),
            gameMode: pattern.rawValue
        )
    }

    /// Melody call-and-response ("sing it back"): a contour phrase sounds
    /// once, then one window per note. Shares the sequence-drill machinery
    /// and the echo level ladder with the scale drill.
    private func startMelodyFlow() {
        let contour = VocalLogic.melodyContour(level: echoLevel) { Int.random(in: 0..<1_000_000) }
        let length = VocalLogic.melodyLength(level: echoLevel)
        melodyDrillLabel = "멜로디 \(contour.rawValue) \(length)음"
        startSequenceDrill(
            midis: VocalLogic.melodyPhrase(
                contour: contour, baseMidi: targetMidi,
                roll: { Int.random(in: 0..<1_000_000) },
                noteCount: length
            ),
            gameMode: melodyDrillLabel
        )
    }

    /// Label of the current melody drill (shown in the caption, persisted as
    /// the session target).
    public private(set) var melodyDrillLabel = ""

    /// Shared one-demo-then-per-note-window flow for the sequence drills
    /// (scale ladder, melody call-and-response). Timings follow the drill BPM.
    private func startSequenceDrill(midis: [Int], gameMode: String) {
        echoGeneration += 1
        let generation = echoGeneration
        let tempo = VocalLogic.DrillTempo.timings(bpm: sequenceBpm)
        echoTargetMidis = midis
        activeEchoIndex = 0
        ignorePitchUntil = .distantFuture
        LiveActivityManager.shared.startGameActivity(
            gameMode: gameMode,
            totalRounds: echoTargetMidis.count
        )

        echoPhaseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Demo once — the phrases are predictable, one pass is enough.
            for midi in self.echoTargetMidis {
                guard !Task.isCancelled, generation == self.echoGeneration else { return }
                self.audio.playTone(
                    frequency: VocalAudioEngine.frequency(forMidi: Double(midi)),
                    duration: tempo.note,
                    volume: 0.5
                )
                try? await Task.sleep(for: .seconds(tempo.note + tempo.gap))
            }
            try? await Task.sleep(for: .seconds(0.3))
            // Sing: one window per note of the phrase.
            guard !Task.isCancelled, generation == self.echoGeneration else { return }
            self.ignorePitchUntil = Date()
            for index in self.echoTargetMidis.indices {
                guard !Task.isCancelled, generation == self.echoGeneration else { return }
                self.activeEchoIndex = index
                LiveActivityManager.shared.updateGameRound(index + 1, of: self.echoTargetMidis.count)
                try? await Task.sleep(for: .seconds(tempo.window))
            }
            guard generation == self.echoGeneration else { return }
            self.stopTracking()
        }
    }

    /// Karaoke-style scoring familiar to Korean users: on-pitch ratio over
    /// voiced frames, expressed as 0...100 with an S/A/B/C/D grade.
    private func finishSession() {
        guard voicedFrameCount >= 10 else {
            lastSessionScore = nil
            lastSessionGrade = ""
            return
        }
        lastSessionScore = Int(accuracyScore.rounded())
        lastSessionGrade = VocalLogic.sessionGrade(forScore: lastSessionScore ?? 0)
        updateEchoLevelIfNeeded(score: lastSessionScore ?? 0)
        if mode == .single {
            // Maximum phonation time: the breathing-support readout.
            let profiles = (try? modelContext?.fetch(FetchDescriptor<UserProfile>())) ?? nil
            lastSustainSeconds = VocalLogic.SustainStats.longestRun(times: singleVoicedTimes)
            lastSustainTip = VocalLogic.SustainStats.feedback(
                seconds: lastSustainSeconds,
                isFemale: profiles?.first?.prefersHigherKeyGuide == true ? true : nil
            )
        }
        haptics.routineCompleted()
    }

    /// Personalized difficulty: session history drives level transitions
    /// through VocalLogic.recommendedLevel (same rule the contract tests
    /// and the web prototype use), replacing the ad-hoc fail-streak.
    /// Applies to the sequence drills: echo, scale, melody, and interval games.
    private func updateEchoLevelIfNeeded(score: Int) {
        guard [.echo, .scale, .melody, .interval].contains(mode) else { return }
        lastEchoLevelDelta = nil
        echoHistory.append(score)
        let newLevel = VocalLogic.recommendedLevel(
            recentAccuracies: echoHistory, currentLevel: echoLevel
        )
        if newLevel != echoLevel {
            lastEchoLevelDelta = newLevel - echoLevel
            echoLevel = newLevel
        }
        UserDefaults.standard.set(echoLevel, forKey: "echoDifficultyLevel")
    }
    private var echoHistory: [Int] = []

    public func dismissScoreAlert() {
        lastSessionScore = nil
        lastSessionGrade = ""
    }

    // MARK: - Frame handling (called from the engine on the main actor)

    private func handlePitchUpdate(frequency: Double, noteName: String, cents: Double, voiced: Bool) {
        guard isListening else { return }
        guard Date() >= ignorePitchUntil else { return }

        guard voiced else {
            if let last = pitchHistory.last, last.isVoiced {
                // keep a gap marker so the canvas breaks the line
                pitchHistory.append(
                    PitchPoint(timestamp: Date().timeIntervalSince1970,
                               frequency: 0, noteName: "--", cents: 0,
                               isOnPitch: false, isVoiced: false)
                )
            }
            wasOnPitch = false
            return
        }

        voicedFrameCount += 1
        voicedFrequencies.append(frequency)
        if mode == .vibrato {
            vibratoTrace.append((Date().timeIntervalSince1970, frequency))
        }
        if mode == .dynamics {
            // Engine updates the smoothed RMS before this callback fires.
            dynamicsAmps.append(audio.amplitude)
        }
        if mode == .single {
            singleVoicedTimes.append(Date().timeIntervalSince1970)
        }
        if mode == .interval, intervalPhase == .recording {
            intervalMidis.append(VocalAudioEngine.midiNumber(forFrequency: frequency))
        }
        if mode == .vowel {
            vowelMagnitudes.append(audio.currentMagnitudeSpectrum)
        }
        totalCentsMagnitude += abs(cents)

        if sessionLowestFrequency == 0 || frequency < sessionLowestFrequency {
            sessionLowestFrequency = frequency
        }
        if frequency > sessionHighestFrequency {
            sessionHighestFrequency = frequency
        }

        let currentMidi = VocalAudioEngine.noteAndCents(fromFrequency: frequency).midi
        noteBinCounts[(currentMidi % 12 + 12) % 12] += 1
        let isOnPitch = currentMidi == activeTargetMidi
            && abs(cents) <= Self.onPitchCentsTolerance
        if isOnPitch {
            onPitchHitCount += 1
        }
        accuracyScore = voicedFrameCount > 0
            ? Double(onPitchHitCount) / Double(voicedFrameCount) * 100.0
            : 0

        fireOnPitchHapticIfNeeded(isOnPitch: isOnPitch)

        pitchHistory.append(
            PitchPoint(timestamp: Date().timeIntervalSince1970,
                       frequency: frequency, noteName: noteName, cents: cents,
                       isOnPitch: isOnPitch, isVoiced: true)
        )
        if pitchHistory.count > Self.historyLimit {
            pitchHistory.removeFirst(pitchHistory.count - Self.historyLimit)
        }
    }

    private func fireOnPitchHapticIfNeeded(isOnPitch: Bool) {
        defer { wasOnPitch = isOnPitch }
        guard isOnPitch, !wasOnPitch else { return }
        guard Date().timeIntervalSince(lastHapticAt) >= 0.5 else { return }
        lastHapticAt = Date()
        haptics.onPitchHit()
    }

    // MARK: - Persistence

    private func persistSessionSummary() {
        guard let context = modelContext, voicedFrameCount >= 10 else { return }

        let low = VocalAudioEngine.noteAndCents(fromFrequency: sessionLowestFrequency)
        let high = VocalAudioEngine.noteAndCents(fromFrequency: sessionHighestFrequency)

        let record = PitchRecord(
            durationSeconds: max(1, Int(Date().timeIntervalSince(sessionStartDate))),
            targetNoteName: lastSessionTargetLabel.isEmpty ? targetNoteName : lastSessionTargetLabel,
            targetFrequency: targetFrequency,
            averageCentsDeviation: totalCentsMagnitude / Double(voicedFrameCount),
            accuracyPercentage: accuracyScore,
            voicedFrameCount: voicedFrameCount,
            lowestNoteName: low.note,
            lowestFrequency: sessionLowestFrequency,
            highestNoteName: high.note,
            highestFrequency: sessionHighestFrequency
        )
        context.insert(record)

        // Speak mode: persist the habitual speech pitch median.
        if mode == .speak, voicedFrequencies.count >= 30 {
            let descriptor = FetchDescriptor<UserProfile>()
            if let profile = (try? context.fetch(descriptor))?.first {
                profile.speechMedianFrequency = VocalLogic.median(voicedFrequencies)
            }
        }

        // Sustain checks: keep the last measured technique fingerprints so
        // the growth dashboard can show them (0 = not yet measured).
        if mode == .vibrato,
           let result = vibratoResult,
           result.voicedFrames >= VocalLogic.VibratoAnalysis.minFrames {
            let descriptor = FetchDescriptor<UserProfile>()
            if let profile = (try? context.fetch(descriptor))?.first {
                profile.lastVibratoRateHz = result.rateHz
                profile.lastVibratoExtentCents = result.extentCents
            }
        }
        if mode == .dynamics,
           let result = dynamicsResult,
           result.voicedFrames >= VocalLogic.DynamicsAnalysis.minFrames {
            let descriptor = FetchDescriptor<UserProfile>()
            if let profile = (try? context.fetch(descriptor))?.first {
                profile.lastDynamicsRangeDb = result.rangeDb
            }
        }

        // Extend the stored vocal range when this session went beyond it.
        let descriptor = FetchDescriptor<UserProfile>()
        if let profile = (try? context.fetch(descriptor))?.first {
            if mode == .single, lastSustainSeconds > profile.bestSustainSeconds {
                profile.bestSustainSeconds = lastSustainSeconds
            }
            if profile.lowestFrequency == 0 || sessionLowestFrequency < profile.lowestFrequency {
                profile.lowestFrequency = sessionLowestFrequency
                profile.lowestNoteName = low.note
            }
            if sessionHighestFrequency > profile.highestFrequency {
                profile.highestFrequency = sessionHighestFrequency
                profile.highestNoteName = high.note
            }
        }
        try? context.save()
    }
}
