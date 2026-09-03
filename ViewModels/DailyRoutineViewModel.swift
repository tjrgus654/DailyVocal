//
//  DailyRoutineViewModel.swift
//  5VocalMaster
//
//  Business logic for the 15-minute routine: step timer, partial-completion
//  tracking (a step counts as practiced after 70% of its duration), guide-tone
//  autoplay per step, Live Activity updates, and SwiftData persistence.
//

import SwiftUI
import Combine
import SwiftData
import AVFoundation

@MainActor
@Observable
public final class DailyRoutineViewModel {

    // MARK: - State

    public private(set) var routineSteps: [RoutineStep] = RoutinePresets.defaultRoutine(forWeek: 1)
    public private(set) var currentStepIndex = 0
    public private(set) var remainingSeconds = 0
    public private(set) var isTimerRunning = false
    public private(set) var totalElapsedSeconds = 0
    public private(set) var isSessionCompleted = false
    public private(set) var trainingWeek = 1
    /// True after the 4-week program ends: the W4 routine keeps repeating.
    public private(set) var isMaintenanceMode = false
    /// Substantial sessions finished today (4 AM rollover). Only full
    /// completions or sessions of 5+ minutes count toward the voice-rest
    /// recommendation — a 2-minute quick top-up should not trip it. Repeated
    /// same-day sessions accumulate vocal fatigue faster than benefit, so the
    /// completion card nudges toward recovery.
    public private(set) var sessionsCompletedToday = 0
    public var isVoiceRestRecommended: Bool { sessionsCompletedToday >= 2 }

    public var isScaleAutoPlayEnabled = true

    /// Full 15-minute program vs busy-day 2-minute shortcut. `.rest` is not
    /// user-selectable: it is entered automatically when the voice condition
    /// is "sore" so a painful day can never run the normal workload.
    public enum RoutineMode {
        case full
        case quick
        case rest
    }
    public private(set) var mode: RoutineMode = .full

    /// Daily self-reported voice condition (0 good / 1 tired / 2 sore).
    /// Sore swaps the routine for the minimal-SOVT rest day automatically.
    public enum VocalCondition: Int, CaseIterable, Identifiable {
        case good = 0
        case tired = 1
        case sore = 2
        public var id: Int { rawValue }
    }
    /// @Observable runs property observers even for assignments in init,
    /// so the persisted-condition restore must not fire the didSet logic
    /// (measured empirically) — gate it on this flag.
    private var bootstrapped = false
    public var vocalCondition: VocalCondition = .good {
        didSet {
            UserDefaults.standard.set(vocalCondition.rawValue, forKey: "vocalCondition")
            guard bootstrapped, vocalCondition != oldValue else { return }
            if vocalCondition == .sore {
                if isTimerRunning { pause() }
                switchToRestRoutine(notify: true)
            } else if mode == .rest {
                // Recovering the chip on the same screen must leave rest mode
                // too, or the user feels locked out of the normal program.
                sequencer.stop()
                mode = .full
                routineSteps = RoutinePresets.defaultRoutine(forWeek: trainingWeek)
                currentStepIndex = 0
                totalElapsedSeconds = 0
                stepElapsedSeconds = 0
                completedStepIndices = []
                isSessionCompleted = false
                remainingSeconds = routineSteps.first?.durationSeconds ?? 0
                stepEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
            }
        }
    }
    /// One-shot message surfaced by the view after an automatic rest switch.
    public private(set) var restNotice: String?
    public func clearRestNotice() { restNotice = nil }

    /// Accumulated 0-based indices of steps practiced >= 70% of their duration.
    public private(set) var completedStepIndices: Set<Int> = []
    private var stepElapsedSeconds = 0
    /// Wall-clock end of the current step; the tick recomputes the remaining
    /// time from it so timer drift and background suspension cannot desync
    /// the in-app countdown from the Live Activity countdown.
    private var stepEndDate = Date()

    // MARK: - Services

