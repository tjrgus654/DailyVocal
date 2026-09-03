//
//  VocalAudioEngine.swift
//  5VocalMaster
//
//  Single shared AVAudioEngine owning both the microphone analysis tap and the
//  guide-tone player. One engine + one audio session prevents the two-node
//  (input tap + output synth) session conflicts of the previous architecture.
//
//  Concurrency model:
//   - All mutable state is MainActor-isolated (@Observable).
//   - The render-thread tap callback only computes RMS and copies the frame
//     (deep copy — the CoreAudio buffer is reused after the callback returns).
//   - YIN analysis runs on a private serial queue with latest-wins frame
//     dropping, results are published back on the main actor.
//

import AVFoundation
import Accelerate
import Observation

/// Thread-safe latest-wins gate: bounds the number of frames in flight so a
/// slow analysis never builds up a queue (oldest frames are simply dropped).
private final class FrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    func tryEnter() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard count < limit else { return false }
        count += 1
        return true
    }

    func leave() {
        lock.lock()
        defer { lock.unlock() }
        count = max(0, count - 1)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        count = 0
    }
}

@MainActor
@Observable
public final class VocalAudioEngine {

    public static let shared = VocalAudioEngine()

    // MARK: - Observable UI state

    public private(set) var isMicrophoneRunning = false
    public private(set) var currentFrequency: Double = 0
    public private(set) var currentNoteName = "--"
    public private(set) var centsDeviation: Double = 0
    /// Exponentially smoothed RMS, roughly 0...0.3 for normal speech/singing.
    public private(set) var amplitude: Double = 0
    public private(set) var isVoiceDetected = false
    public private(set) var hasMicPermission = false
    /// True only after the user explicitly denied the microphone
    /// (undetermined is false — the request flow hasn't run yet).
    public private(set) var isMicPermissionDenied = false
    public private(set) var errorMessage: String?

    /// MainActor callback invoked on every analyzed frame while the microphone
    /// runs. Parameters: (frequency, noteName, cents, voiced); `voiced` is false
    /// for silent/unvoiced frames (frequency is 0 then).
    public var onPitchUpdate: ((Double, String, Double, Bool) -> Void)?

    // MARK: - Audio graph

    private let engine = AVAudioEngine()
    private let toneNode = AVAudioPlayerNode()
    private var isToneNodeAttached = false
    private var activeToneCount = 0
    private var engineStopWorkItem: DispatchWorkItem?

    private let processingQueue = DispatchQueue(label: "com.vocalmaster.pitch.yin", qos: .userInteractive)
    private let frameGate = FrameGate(limit: 2)
    private let silenceRMSGate: Double = 0.02
    private var previousFrequency1: Double = 0
    private var previousFrequency2: Double = 0
    /// Last accepted voiced frequency, used to reject sudden octave jumps.
    private var lastVoicedFrequency: Double = 0

    // deinit runs nonisolated; only mutated on the main actor and the
    // singleton outlives every reference when deinit reads them.
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // MARK: - Init

    private init() {
        checkMicrophonePermission()
        installAudioSessionObservers()
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeChangeObserver { NotificationCenter.default.removeObserver(routeChangeObserver) }
    }

    // MARK: - Permission

