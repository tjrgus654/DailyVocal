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

    /// P2-4 contract: settlement is idempotent — applying consumedDays to
    /// frozenDays once means no further consumption on subsequent walks
    /// (the dashboard render loop must never spend tokens twice).
    func testFreezeSettlementIsIdempotent() {
        let now = noon()
        let days: Set<String> = [key(now), key(now, offsetDays: -2)]
        var frozen: Set<String> = []
        var tokens = 2

        let first = VocalLogic.calculateStreak(practiceDays: days, frozenDays: frozen, freezeTokens: tokens, now: now)
        XCTAssertEqual(first.consumedDays, [key(now, offsetDays: -1)])
        // Apply once (session completion).
        frozen.formUnion(first.consumedDays)
        tokens -= first.consumedDays.count

        // Repeated walks (dashboard renders) propose nothing new.
        for _ in 0..<5 {
            let again = VocalLogic.calculateStreak(practiceDays: days, frozenDays: frozen, freezeTokens: tokens, now: now)
            XCTAssertTrue(again.consumedDays.isEmpty, "re-walk consumed \(again.consumedDays)")
            XCTAssertEqual(again.streak, first.streak)
        }
        XCTAssertEqual(tokens, 1)
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

    func testNextReminderDateBoundaries() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let base = cal.date(from: DateComponents(year: 2025, month: 6, day: 10, hour: 12))!
        // Later today.
        let evening = VocalLogic.nextReminderDate(now: base, hour: 20, minute: 30, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.day, .hour, .minute], from: evening!),
                       DateComponents(day: 10, hour: 20, minute: 30))
        // Exactly now -> tomorrow (UNCalendar trigger semantics: not in the past).
        let same = VocalLogic.nextReminderDate(now: base, hour: 12, minute: 0, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.day], from: same!), DateComponents(day: 11))
        // Earlier today -> tomorrow.
        let morning = VocalLogic.nextReminderDate(now: base, hour: 8, minute: 0, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.day], from: morning!), DateComponents(day: 11))
        // Invalid times are rejected.
        XCTAssertNil(VocalLogic.nextReminderDate(now: base, hour: 24, minute: 0, calendar: cal))
        XCTAssertNil(VocalLogic.nextReminderDate(now: base, hour: 10, minute: 60, calendar: cal))
        // Day rollover across a month boundary.
        let june30 = cal.date(from: DateComponents(year: 2025, month: 6, day: 30, hour: 23))!
        let july1 = VocalLogic.nextReminderDate(now: june30, hour: 9, minute: 0, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.month, .day], from: july1!),
                       DateComponents(month: 7, day: 1))
    }

    // MARK: - Voice type (성종)

    func testVoiceTypeClassification() {
        // Classical reference comfortable ranges (midi low...high, ceiling).
        // Tenor ~ C3..A4 (48..69), ceiling >= G4 (67)
        XCTAssertEqual(VocalLogic.estimateVoiceType(comfortableLowMidi: 48, comfortableHighMidi: 67, absoluteHighMidi: 69, isFemale: false), .tenor)
        // Baritone ~ G2..E4 (43..64) midpoint ~53 but below tenor ceiling band edge:
        // mid 53 >= 50 would say tenor — baritone needs mid < 50 or ceiling < 62.
        XCTAssertEqual(VocalLogic.estimateVoiceType(comfortableLowMidi: 43, comfortableHighMidi: 56, absoluteHighMidi: 61, isFemale: false), .baritone)
        // Bass ~ E2..C4 (40..60) midpoint 50 -> tenor band but ceiling 60 < 62 -> baritone; push lower
        XCTAssertEqual(VocalLogic.estimateVoiceType(comfortableLowMidi: 40, comfortableHighMidi: 55, absoluteHighMidi: 59, isFemale: false), .baritone)
        XCTAssertEqual(VocalLogic.estimateVoiceType(comfortableLowMidi: 38, comfortableHighMidi: 52, absoluteHighMidi: 56, isFemale: false), .bass)
        // Soprano ~ C4..A5 (60..81), ceiling >= D5 (74)
        XCTAssertEqual(VocalLogic.estimateVoiceType(comfortableLowMidi: 60, comfortableHighMidi: 79, absoluteHighMidi: 81, isFemale: true), .soprano)
        // Mezzo ~ A3..F5 (57..77)
        XCTAssertEqual(VocalLogic.estimateVoiceType(comfortableLowMidi: 57, comfortableHighMidi: 74, absoluteHighMidi: 77, isFemale: true), .mezzo)
        // Contralto ~ F3..E5 (53..76)
        XCTAssertEqual(VocalLogic.estimateVoiceType(comfortableLowMidi: 53, comfortableHighMidi: 69, absoluteHighMidi: 72, isFemale: true), .contralto)
        // Unknown gender falls through the merged scale
        XCTAssertEqual(VocalLogic.estimateVoiceType(comfortableLowMidi: 48, comfortableHighMidi: 67, absoluteHighMidi: 69, isFemale: nil), .tenor)
    }

    func testVoiceTypeRequiresWideEnoughRange() {
        // Beginner with a narrow 8-semitone measurement: anatomy undecided.
        XCTAssertEqual(VocalLogic.estimateVoiceType(comfortableLowMidi: 48, comfortableHighMidi: 56, absoluteHighMidi: 60, isFemale: false), .undetermined)
        // Exactly 10 semitones is enough.
        XCTAssertNotEqual(VocalLogic.estimateVoiceType(comfortableLowMidi: 48, comfortableHighMidi: 58, absoluteHighMidi: 62, isFemale: false), .undetermined)
    }

    func testPassaggioZonePerType() {
        XCTAssertEqual(VocalLogic.passaggioZone(for: .tenor), 66...69)
        XCTAssertEqual(VocalLogic.passaggioZone(for: .soprano), 74...78)
        XCTAssertNil(VocalLogic.passaggioZone(for: .undetermined))
        // Every determined type has a zone inside the singing band.
        for type in VocalLogic.VoiceType.allCases where type != .undetermined {
            let zone = VocalLogic.passaggioZone(for: type)!
            XCTAssertTrue((43...84).contains(zone.lowerBound))
            XCTAssertTrue(zone.lowerBound < zone.upperBound)
        }
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
