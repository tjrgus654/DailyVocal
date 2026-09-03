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

public struct HeatmapDay: Identifiable, Hashable {
    /// Stable identity: re-issuing UUIDs on every update would rebuild the
    /// whole 84-cell grid even when only one day changed.
    public var id: String { dayKey }
    public let date: Date
    public let count: Int
    public let intensity: Double
    public let dayKey: String
}

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

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    public init() {
        heatmapDays = Self.buildEmptyHeatmap(dayCount: 84)
    }

    // MARK: - Update entry point (called by the view with @Query results)

    public func update(sessions: [PracticeSession], profile: UserProfile?, latestPitchRecord: PitchRecord? = nil) {
        totalSessions = sessions.count

        let totalSeconds = sessions.reduce(0) { $0 + $1.durationSeconds }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        totalPracticeTimeFormatted = hours > 0 ? "\(hours)시간 \(minutes)분" : "\(minutes)분"

        let practiceDays = Set(sessions.map { Self.practiceDayKey(for: $0.date) })
        let frozenDays = Set(profile?.frozenDayKeys ?? [])
        let result = Self.calculateStreak(
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
            dayCounts[Self.practiceDayKey(for: session.date), default: 0] += 1
        }

        // Weekly goal: practice days in the current Mon..Sun week.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        ) ?? today
        let weekKeys = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart).map { Self.dayFormatter.string(from: $0) }
        }
        weeklyPracticeDays = weekKeys.filter { practiceDays.contains($0) }.count

        heatmapDays = Self.buildHeatmap(dayCounts: dayCounts, dayCount: 84)

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
            let grade: String
            switch Int(record.accuracyPercentage.rounded()) {
            case 90...: grade = "S"
            case 80..<90: grade = "A"
            case 70..<80: grade = "B"
            case 60..<70: grade = "C"
            default: grade = "D"
            }
            latestPitchSummary = "\(Int(record.accuracyPercentage.rounded()))점 · \(grade)등급 · 목표음 \(record.targetNoteName)"
        } else {
            latestPitchSummary = nil
        }
    }

    private func now() -> Date { Date() }

    // MARK: - Practice day (4 AM rollover)

    /// A practice performed between 00:00 and 03:59 counts for the previous
    /// calendar day — late-night 한국 연습 습관을 고려한 스트릭 기준.
    static func practiceDayKey(for date: Date) -> String {
        let shifted = date.addingTimeInterval(-4 * 3600)
        return dayFormatter.string(from: shifted)
    }

    // MARK: - Streak (with automatic freeze consumption)

    struct StreakResult {
        var streak: Int
        var consumedDay: String?
        var usedFrozenCount: Int
    }

    /// Consecutive practice days ending today (yesterday still counts while
    /// today isn't practiced yet). One missed day is bridged automatically by
    /// consuming a freeze token; two consecutive missed days end the streak.
    static func calculateStreak(
        practiceDays: Set<String>,
        frozenDays: Set<String>,
        freezeTokens: Int,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> StreakResult {
        var streak = 0
        var tokens = freezeTokens
        var consumedDay: String?
        var usedFrozenCount = 0

        // Anchor to the 4am-rollover "practice day" of now.
        var cursor = calendar.startOfDay(for: now.addingTimeInterval(-4 * 3600))

        // Streak stays alive until yesterday even if today isn't practiced yet.
        if !practiceDays.contains(dayFormatter.string(from: cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return StreakResult(streak: 0, consumedDay: nil, usedFrozenCount: 0)
            }
            cursor = yesterday
        }

        var iterations = 0
        while iterations < 366 {
            iterations += 1
            let key = dayFormatter.string(from: cursor)
            let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor)

            if practiceDays.contains(key) {
                streak += 1
            } else if frozenDays.contains(key) {
                usedFrozenCount += 1
                // bridged by an earlier freeze — streak continues without counting
            } else if tokens > 0,
                      let previousDay,
                      // consume only when the streak actually resumes the day before
                      practiceDays.contains(dayFormatter.string(from: previousDay))
                        || frozenDays.contains(dayFormatter.string(from: previousDay)) {
                tokens -= 1
                consumedDay = key
            } else {
                break
            }
            guard let previousDay else { break }
            cursor = previousDay
        }
        return StreakResult(streak: streak, consumedDay: consumedDay, usedFrozenCount: usedFrozenCount + (consumedDay == nil ? 0 : 1))
    }

    // MARK: - Heatmap (12 weeks, columns aligned to Mon..Sun)

    static func buildHeatmap(dayCounts: [String: Int], dayCount: Int) -> [HeatmapDay] {
        buildDays(dayCount: dayCount) { key in
            let count = dayCounts[key, default: 0]
            return (count, min(1.0, Double(count) / 3.0))
        }
    }

    static func buildEmptyHeatmap(dayCount: Int) -> [HeatmapDay] {
        buildDays(dayCount: dayCount) { _ in (0, 0) }
    }

    private static func buildDays(
        dayCount: Int,
        content: (String) -> (count: Int, intensity: Double)
    ) -> [HeatmapDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Anchor to the Monday of the current week, then step back so the
        // grid starts exactly `dayCount/7 - 1` weeks earlier: columns then
        // line up with the Mon..Sun header.
        let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        guard let gridStart = calendar.date(byAdding: .weekOfYear, value: -(dayCount / 7 - 1), to: thisWeekStart) else {
            return []
        }

        var days: [HeatmapDay] = []
        for offset in 0..<dayCount {
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { continue }
            let key = dayFormatter.string(from: date)
            let (count, intensity) = content(key)
            days.append(HeatmapDay(date: date, count: count, intensity: intensity, dayKey: key))
        }
        return days
    }
}