    let audio = VocalAudioEngine.shared
    let sequencer = ScaleSequencer.shared
    private let haptics = HapticManager.shared
    private let liveActivity = LiveActivityManager.shared

    // deinit runs nonisolated; these tokens are only mutated on the main
    // actor and the object is already unreferenced there, so the unsynchronised
    // final read is safe.
    nonisolated(unsafe) private var timerCancellable: AnyCancellable?
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    private var modelContext: ModelContext?
    private var profile: UserProfile?

    public init() {
        remainingSeconds = routineSteps.first?.durationSeconds ?? 0
        vocalCondition = VocalCondition(rawValue: UserDefaults.standard.integer(forKey: "vocalCondition")) ?? .good
        if vocalCondition == .sore {
            mode = .rest
            routineSteps = RoutinePresets.restRoutine()
            remainingSeconds = routineSteps.first?.durationSeconds ?? 0
        }
        observeAudioInterruptions()
        bootstrapped = true
    }

    deinit {
        timerCancellable?.cancel()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    // MARK: - Context / profile

    public func setModelContext(_ context: ModelContext) {
        let isFirstInjection = modelContext == nil
        modelContext = context
        // Re-entering the tab (TabView fires onAppear on every switch) must
        // not wipe an in-progress session; refresh only on first injection or
        // when nothing is in progress.
        let sessionInProgress = isTimerRunning || totalElapsedSeconds > 0 || isSessionCompleted
        if isFirstInjection || !sessionInProgress {
            refreshFromProfile()
        }
    }

    private func refreshFromProfile() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<UserProfile>()
        profile = (try? context.fetch(descriptor))?.first

        let week = profile?.computeTrainingWeek() ?? 1
        trainingWeek = week
        isMaintenanceMode = (profile?.weeksElapsedSinceCreation() ?? 0) + 1 > 4
        // Recover the picker state on re-entry, but a sore voice wins: the
        // rest routine stays until the condition is changed back.
        if mode == .rest && vocalCondition != .sore {
            mode = .full
        }
        routineSteps = mode == .quick
            ? RoutinePresets.quickRoutine()
            : (mode == .rest ? RoutinePresets.restRoutine()
                             : RoutinePresets.defaultRoutine(forWeek: week))
        currentStepIndex = 0
        totalElapsedSeconds = 0
        completedStepIndices = []
        stepElapsedSeconds = 0
        isSessionCompleted = false
        remainingSeconds = routineSteps.first?.durationSeconds ?? 0
        stepEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        refreshSessionsToday()
    }

    /// Counts sessions whose practice day (4 AM rollover, same key as the
    /// streak logic) is today. Fetch-then-filter in memory: the day key is a
    /// computed property, so it cannot live inside a SwiftData predicate.
    private func refreshSessionsToday() {
        guard let context = modelContext else { return }
        let todayKey = VocalLogic.practiceDayKey(for: .now)
        let sessions = (try? context.fetch(FetchDescriptor<PracticeSession>())) ?? []
        sessionsCompletedToday = sessions.filter {
            VocalLogic.practiceDayKey(for: $0.date) == todayKey
                && ($0.isFullCompletion || $0.durationSeconds >= 300)
        }.count
    }

    /// Switches between the 15-minute program and the 2-minute quick set.
    /// Resets step state; safe to call mid-session (stops playback first).
    public func setMode(_ newMode: RoutineMode) {
        guard newMode != mode else { return }
        pause()
        mode = newMode
        currentStepIndex = 0
        totalElapsedSeconds = 0
        stepElapsedSeconds = 0
        completedStepIndices = []
        isSessionCompleted = false
        routineSteps = newMode == .quick
            ? RoutinePresets.quickRoutine()
            : RoutinePresets.defaultRoutine(forWeek: trainingWeek)
        remainingSeconds = routineSteps.first?.durationSeconds ?? 0
        stepEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        liveActivity.endLiveActivity()
    }

    // MARK: - Computed

    public var currentStep: RoutineStep {
        guard currentStepIndex < routineSteps.count else {
            return routineSteps.last ?? routineSteps[0]
        }
        return routineSteps[currentStepIndex]
    }

