//
//  LiveActivityManager.swift
//  DailyVocal
//
//  Dynamic Island / Lock Screen Live Activity lifecycle. No-ops gracefully
//  when Live Activities are unavailable (Simulator, denied, not supported).
//

import Foundation
import ActivityKit

@MainActor
public final class LiveActivityManager {

    public static let shared = LiveActivityManager()

    private var currentActivity: Activity<VocalActivityAttributes>?

    private init() {}

    public var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    public func startLiveActivity(
        stepIndex: Int,
        stepTitle: String,
        soundKeyword: String,
        durationSeconds: Int,
        totalProgress: Double
    ) {
        endLiveActivity()
        guard areActivitiesEnabled else { return }

        let now = Date()
        let attributes = VocalActivityAttributes(sessionStartTime: now)
        let state = VocalActivityAttributes.ContentState(
            currentStepIndex: stepIndex,
            stepTitle: stepTitle,
            soundKeyword: soundKeyword,
            stepStartTime: now,
            stepEndTime: now.addingTimeInterval(TimeInterval(durationSeconds)),
            totalProgress: totalProgress
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: state.stepEndTime.addingTimeInterval(120)),
                pushType: nil
            )
        } catch {
            print("Live Activity 시작 실패: \(error.localizedDescription)")
        }
    }

    public func updateStep(
        stepIndex: Int,
        stepTitle: String,
        soundKeyword: String,
        remainingSeconds: Int,
        totalProgress: Double,
        isPaused: Bool = false
    ) {
        guard let activity = currentActivity else { return }
        let now = Date()
        let state = VocalActivityAttributes.ContentState(
            currentStepIndex: stepIndex,
            stepTitle: stepTitle,
            soundKeyword: soundKeyword,
            stepStartTime: now,
            stepEndTime: now.addingTimeInterval(TimeInterval(remainingSeconds)),
            totalProgress: totalProgress,
            isPaused: isPaused,
            pausedRemainingText: Self.remainingFormatter.string(
                from: TimeInterval(max(0, remainingSeconds))
            ) ?? "\(remainingSeconds)초"
        )
        Task {
            await activity.update(
                .init(state: state, staleDate: state.stepEndTime.addingTimeInterval(120))
            )
        }
    }

    private static let remainingFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    /// Starts a Live Activity for a game session (vowel/interval/ear).
    public func startGameActivity(gameMode: String, totalRounds: Int) {
        let state = VocalActivityAttributes.ContentState(
            currentStepIndex: 0,
            stepTitle: gameMode,
            soundKeyword: "듣고 따라하기",
            stepStartTime: Date(),
            stepEndTime: Date().addingTimeInterval(TimeInterval(totalRounds * 5)),
            totalProgress: 0,
            gameMode: gameMode,
            gameRound: 1,
            gameTotal: totalRounds
        )
        Task { @MainActor in
            if let current = currentActivity {
                await current.update(ActivityContent(state: state, staleDate: nil))
            } else {
                _ = Activity.request(
                    attributes: VocalActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: nil)
                )
            }
        }
    }

    /// Updates the game round in the Live Activity.
    public func updateGameRound(_ round: Int, of total: Int) {
        guard let activity = currentActivity else { return }
        let state = activity.content.state
        let updated = VocalActivityAttributes.ContentState(
            currentStepIndex: state.currentStepIndex,
            stepTitle: state.stepTitle,
            soundKeyword: state.soundKeyword,
            stepStartTime: state.stepStartTime,
            stepEndTime: state.stepEndTime,
            totalProgress: Double(round) / Double(max(total, 1)),
            gameMode: state.gameMode,
            gameRound: round,
            gameTotal: total
        )
        Task { @MainActor in
            await activity.update(ActivityContent(state: updated, staleDate: nil))
        }
    }

    public func endLiveActivity() {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