    public func checkMicrophonePermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            hasMicPermission = true
            isMicPermissionDenied = false
        case .denied:
            hasMicPermission = false
            isMicPermissionDenied = true
            errorMessage = "마이크 권한이 거부되었습니다. 설정 > 개인정보 보호에서 허용해주세요."
        case .undetermined:
            hasMicPermission = false
            isMicPermissionDenied = false
        @unknown default:
            hasMicPermission = false
            isMicPermissionDenied = true
        }
    }

    /// Requests permission when undetermined, then runs `action` if granted.
    public func requestMicrophonePermission(then action: (() -> Void)? = nil) {
        checkMicrophonePermission()
        if hasMicPermission {
            action?()
            return
        }
        guard AVAudioApplication.shared.recordPermission == .undetermined else { return }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.hasMicPermission = granted
                if granted {
                    action?()
                } else {
                    self.errorMessage = "마이크 권한이 거부되었습니다. 설정 > 개인정보 보호에서 허용해주세요."
                }
            }
        }
    }

    // MARK: - Microphone control

    public func startMicrophone() {
        guard !isMicrophoneRunning else { return }
        guard hasMicPermission else {
            requestMicrophonePermission { [weak self] in self?.startMicrophone() }
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            // Preferred (not guaranteed) IO duration ~2048 frames @48 kHz:
            // keeps analysis latency around 43 ms without starving the CPU.
            try? session.setPreferredIOBufferDuration(2048.0 / 48000.0)
            try session.setActive(true)
            cancelPendingEngineStop()

            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
                throw NSError(domain: "VocalAudioEngine", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "입력 오디오 포맷을 사용할 수 없습니다."])
            }

            // Detector must match the actual hardware rate (48 kHz on modern
            // iPhones). Local constant: the escaping tap closure captures it
            // by value (Sendable), avoiding both an explicit-self requirement
            // and any engine->tap->engine retain cycle.
            let detector = YINPitchDetector(sampleRate: inputFormat.sampleRate)

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
                self?.handleAudioFrame(buffer, detector: detector)
            }

            engine.prepare()
            try engine.start()
            isMicrophoneRunning = true
            errorMessage = nil
            resetAnalysisState()
        } catch {
            errorMessage = "마이크를 시작할 수 없습니다: \(error.localizedDescription)"
            isMicrophoneRunning = false
        }
    }

    public func stopMicrophone() {
        guard isMicrophoneRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        isMicrophoneRunning = false
        resetAnalysisState()
        scheduleEngineStopIfIdle()
    }

    private func resetAnalysisState() {
        currentFrequency = 0
        currentNoteName = "--"
        centsDeviation = 0
        amplitude = 0
        isVoiceDetected = false
        previousFrequency1 = 0
        previousFrequency2 = 0
        lastVoicedFrequency = 0
        frameGate.reset()
    }

    // MARK: - Render-thread frame handler (nonisolated, keep minimal)

    nonisolated private func handleAudioFrame(_ buffer: AVAudioPCMBuffer, detector: YINPitchDetector) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength >= 1024 else { return }

        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(frameLength))

        // Deep copy: the underlying buffer is owned by CoreAudio and recycled
        // as soon as this callback returns.
        let samples = Array(UnsafeBufferPointer(start: channel, count: frameLength))

        // Latest-wins backpressure: drop the frame when analysis is behind.
        guard frameGate.tryEnter() else { return }

        processingQueue.async { [weak self] in
            let estimate = detector.detect(in: samples)
            Task { @MainActor in
                // The engine is a process-lifetime singleton; a nil self here
                // would only be possible during app teardown, where the gate
                // no longer matters.
                guard let self else { return }
                self.frameGate.leave()
                guard self.isMicrophoneRunning else { return }
                self.publish(estimate: estimate, frameRMS: Double(rms))
            }
        }
    }

    // MARK: - Publishing (MainActor)

    private func publish(estimate: PitchEstimate, frameRMS: Double) {
        amplitude = amplitude * 0.6 + frameRMS * 0.4
        isVoiceDetected = frameRMS > silenceRMSGate && estimate.isVoiced

        guard isVoiceDetected else {
            currentFrequency = 0
            currentNoteName = "--"
            centsDeviation = 0
            previousFrequency1 = 0
            previousFrequency2 = 0
            onPitchUpdate?(0, "--", 0, false)
            return
        }

        // Octave-jump rejection: a jump of ~1 octave right after a stable
        // voiced frame, with only moderate confidence, is almost always a
        // YIN harmonic confusion — keep the previous stable estimate.
        if lastVoicedFrequency > 0 {
            let ratio = estimate.frequency / lastVoicedFrequency
            if (ratio > 1.9 || ratio < 0.55) && estimate.confidence < 0.85 {
                onPitchUpdate?(lastVoicedFrequency, currentNoteName, centsDeviation, true)
                return
            }
        }

        // Median-of-3 smoothing stabilizes the displayed note against octave flips.
        var candidates = [estimate.frequency]
        if previousFrequency1 > 0 { candidates.append(previousFrequency1) }
        if previousFrequency2 > 0 { candidates.append(previousFrequency2) }
        candidates.sort()
        let stable = candidates[candidates.count / 2]

        previousFrequency2 = previousFrequency1
        previousFrequency1 = stable
        lastVoicedFrequency = stable

        let conversion = Self.noteAndCents(fromFrequency: stable)
        currentFrequency = stable
        currentNoteName = conversion.note
        centsDeviation = conversion.cents
        onPitchUpdate?(stable, conversion.note, conversion.cents, true)
    }

    // MARK: - Guide tone playback (shared engine output)

    /// Plays a synthesized guide tone (triangle + 2 harmonics, ADSR envelope).
    public func playTone(frequency: Double, duration: TimeInterval = 0.7, volume: Float = 0.5) {
        guard frequency > 20, frequency < 8000, volume > 0 else { return }
        do {
            cancelPendingEngineStop()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try session.setActive(true)
            attachToneNodeIfNeeded()
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            guard let buffer = makeToneBuffer(frequency: frequency, duration: duration, volume: volume) else {
                return
            }
            activeToneCount += 1
            toneNode.scheduleBuffer(buffer) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.activeToneCount = max(0, self.activeToneCount - 1)
                    self.scheduleEngineStopIfIdle()
                }
            }
            if !toneNode.isPlaying {
                toneNode.play()
            }
        } catch {
            errorMessage = "가이드 톤 재생 실패: \(error.localizedDescription)"
        }
    }

    /// Immediately silences all scheduled guide tones (used when a sequence stops).
    public func stopAllTones() {
        guard isToneNodeAttached else { return }
        toneNode.stop()
        activeToneCount = 0
        scheduleEngineStopIfIdle()
    }

    private func attachToneNodeIfNeeded() {
        guard !isToneNodeAttached else { return }
        engine.attach(toneNode)
        engine.connect(toneNode, to: engine.mainMixerNode, format: toneFormat)
        isToneNodeAttached = true
    }

    private var toneFormat: AVAudioFormat {
        let mixerRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let rate = mixerRate > 0 ? mixerRate : 44100
        return AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    }

    private func makeToneBuffer(frequency: Double, duration: TimeInterval, volume: Float) -> AVAudioPCMBuffer? {
        let sampleRate = toneFormat.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: toneFormat, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let data = buffer.floatChannelData?[0] else { return nil }

        let attack = 0.03
        let decay = 0.15
        let sustain: Float = 0.65
        let release = min(0.2, duration * 0.3)
        let releaseStart = duration - release

        let attackFrames = Int(sampleRate * attack)
        let decayFrames = Int(sampleRate * decay)
        let releaseStartFrame = Int(sampleRate * releaseStart)
        let totalFrames = Int(frameCount)

        let twoPi = 2.0 * Double.pi
        for i in 0..<totalFrames {
            let t = Double(i) / sampleRate
            let wave = sin(twoPi * frequency * t)
                + 0.3 * sin(twoPi * frequency * 2.0 * t)
                + 0.12 * sin(twoPi * frequency * 3.0 * t)

            var envelope: Float = sustain
            if i < attackFrames {
                envelope = Float(i) / Float(max(attackFrames, 1))
            } else if i < attackFrames + decayFrames {
                let progress = Float(i - attackFrames) / Float(max(decayFrames, 1))
                envelope = 1.0 - progress * (1.0 - sustain)
            } else if i >= releaseStartFrame {
                let span = max(totalFrames - releaseStartFrame, 1)
                let progress = Float(i - releaseStartFrame) / Float(span)
                envelope = sustain * (1.0 - progress)
            }
            data[i] = Float(wave) / 1.42 * envelope * volume
        }
        return buffer
    }

    // MARK: - Engine idle management

    /// The engine keeps running while the microphone or any tone is active.
    /// When both are idle it is stopped (and the session deactivated) shortly
    /// after, so other apps' audio can resume.
    private func scheduleEngineStopIfIdle() {
        guard !isMicrophoneRunning, activeToneCount <= 0 else { return }
        engineStopWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, !self.isMicrophoneRunning, self.activeToneCount <= 0 else { return }
                if self.isToneNodeAttached { self.toneNode.stop() }
                self.engine.stop()
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
        engineStopWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    private func cancelPendingEngineStop() {
        engineStopWorkItem?.cancel()
        engineStopWorkItem = nil
    }

    // MARK: - Session notifications

    private func installAudioSessionObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            Task { @MainActor in
                guard type == .began else { return }
                self?.handleInterruptionBegan()
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let rawReason = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
                  reason == .oldDeviceUnavailable else { return }
            Task { @MainActor in
                self?.restartMicrophoneAfterRouteChange()
            }
        }
    }

    private func handleInterruptionBegan() {
        // Phone call, Siri, alarm: tear the graph down. Callers observe
        // isMicrophoneRunning to pause their own state.
        stopAllTones()
        stopMicrophone()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func restartMicrophoneAfterRouteChange() {
        guard isMicrophoneRunning else { return }
        stopMicrophone()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            self.startMicrophone()
        }
    }

    // MARK: - Note <-> frequency conversion (pure statics, usable anywhere)

    /// Tuning reference (A4). Apps or instruments the user sings along with
    /// are not always at 440 Hz; the whole note<->frequency chain follows
    /// this value. Clamped to 435...445 and persisted in UserDefaults
    /// (0 = unset = standard pitch).
    public static var referenceA4: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: "referenceA4")
            guard stored != 0 else { return 440.0 }
            return min(445.0, max(435.0, stored))
        }
        set {
            UserDefaults.standard.set(min(445.0, max(435.0, newValue)), forKey: "referenceA4")
        }
    }

    public static func midiNumber(forFrequency frequency: Double) -> Double {
        VocalLogic.midiNumber(forFrequency: frequency, a4: referenceA4)
    }

    public static func frequency(forMidi midi: Double) -> Double {
        VocalLogic.frequency(forMidi: midi, a4: referenceA4)
    }

    public static func noteAndCents(fromFrequency frequency: Double) -> (note: String, midi: Int, cents: Double) {
        VocalLogic.noteAndCents(fromFrequency: frequency, a4: referenceA4)
    }

    /// Parses note names like "C4", "F#3", "Bb4" into a MIDI number.
    public static func midiNumber(forNoteName name: String) -> Int? {
        VocalLogic.midiNumber(forNoteName: name)
    }
}
