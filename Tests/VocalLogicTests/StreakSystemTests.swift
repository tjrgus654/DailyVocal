import XCTest
@testable import VocalLogic

final class StreakSystemTests: XCTestCase {

    private var calendar: Calendar { .current }

    /// Day key of `date` shifted by `days`.
    private func key(_ date: Date, offsetDays days: Int = 0) -> String {
        let shifted = calendar.date(byAdding: .day, value: days, to: date)!
        return VocalLogic.practiceDayKey(for: shifted)
    }

    /// A fixed "now" at 12:00 local so the 4 AM rollover never interferes.
    private func noon(_ daysAgo: Int = 0) -> Date {
        let base = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        return calendar.date(byAdding: .day, value: -daysAgo, to: base)!
    }

    func testEmptyPracticeGivesZeroStreak() {
        let result = VocalLogic.calculateStreak(practiceDays: [], frozenDays: [], freezeTokens: 2, now: noon())
        XCTAssertEqual(result.streak, 0)
        XCTAssertTrue(result.consumedDays.isEmpty)
    }

    func testConsecutiveDaysCount() {
        let now = noon()
        let days: Set<String> = [key(now, offsetDays: -2), key(now, offsetDays: -1), key(now)]
        let result = VocalLogic.calculateStreak(practiceDays: days, frozenDays: [], freezeTokens: 0, now: now)
        XCTAssertEqual(result.streak, 3)
    }

    func testYesterdayStillCountsWhenTodayMissing() {
        let now = noon()
        let days: Set<String> = [key(now, offsetDays: -1), key(now, offsetDays: -2)]
        let result = VocalLogic.calculateStreak(practiceDays: days, frozenDays: [], freezeTokens: 0, now: now)
        XCTAssertEqual(result.streak, 2)
    }

    func testOneGapConsumesFreezeToken() {
        let now = noon()
        // practiced today and two days ago; yesterday missing -> one freeze bridges it.
        let days: Set<String> = [key(now), key(now, offsetDays: -2)]
        let result = VocalLogic.calculateStreak(practiceDays: days, frozenDays: [], freezeTokens: 1, now: now)
        XCTAssertEqual(result.streak, 2)
        XCTAssertEqual(result.consumedDays, [key(now, offsetDays: -1)])
        XCTAssertEqual(result.usedFrozenCount, 1)
    }

    /// Two separate 1-day gaps, two tokens: BOTH gaps must be reported so the
    /// profile converges in a single update (single-slot regression guard).
    func testTwoGapsBothConsumedWithTwoTokens() {
        let now = noon()
        let days: Set<String> = [
            key(now), key(now, offsetDays: -2), key(now, offsetDays: -4),
        ]
        let result = VocalLogic.calculateStreak(practiceDays: days, frozenDays: [], freezeTokens: 2, now: now)
        XCTAssertEqual(result.streak, 3)
        XCTAssertEqual(Set(result.consumedDays), Set([key(now, offsetDays: -1), key(now, offsetDays: -3)]))
        XCTAssertEqual(result.usedFrozenCount, 2)
    }

    func testTwoGapsEndStreakWithoutTokens() {
        let now = noon()
        let days: Set<String> = [key(now), key(now, offsetDays: -3)]
        let result = VocalLogic.calculateStreak(practiceDays: days, frozenDays: [], freezeTokens: 2, now: now)
        // yesterday bridged by a token, the day before has no practice behind it -> stop.
        XCTAssertEqual(result.streak, 1)
    }

    func testPreviouslyFrozenDayBridgesWithoutNewConsumption() {
        let now = noon()
        let frozenYesterday = key(now, offsetDays: -1)
        let days: Set<String> = [key(now), key(now, offsetDays: -2)]
        let result = VocalLogic.calculateStreak(practiceDays: days, frozenDays: [frozenYesterday], freezeTokens: 0, now: now)
        XCTAssertEqual(result.streak, 2)
        XCTAssertTrue(result.consumedDays.isEmpty)
        XCTAssertEqual(result.usedFrozenCount, 1)
    }

