//
//  VocalActivityAttributes.swift
//  5VocalMaster
//
//  ActivityKit attributes shared between the app target and the widget
//  extension target (both targets must include this file — see README).
//

import Foundation
import ActivityKit

public struct VocalActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        public var currentStepIndex: Int       // 1...5
        public var stepTitle: String
        public var soundKeyword: String
        public var stepStartTime: Date         // timer interval start
        public var stepEndTime: Date           // timer interval end
        public var totalProgress: Double       // 0...1
        public var isPaused: Bool
        /// Pre-formatted "mm:ss" shown instead of the (unfreezable) countdown
        /// timer while paused.
        public var pausedRemainingText: String

        public init(
            currentStepIndex: Int,
            stepTitle: String,
            soundKeyword: String,
            stepStartTime: Date,
            stepEndTime: Date,
            totalProgress: Double,
            isPaused: Bool = false,
            pausedRemainingText: String = ""
        ) {
            self.currentStepIndex = currentStepIndex
            self.stepTitle = stepTitle
            self.soundKeyword = soundKeyword
            self.stepStartTime = stepStartTime
            self.stepEndTime = stepEndTime
            self.totalProgress = totalProgress
            self.isPaused = isPaused
            self.pausedRemainingText = pausedRemainingText
        }
    }

    public var routineName: String
    public var sessionStartTime: Date

    public init(
        routineName: String = "5분 보컬 데일리 루틴",
        sessionStartTime: Date = .now
    ) {
        self.routineName = routineName
        self.sessionStartTime = sessionStartTime
    }
}
