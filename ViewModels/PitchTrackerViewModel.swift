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

    public var targetNoteName = "E4" {
        didSet { syncTargetFrequency() }
    }
    public private(set) var targetMidi = 64
    /// Follows the current A4 calibration (no stored copy: a calibration
    /// change must not leave the guide tone on the old pitch).
    public var targetFrequency: Double {
        VocalAudioEngine.frequency(forMidi: Double(targetMidi))
    }

    /// Joined note names of the current echo sequence, e.g. "C4-E4-G4"
    /// (empty in single mode). Used by the completion alert and the stored
    /// record so both always agree.
    public var echoTargetLabel: String {
        mode == .echo ? VocalLogic.echoLabel(midis: echoTargetMidis) : ""
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
        mode == .echo && !echoTargetMidis.isEmpty
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
        noteBinCounts = Array(repeating: 0, count: 12)
        voicedFrequencies.removeAll()
        sessionStartDate = Date()
        isListening = true

        audio.onPitchUpdate = { [weak self] frequency, noteName, cents, voiced in
            self?.handlePitchUpdate(frequency: frequency, noteName: noteName, cents: cents, voiced: voiced)
        }
        audio.startMicrophone()

        if mode == .speak {
            echoPhaseTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, self.mode == .speak else { return }
                self.stopTracking()
            }
        } else if mode == .echo {
            startEchoFlow()
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
        // persisted record read this after the sequence is gone.
        lastSessionTargetLabel = echoTargetLabel.isEmpty ? targetNoteName : echoTargetLabel
        isListening = false
        echoPhaseTask?.cancel()
        echoPhaseTask = nil
        echoGeneration += 1
        // Clear the echo guides so a later single-note session does not
        // render ghost target lines from the previous sequence.
        echoTargetMidis = []
        activeEchoIndex = 0
        ignorePitchUntil = Date.distantPast
        audio.stopMicrophone()
        audio.onPitchUpdate = nil
        haptics.buttonTap()
        finishSession()
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
        haptics.routineCompleted()
    }

    /// Success-gated difficulty: promote at 80%+, demote after two
    /// consecutive sub-50% sessions, otherwise hold.
    private func updateEchoLevelIfNeeded(score: Int) {
        guard mode == .echo else { return }
        lastEchoLevelDelta = nil
        if score >= 80 {
            if echoLevel < 3 {
                echoLevel += 1
                lastEchoLevelDelta = 1
            }
            echoFailStreak = 0
        } else if score < 50 {
            echoFailStreak += 1
            if echoFailStreak >= 2 && echoLevel > 1 {
                echoLevel -= 1
                lastEchoLevelDelta = -1
                echoFailStreak = 0
            }
        } else {
            echoFailStreak = 0
        }
        UserDefaults.standard.set(echoLevel, forKey: "echoDifficultyLevel")
    }

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

        // Extend the stored vocal range when this session went beyond it.
        let descriptor = FetchDescriptor<UserProfile>()
        if let profile = (try? context.fetch(descriptor))?.first {
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
