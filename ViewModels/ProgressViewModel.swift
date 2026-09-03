//
//  ProgressViewModel.swift
//  5VocalMaster
//
//  Growth dashboard statistics computed from real SwiftData records:
//  streak, totals, weekday-aligned 12-week heatmap, and vocal range growth
//  measured against the onboarding baseline stored in UserProfile.
//

import SwiftUI
import SwiftData

@MainActor
@Observable
public final class ProgressViewModel {

    public private(set) var currentStreak = 0
    public private(set) var totalSessions = 0
    public private(set) var totalPracticeTimeFormatted = "0분"
    public private(set) var heatmapDays: [HeatmapDay] = []
    /// Days bridged by a freeze token inside the current streak.
    public private(set) var frozenDaysInStreak = 0
    /// Practice days within the current Mon..Sun week (goal: 5/week).
    public private(set) var weeklyPracticeDays = 0
    public let weeklyGoalDays = 5
    /// Summary of the most recent pitch measurement, e.g. "87점 · A등급 · E4".
    public private(set) var latestPitchSummary: String?

    // Vocal range growth (from the user profile, extended by tracking sessions)
    public private(set) var hasMeasuredRange = false
    public private(set) var baselineRangeText = "측정 전"
    public private(set) var currentRangeText = "측정 전"
    public private(set) var rangeExpansionSemitones = 0
    public private(set) var streakFreezeTokens = 2

    public init() {
        heatmapDays = VocalLogic.buildEmptyHeatmap(dayCount: 84)
    }

    // MARK: - Update entry point (called by the view with @Query results)

    public func update(sessions: [PracticeSession], profile: UserProfile?, latestPitchRecord: PitchRecord? = nil) {
        totalSessions = sessions.count

        let totalSeconds = sessions.reduce(0) { $0 + $1.durationSeconds }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        totalPracticeTimeFormatted = hours > 0 ? "\(hours)시간 \(minutes)분" : "\(minutes)분"

        let practiceDays = Set(sessions.map { VocalLogic.practiceDayKey(for: $0.date) })
        let frozenDays = Set(profile?.frozenDayKeys ?? [])
        let result = VocalLogic.calculateStreak(
            practiceDays: practiceDays,
            frozenDays: frozenDays,
            freezeTokens: profile?.streakFreezeTokens ?? 0
        )
        currentStreak = result.streak

        // Auto-consume a freeze token when it bridged exactly one missed day.
        if let consumedDay = result.consumedDay, let profile {
            profile.streakFreezeTokens = max(0, profile.streakFreezeTokens - 1)
            profile.frozenDayKeys.append(consumedDay)
            try? profile.modelContext?.save()
        }
        frozenDaysInStreak = result.usedFrozenCount

        var dayCounts: [String: Int] = [:]
        for session in sessions {
            dayCounts[VocalLogic.practiceDayKey(for: session.date), default: 0] += 1
        }

        // Weekly goal: practice days in the current Mon..Sun week.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        ) ?? today
        let weekKeys = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart).map { VocalLogic.dayFormatter.string(from: $0) }
        }
        weeklyPracticeDays = weekKeys.filter { practiceDays.contains($0) }.count

        heatmapDays = VocalLogic.buildHeatmap(dayCounts: dayCounts, dayCount: 84)

        if let profile {
            streakFreezeTokens = profile.streakFreezeTokens
            hasMeasuredRange = profile.hasMeasuredRange
            baselineRangeText = "\(profile.baselineLowestNoteName) ~ \(profile.baselineHighestNoteName)"
            currentRangeText = "\(profile.lowestNoteName) ~ \(profile.highestNoteName)"
            let baselineTop = VocalAudioEngine.midiNumber(forFrequency: profile.baselineHighestFrequency)
            let currentTop = VocalAudioEngine.midiNumber(forFrequency: profile.highestFrequency)
            rangeExpansionSemitones = Int((currentTop - baselineTop).rounded())
        }

        if let record = latestPitchRecord {
            let grade = VocalLogic.sessionGrade(forScore: Int(record.accuracyPercentage.rounded()))
            latestPitchSummary = "\(Int(record.accuracyPercentage.rounded()))점 · \(grade)등급 · 목표음 \(record.targetNoteName)"
        } else {
            latestPitchSummary = nil
        }
    }

    private func now() -> Date { Date() }
}