    func testFourAMRollover() {
        // A session at 03:59 belongs to the previous calendar day; 04:01
        // belongs to the same calendar day as a noon session.
        let today = calendar.startOfDay(for: Date())
        let noonToday = today.addingTimeInterval(12 * 3600)
        let noonYesterday = calendar.date(byAdding: .day, value: -1, to: noonToday)!
        let beforeRollover = today.addingTimeInterval(3 * 3600 + 59 * 60)   // 03:59
        let afterRollover = today.addingTimeInterval(4 * 3600 + 1 * 60)     // 04:01
        XCTAssertEqual(VocalLogic.practiceDayKey(for: beforeRollover),
                       VocalLogic.practiceDayKey(for: noonYesterday))
        XCTAssertEqual(VocalLogic.practiceDayKey(for: afterRollover),
                       VocalLogic.practiceDayKey(for: noonToday))
        XCTAssertNotEqual(VocalLogic.practiceDayKey(for: beforeRollover),
                          VocalLogic.practiceDayKey(for: afterRollover))
    }

    func testHeatmapGridShapeAndWeekAlignment() {
        let days = VocalLogic.buildHeatmap(dayCounts: [:], dayCount: 84)
        XCTAssertEqual(days.count, 84)
        // First cell is a Monday (raw calendar weekday is locale-dependent:
        // compare via a Monday-pinned calendar like the app code).
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let weekday = mondayCalendar.component(.weekday, from: days[0].date)
        XCTAssertEqual(weekday, 2) // Sunday=1, Monday=2
        // Keys are unique (stable identity).
        XCTAssertEqual(Set(days.map(\.dayKey)).count, 84)
    }

    func testHeatmapIntensityBoundaries() {
        XCTAssertEqual(VocalLogic.heatmapIntensity(sessionCount: 0), 0)
        XCTAssertEqual(VocalLogic.heatmapIntensity(sessionCount: 1), 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(VocalLogic.heatmapIntensity(sessionCount: 2), 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(VocalLogic.heatmapIntensity(sessionCount: 3), 1.0)
        XCTAssertEqual(VocalLogic.heatmapIntensity(sessionCount: 99), 1.0)  // saturates
    }

    func testStepCompletionThresholdBoundaries() {
        // 70% boundary: exactly at threshold counts, one second under does not.
        XCTAssertTrue(VocalLogic.isStepCompleted(elapsedSeconds: 70, durationSeconds: 100))
        XCTAssertFalse(VocalLogic.isStepCompleted(elapsedSeconds: 69, durationSeconds: 100))
        // Rounding: 0.7 * 150 = 105 exactly.
        XCTAssertTrue(VocalLogic.isStepCompleted(elapsedSeconds: 105, durationSeconds: 150))
        XCTAssertFalse(VocalLogic.isStepCompleted(elapsedSeconds: 104, durationSeconds: 150))
        // Guard: zero/negative duration never completes.
        XCTAssertFalse(VocalLogic.isStepCompleted(elapsedSeconds: 100, durationSeconds: 0))
        XCTAssertFalse(VocalLogic.isStepCompleted(elapsedSeconds: 100, durationSeconds: -5))
        // Degenerate: zero elapsed on positive duration.
        XCTAssertFalse(VocalLogic.isStepCompleted(elapsedSeconds: 0, durationSeconds: 1))
    }

    func testSessionGradeBoundaries() {
        XCTAssertEqual(VocalLogic.sessionGrade(forScore: 100), "S")
        XCTAssertEqual(VocalLogic.sessionGrade(forScore: 90), "S")
        XCTAssertEqual(VocalLogic.sessionGrade(forScore: 89), "A")
        XCTAssertEqual(VocalLogic.sessionGrade(forScore: 80), "A")
        XCTAssertEqual(VocalLogic.sessionGrade(forScore: 79), "B")
        XCTAssertEqual(VocalLogic.sessionGrade(forScore: 70), "B")
        XCTAssertEqual(VocalLogic.sessionGrade(forScore: 69), "C")
        XCTAssertEqual(VocalLogic.sessionGrade(forScore: 60), "C")
        XCTAssertEqual(VocalLogic.sessionGrade(forScore: 59), "D")
        XCTAssertEqual(VocalLogic.sessionGrade(forScore: 0), "D")
    }
}