    public var currentStepProgress: Double {
        let total = Double(currentStep.durationSeconds)
        guard total > 0 else { return 0 }
        return 1.0 - Double(remainingSeconds) / total
    }

    public var overallProgress: Double {
        let total = Double(routineSteps.reduce(0) { $0 + $1.durationSeconds })
        guard total > 0 else { return 0 }
        return min(1.0, Double(totalElapsedSeconds) / total)
    }

    public var formattedRemainingTime: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private var modeLabel: String {
        switch mode {
        case .full: return "데일리"
        case .quick: return "2분 퀵"
        case .rest: return "쉬는 날"
        }
    }

    /// Switches to the 2-minute minimal-SOVT routine and resets progress.
    private func switchToRestRoutine(notify: Bool) {
        pause()
        mode = .rest
        routineSteps = RoutinePresets.restRoutine()
        currentStepIndex = 0
        totalElapsedSeconds = 0
        stepElapsedSeconds = 0
        completedStepIndices = []
        isSessionCompleted = false
        remainingSeconds = routineSteps.first?.durationSeconds ?? 0
        stepEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        if notify {
            restNotice = "목이 아픈 날은 쉬는 것도 훈련입니다. 오늘은 아주 작은 빨대 발성과 허밍만 하는 2분 루틴으로 바꿨어요."
        }
    }

    // MARK: - Playback control

    public func togglePlayPause() {
        haptics.buttonTap()
        isTimerRunning ? pause() : play()
    }

