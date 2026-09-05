//
//  UserProfile.swift
//  DailyVocal
//
//  SwiftData model for the single user profile: baseline vocal range (measured
//  during onboarding), current vocal range (extended as the user practices),
//  cumulative stats, and reminder settings.
//

import Foundation
import SwiftData

@Model
public final class UserProfile {

    // Identity
    public var id: UUID
    public var createdAt: Date
    public var userName: String

    // True when the onboarding range test was actually measured.
    public var hasMeasuredRange: Bool

    // Baseline range captured at onboarding ("before").
    public var baselineLowestNoteName: String
    public var baselineLowestFrequency: Double
    public var baselineHighestNoteName: String
    public var baselineHighestFrequency: Double

    // Current range, updated whenever a tracking session extends it ("after").
    public var lowestNoteName: String
    public var lowestFrequency: Double
    public var highestNoteName: String
    public var highestFrequency: Double

    // Guide-tone key preference (false = male C3 base, true = female C4 base).
    public var prefersHigherKeyGuide: Bool
    /// Habitual speech pitch in Hz (median over a 10s speaking sample).
    /// 0 = not yet measured.
    public var speechMedianFrequency: Double
    /// Last vibrato check: oscillation rate in Hz (0 = not yet measured).
    public var lastVibratoRateHz: Double = 0
    /// Last vibrato check: extent in cents from the mean.
    public var lastVibratoExtentCents: Double = 0
    /// Last messa di voce check: dynamic range in dB.
    public var lastDynamicsRangeDb: Double = 0
    /// Longest continuously voiced single-note hold, in seconds (MPT-style).
    public var bestSustainSeconds: Double = 0

    // Progress
    public var currentWeek: Int           // 1...4
    public var totalPracticeSeconds: Int
    public var completedSessionCount: Int
    public var streakFreezeTokens: Int
    public var lastPracticeDate: Date?
    /// Day keys (yyyy-MM-dd, 4am-rollover) where a freeze token bridged a missed day.
    public var frozenDayKeys: [String] = []

    // Daily reminder
    public var reminderEnabled: Bool
    public var reminderHour: Int
    public var reminderMinute: Int

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        userName: String = "보컬 꿈나무",
        hasMeasuredRange: Bool = false,
        baselineLowestNoteName: String = "C3",
        baselineLowestFrequency: Double = 130.81,
        baselineHighestNoteName: String = "F4",
        baselineHighestFrequency: Double = 349.23,
        lowestNoteName: String = "C3",
        lowestFrequency: Double = 130.81,
        highestNoteName: String = "F4",
        highestFrequency: Double = 349.23,
        prefersHigherKeyGuide: Bool = false,
        speechMedianFrequency: Double = 0,
        currentWeek: Int = 1,
        totalPracticeSeconds: Int = 0,
        completedSessionCount: Int = 0,
        streakFreezeTokens: Int = 2,
        lastPracticeDate: Date? = nil,
        reminderEnabled: Bool = true,
        reminderHour: Int = 20,
        reminderMinute: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.userName = userName
        self.hasMeasuredRange = hasMeasuredRange
        self.baselineLowestNoteName = baselineLowestNoteName
        self.baselineLowestFrequency = baselineLowestFrequency
        self.baselineHighestNoteName = baselineHighestNoteName
        self.baselineHighestFrequency = baselineHighestFrequency
        self.lowestNoteName = lowestNoteName
        self.lowestFrequency = lowestFrequency
        self.highestNoteName = highestNoteName
        self.highestFrequency = highestFrequency
        self.prefersHigherKeyGuide = prefersHigherKeyGuide
        self.speechMedianFrequency = speechMedianFrequency
        self.currentWeek = currentWeek
        self.totalPracticeSeconds = totalPracticeSeconds
        self.completedSessionCount = completedSessionCount
        self.streakFreezeTokens = streakFreezeTokens
        self.lastPracticeDate = lastPracticeDate
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }

    /// 1...4, derived from weeks elapsed since profile creation.
    public func computeTrainingWeek(at date: Date = .now, calendar: Calendar = .current) -> Int {
        Swift.min(4, Swift.max(1, weeksElapsedSinceCreation(at: date, calendar: calendar) + 1))
    }

    /// Raw weeks since the program started; > 3 means the 4-week program is over.
    public func weeksElapsedSinceCreation(at date: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.dateComponents(
            [.weekOfYear],
            from: calendar.startOfDay(for: createdAt),
            to: calendar.startOfDay(for: date)
        ).weekOfYear ?? 0
    }
}
