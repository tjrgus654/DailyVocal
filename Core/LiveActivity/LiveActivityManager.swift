//
//  LiveActivityManager.swift
//  5VocalMaster
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
        formatter.zeroFormattingBehavior = .padUnits
        return formatter
    }()

    public func endLiveActivity() {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