    public func play() {
        guard !isTimerRunning else { return }
        // A sore voice never runs the normal workload; swap before starting.
        if vocalCondition == .sore && mode != .rest {
            switchToRestRoutine(notify: true)
        }
        isTimerRunning = true
        // Resuming (or starting): anchor the step clock to the remaining time.
        stepEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))

        // Microphone powers the live waveform; if permission is undetermined
        // the engine requests it and the waveform starts once granted.
        audio.startMicrophone()

        if isScaleAutoPlayEnabled {
            startGuideSequencerForCurrentStep()
        }

        liveActivity.startLiveActivity(
            stepIndex: currentStepIndex + 1,
            stepTitle: currentStep.title,
            soundKeyword: currentStep.soundKeyword,
            durationSeconds: remainingSeconds,
            totalProgress: overallProgress
        )

        startTimerTicker()
    }

    public func pause() {
        guard isTimerRunning else { return }
        isTimerRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        sequencer.stop()
        audio.stopMicrophone()

        liveActivity.updateStep(
            stepIndex: currentStepIndex + 1,
            stepTitle: currentStep.title,
            soundKeyword: currentStep.soundKeyword,
            remainingSeconds: remainingSeconds,
            totalProgress: overallProgress,
            isPaused: true
        )
    }

    private func startTimerTicker() {
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        // Wall-clock authoritative countdown: recomputes from stepEndDate so
        // Timer.publish drift, missed ticks during suspension, or an early
        // tick can never add or lose time. Advances in the same tick that
        // reaches zero (no dead +1s per step).
        let wallRemaining = max(0, Int(stepEndDate.timeIntervalSinceNow.rounded(.down)))
        guard wallRemaining < remainingSeconds else { return }

        let elapsedDelta = remainingSeconds - wallRemaining
        remainingSeconds = wallRemaining
        totalElapsedSeconds += elapsedDelta
        stepElapsedSeconds += elapsedDelta

        guard remainingSeconds > 0 else {
            advanceToNextStep()
            return
        }

        if remainingSeconds % 30 == 0 {
            haptics.tick()
        }
        if remainingSeconds <= 3 {
            haptics.tick()
        }
    }

    // MARK: - Step navigation

    public func nextStep() {
        haptics.stepTransition()
        advanceToNextStep()
    }

    private func advanceToNextStep() {
        closeCurrentStep()

        guard currentStepIndex + 1 < routineSteps.count else {
            completeRoutine()
            return
        }

        currentStepIndex += 1
        remainingSeconds = currentStep.durationSeconds
        stepElapsedSeconds = 0
        stepEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))

        if isTimerRunning {
            if isScaleAutoPlayEnabled {
                startGuideSequencerForCurrentStep()
            }
            liveActivity.updateStep(
                stepIndex: currentStepIndex + 1,
                stepTitle: currentStep.title,
                soundKeyword: currentStep.soundKeyword,
                remainingSeconds: remainingSeconds,
                totalProgress: overallProgress
            )
        }
    }

    public func previousStep() {
        guard currentStepIndex > 0 else { return }
        haptics.stepTransition()
        closeCurrentStep()
        sequencer.stop()

        currentStepIndex -= 1
        remainingSeconds = currentStep.durationSeconds
        stepElapsedSeconds = 0
        stepEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))

        if isTimerRunning && isScaleAutoPlayEnabled {
            startGuideSequencerForCurrentStep()
        }
    }

    /// A step practiced for at least 70% of its duration counts as completed.
    private func closeCurrentStep() {
        let threshold = Double(currentStep.durationSeconds) * 0.7
        if stepElapsedSeconds >= Int(threshold) {
            completedStepIndices.insert(currentStepIndex)
        }
        stepElapsedSeconds = 0
    }

    public func reset() {
        pause()
        currentStepIndex = 0
        totalElapsedSeconds = 0
        stepElapsedSeconds = 0
        completedStepIndices = []
        isSessionCompleted = false
        remainingSeconds = routineSteps.first?.durationSeconds ?? 0
        stepEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        liveActivity.endLiveActivity()
    }

    // MARK: - Completion

    private func completeRoutine() {
        pause()
        isSessionCompleted = true
        haptics.routineCompleted()
        liveActivity.endLiveActivity()

        let fullCompletion = completedStepIndices.count == routineSteps.count
        persistSession(isFullCompletion: fullCompletion)
    }

    private func persistSession(isFullCompletion: Bool) {
        guard let context = modelContext else { return }

        let week = trainingWeek
        let elapsed = totalElapsedSeconds
        let steps = completedStepIndices.sorted()

        // A skip-through "session" (next pressed 5x, nothing practiced) is not
        // practice: it must not count toward the streak or session totals.
        guard elapsed >= 60, !steps.isEmpty else { return }

        let session = PracticeSession(
            durationSeconds: elapsed,
            completedStepIndices: steps,
            isFullCompletion: isFullCompletion,
            weekNumber: week,
            notes: "\(week)주차 \(modeLabel) 루틴"
        )
        context.insert(session)

        if let profile {
            profile.totalPracticeSeconds += elapsed
            profile.completedSessionCount += 1
            profile.lastPracticeDate = .now
            profile.currentWeek = profile.computeTrainingWeek()
        }
        try? context.save()
        refreshSessionsToday()
    }

    // MARK: - Profile sync

    /// Keeps the stored profile in sync with the @AppStorage key preference
    /// so both sources never disagree.
    public func syncProfileKeyPreference(_ prefersHigher: Bool) {
        if let profile {
            profile.prefersHigherKeyGuide = prefersHigher
            try? modelContext?.save()
        }
    }

    // MARK: - Guide sequencer

    private func startGuideSequencerForCurrentStep() {
        // Live source of truth is the AppStorage key written by the onboarding
        // page and the routine settings card (the profile keeps a copy).
        let prefersHigherKey = UserDefaults.standard.bool(forKey: "prefersHigherKeyGuide")
        let baseMidi = prefersHigherKey ? 60 : 48
        sequencer.start(
            pattern: ScaleSequencer.pattern(for: currentStep.recommendedToneType),
            baseMidi: baseMidi,
            repetitions: 6,
            beatsPerMinute: 80,
            maxDuration: TimeInterval(remainingSeconds + 5)
        )
    }

    // MARK: - Audio interruption (phone call, Siri, ...)

    private func observeAudioInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
            Task { @MainActor in
                self?.pause()
            }
        }
    }
}
