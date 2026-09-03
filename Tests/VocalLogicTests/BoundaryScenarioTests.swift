import XCTest
@testable import VocalLogic

/// Calendar-boundary hardening: year rollover, leap day, freeze-token
/// exhaustion, heatmap week alignment and the 366-day iteration cap.
/// Dates are built in the machine's own calendar/timezone so the shared
/// dayFormatter (timezone = .current) stays consistent.
final class BoundaryScenarioTests: XCTestCase {

    private var calendar: Calendar { .current }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func key(_ date: Date) -> String {
        VocalLogic.practiceDayKey(for: date)
    }

    // MARK: - Year rollover

    func testLateNightSessionBeforeNewYearBelongsToOldYear() {
        // Jan 1 02:00 minus 4h = Dec 31 22:00 -> Dec 31 key.
        let lateNight = date(2025, 1, 1, 2, 0)
        XCTAssertEqual(key(lateNight), key(date(2024, 12, 31, 12, 0)))
    }

    func testStreakContinuesAcrossYearBoundary() {
        // "Now" is Jan 1 noon 2025; practiced Dec 30, Dec 31, Jan 1.
        let now = date(2025, 1, 1)
        let days: Set<String> = [
            key(date(2024, 12, 30)), key(date(2024, 12, 31)), key(date(2025, 1, 1)),
        ]
        let result = VocalLogic.calculateStreak(practiceDays: days, frozenDays: [], freezeTokens: 0, calendar: calendar, now: now)
        XCTAssertEqual(result.streak, 3)
    }

    // MARK: - Leap day (2024-02-29)

    func testLeapDayRolloverAndStreak() {
        // Mar 1 03:00 minus 4h = Feb 29 23:00 -> leap-day key.
        let earlyMarch = date(2024, 3, 1, 3, 0)
        XCTAssertEqual(key(earlyMarch), key(date(2024, 2, 29, 12, 0)))

        let now = date(2024, 3, 1)
        let days: Set<String> = [
            key(date(2024, 2, 28)), key(date(2024, 2, 29)), key(date(2024, 3, 1)),
        ]
        let result = VocalLogic.calculateStreak(practiceDays: days, frozenDays: [], freezeTokens: 0, calendar: calendar, now: now)
        XCTAssertEqual(result.streak, 3)
    }

    // MARK: - Freeze token exhaustion

    func testZeroTokensDoesNotBridgeSingleGap() {
        let now = date(2025, 6, 10)
        // practiced Jun 10 and Jun 8; Jun 9 missing; no tokens.
        let days: Set<String> = [key(date(2025, 6, 10)), key(date(2025, 6, 8))]
        let result = VocalLogic.calculateStreak(practiceDays: days, frozenDays: [], freezeTokens: 0, calendar: calendar, now: now)
        XCTAssertEqual(result.streak, 1)
        XCTAssertNil(result.consumedDay)
    }

    func testExhaustedTokensEndStreakAtSecondGap() {
        let now = date(2025, 6, 10)
        // Practiced Jun 10, Jun 8, Jun 5; gaps on Jun 9 and Jun 6-7 region.
        // One token bridges Jun 9 only; the older gap terminates the walk.
        let days: Set<String> = [
            key(date(2025, 6, 10)), key(date(2025, 6, 8)), key(date(2025, 6, 5)),
        ]
        let result = VocalLogic.calculateStreak(practiceDays: days, frozenDays: [], freezeTokens: 1, calendar: calendar, now: now)
        XCTAssertEqual(result.streak, 2) // Jun 10 + bridged Jun 9 + Jun 8, stop at Jun 7
        XCTAssertEqual(result.consumedDay, key(date(2025, 6, 9)))
        XCTAssertEqual(result.usedFrozenCount, 1)
    }

    // MARK: - Heatmap week alignment boundaries

    func testHeatmapSpansExactlyTwelveMondayAlignedWeeks() {
        let days = VocalLogic.buildEmptyHeatmap(dayCount: 84)
        guard days.count == 84 else { return XCTFail("expected 84 cells") }

        // First cell: Monday exactly 11 weeks before this week's Monday.
        let today = calendar.startOfDay(for: Date())
        let thisMonday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let expectedStart = calendar.date(byAdding: .weekOfYear, value: -11, to: thisMonday)!
        XCTAssertEqual(calendar.startOfDay(for: days[0].date), expectedStart)
        XCTAssertEqual(calendar.component(.weekday, from: days[0].date), 2) // Monday

        // Last cell: exactly 83 days after the start (inside the current week).
        let expectedLast = calendar.date(byAdding: .day, value: 83, to: expectedStart)!
        XCTAssertEqual(calendar.startOfDay(for: days[83].date), expectedLast)

        // 84 cells = 12 weeks x 7 weekdays: exactly 12 cells per weekday column.
        var weekdayCounts: [Int: Int] = [:]
        for day in days {
            weekdayCounts[calendar.component(.weekday, from: day.date), default: 0] += 1
        }
        XCTAssertTrue(weekdayCounts.values.allSatisfy { $0 == 12 }, "\(weekdayCounts)")
    }

    func testHeatmapIntensityClamp() {
        // Counts above 3 clamp to full intensity.
        let today = Date()
        let todayKey = VocalLogic.practiceDayKey(for: today)
        let days = VocalLogic.buildHeatmap(dayCounts: [todayKey: 99], dayCount: 84)
        let cell = days.first { $0.dayKey == todayKey }
        XCTAssertNotNil(cell)
        XCTAssertEqual(cell?.intensity, 1.0)
        XCTAssertEqual(cell?.count, 99)
    }

    // MARK: - Iteration cap

    func testStreakCappedAtOneYearOfIterations() {
        let now = Date()
        var days = Set<String>()
        for offset in 0...400 {
            if let d = calendar.date(byAdding: .day, value: -offset, to: now) {
                days.insert(VocalLogic.practiceDayKey(for: d))
            }
        }
        let result = VocalLogic.calculateStreak(practiceDays: days, frozenDays: [], freezeTokens: 0, calendar: calendar, now: now)
        // The walk is bounded by the 366-iteration guard; it must terminate
        // (no hang) and never report more than 366 days.
        XCTAssertLessThanOrEqual(result.streak, 366)
        XCTAssertGreaterThan(result.streak, 360)
    }
}
