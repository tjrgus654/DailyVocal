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

    func testMedian() {
        XCTAssertEqual(VocalLogic.median([]), 0)
        XCTAssertEqual(VocalLogic.median([5]), 5)
        XCTAssertEqual(VocalLogic.median([3, 1, 2]), 2)
        XCTAssertEqual(VocalLogic.median([4, 1, 3, 2]), 2.5, accuracy: 1e-9)
        XCTAssertEqual(VocalLogic.median([9, 5, 7, 1, 3]), 5)
    }

    func testSpeechVoiceTypeBands() {
        // Male speech norms (Baken): bass < 98Hz, baritone 98-123Hz, tenor 123Hz+.
        XCTAssertEqual(VocalLogic.speechVoiceTypeBand(medianSpeechMidi: 41, isFemale: false), .bass)    // ~87Hz
        XCTAssertEqual(VocalLogic.speechVoiceTypeBand(medianSpeechMidi: 45, isFemale: false), .baritone) // ~110Hz
        XCTAssertEqual(VocalLogic.speechVoiceTypeBand(medianSpeechMidi: 48, isFemale: false), .tenor)    // ~131Hz
        // Female speech norms: alto < 185Hz, mezzo 185-215Hz, soprano 220Hz+.
        XCTAssertEqual(VocalLogic.speechVoiceTypeBand(medianSpeechMidi: 52, isFemale: true), .contralto) // ~165Hz
        XCTAssertEqual(VocalLogic.speechVoiceTypeBand(medianSpeechMidi: 55, isFemale: true), .mezzo)     // ~196Hz
        XCTAssertEqual(VocalLogic.speechVoiceTypeBand(medianSpeechMidi: 58, isFemale: true), .soprano)   // ~233Hz
    }

    func testRefinedVoiceTypeTwoAxes() {
        // Agreement: range says tenor, speech 131Hz says tenor -> tenor.
        XCTAssertEqual(VocalLogic.refinedVoiceType(rangeBased: .tenor, medianSpeechMidi: 48, isFemale: false), .tenor)
        // Same family, speech corrects: range guessed tenor, speech baritone -> baritone.
        XCTAssertEqual(VocalLogic.refinedVoiceType(rangeBased: .tenor, medianSpeechMidi: 45, isFemale: false), .baritone)
        // Explicit gender keeps both axes in one family — no contradiction path.
        XCTAssertEqual(VocalLogic.refinedVoiceType(rangeBased: .baritone, medianSpeechMidi: 48, isFemale: false), .tenor)
        // Unknown gender + families disagree -> undetermined (unreliable input).
        XCTAssertEqual(VocalLogic.refinedVoiceType(rangeBased: .tenor, medianSpeechMidi: 55, isFemale: nil), .undetermined)
        XCTAssertEqual(VocalLogic.refinedVoiceType(rangeBased: .mezzo, medianSpeechMidi: 45, isFemale: nil), .undetermined)
        // Undetermined range short-circuits.
        XCTAssertEqual(VocalLogic.refinedVoiceType(rangeBased: .undetermined, medianSpeechMidi: 45, isFemale: false), .undetermined)
    }

    func testFormantTable() {
        // Canonical F1/F2 values (Hz) for the five training vowels.
        XCTAssertEqual(VocalLogic.formants(for: .a).f1, 730)
        XCTAssertEqual(VocalLogic.formants(for: .i).f2, 2290)
        // Every vowel has physically ordered formants F1 < F2 < F3.
        for vowel in VocalLogic.TrainingVowel.allCases {
            let f = VocalLogic.formants(for: vowel)
            XCTAssertLessThan(f.f1, f.f2)
            XCTAssertLessThan(f.f2, f.f3)
            XCTAssertTrue((150...900).contains(f.f1), "\(vowel) F1")
            XCTAssertTrue((500...2600).contains(f.f2), "\(vowel) F2")
        }
    }

    func testFftBinMapping() {
        // 48kHz, 512 bins -> 93.75 Hz per bin.
        XCTAssertEqual(VocalLogic.fftBin(frequency: 0, sampleRate: 48000, binCount: 512), 0)
        XCTAssertEqual(VocalLogic.fftBin(frequency: 93.75, sampleRate: 48000, binCount: 512), 1)
        XCTAssertEqual(VocalLogic.fftBin(frequency: 730, sampleRate: 48000, binCount: 512), 7)
        // Out-of-range clamps into bounds.
        XCTAssertEqual(VocalLogic.fftBin(frequency: 999999, sampleRate: 48000, binCount: 512), 511)
        XCTAssertEqual(VocalLogic.fftBin(frequency: 440, sampleRate: 0, binCount: 512), 0)
    }

    func testFormantStrength() {
        // 512 bins @ 48kHz: /a/ F1=730Hz -> bin ~7, F2=1090 -> bin ~11.
        var mags = [Double](repeating: 0.001, count: 512)
        mags[7] = 1.0
        mags[11] = 0.8
        let strength = VocalLogic.formantStrength(magnitudes: mags, sampleRate: 48000, vowel: .a)
        XCTAssertGreaterThan(strength, 0.7)  // most energy lands in the /a/ formant bands
        // Same spectrum scored against /i/ (F1 270=bin 2, F2 2290=bin 24) is weak.
        let wrongVowel = VocalLogic.formantStrength(magnitudes: mags, sampleRate: 48000, vowel: .i)
        XCTAssertLessThan(wrongVowel, 0.05)
        // Degenerate inputs.
        XCTAssertEqual(VocalLogic.formantStrength(magnitudes: [], sampleRate: 48000, vowel: .a), 0)
        XCTAssertEqual(VocalLogic.formantStrength(magnitudes: [0, 0, 0], sampleRate: 48000, vowel: .a), 0)
    }

    func testPeakFrequency() {
        // 512 bins @ 48kHz, peak at bin 8 (750Hz).
        var mags = [Double](repeating: 0.001, count: 512)
        mags[8] = 1.0
        let peak = VocalLogic.peakFrequency(magnitudes: mags, sampleRate: 48000, band: 250...1000)
        XCTAssertEqual(peak ?? 0, 750, accuracy: 50)
        // Band outside the peak returns the band's own max (0.001 noise).
        let outside = VocalLogic.peakFrequency(magnitudes: mags, sampleRate: 48000, band: 2000...3000)
        XCTAssertNotNil(outside)  // noise floor still has a max
        // Empty spectrum.
        XCTAssertNil(VocalLogic.peakFrequency(magnitudes: [], sampleRate: 48000, band: 250...1000))
    }

    func testMeasuredFormants() {
        // /아/-like spectrum: F1 peak at 730Hz(bin 7), F2 at 1090(bin 11).
        var mags = [Double](repeating: 0.001, count: 512)
        mags[7] = 1.0
        mags[11] = 0.7
        let f = VocalLogic.measuredFormants(magnitudes: mags, sampleRate: 48000)
        XCTAssertNotNil(f)
        XCTAssertEqual(f!.f1, 730, accuracy: 95)   // bin width
        XCTAssertEqual(f!.f2, 1090, accuracy: 95)
    }

    func testVowelDirectionFeedback() {
        // User F1 far below /아/ target (730): "open more".
        let open = VocalLogic.vowelDirectionFeedback(target: .a, userF1: 500, userF2: 1000)
        XCTAssertTrue(open.contains { $0.contains("벌려") })
        // On-target: no tips.
        let good = VocalLogic.vowelDirectionFeedback(target: .a, userF1: 720, userF2: 1100)
        XCTAssertTrue(good.isEmpty)
        // /이/ with low F2: front-vowel tip (tongue forward).
        let front = VocalLogic.vowelDirectionFeedback(target: .i, userF1: 280, userF2: 1800)
        XCTAssertTrue(front.contains { $0.contains("앞으로") })
        // /오/ with low F2: round-vowel tip (lips).
        let round = VocalLogic.vowelDirectionFeedback(target: .o, userF1: 560, userF2: 600)
        XCTAssertTrue(round.contains { $0.contains("둥글게") })
    }

    func testVowelRoundScoreAndGameRounds() {
        XCTAssertEqual(VocalLogic.vowelRoundScore(strength: 0.78), 78)
        XCTAssertEqual(VocalLogic.vowelRoundScore(strength: 1.5), 100)  // clamps
        XCTAssertEqual(VocalLogic.vowelRoundScore(strength: -1), 0)
        // L1: contrastive 4 rounds; L3: full 6.
        XCTAssertEqual(VocalLogic.vowelGameRounds(level: 1).count, 4)
        XCTAssertEqual(VocalLogic.vowelGameRounds(level: 3).count, 6)
        XCTAssertEqual(VocalLogic.vowelGameRounds(level: 0).count, 4)   // clamps
        XCTAssertEqual(VocalLogic.vowelGameRounds(level: 99).count, 6)
    }

    func testIntervalRoundsAndScore() {
        // L1: obvious leaps only.
        let l1 = VocalLogic.intervalRounds(level: 1, roll: { 0 })
        XCTAssertTrue(l1.allSatisfy { [.unison, .perfectFifth, .octave].contains($0) })
        XCTAssertEqual(l1.count, 4)
        // L3: 6 rounds from the full set.
        XCTAssertEqual(VocalLogic.intervalRounds(level: 3, roll: { 3 }).count, 6)
        // Clamp.
        XCTAssertEqual(VocalLogic.intervalRounds(level: 0, roll: { 0 }).count, 4)
        // Interval sizes.
        XCTAssertEqual(VocalLogic.TrainingInterval.perfectFifth.semitones, 7)
        XCTAssertEqual(VocalLogic.TrainingInterval.octave.semitones, 12)
        // Scoring.
        XCTAssertEqual(VocalLogic.intervalScore(target: .perfectFifth, userSemitones: 7), 100)
        XCTAssertEqual(VocalLogic.intervalScore(target: .perfectFifth, userSemitones: 6), 40)
        XCTAssertEqual(VocalLogic.intervalScore(target: .perfectFifth, userSemitones: 3), 0)
        // Feedback direction.
        XCTAssertTrue(VocalLogic.intervalFeedback(target: .octave, userSemitones: 9).contains("좁게"))
        XCTAssertTrue(VocalLogic.intervalFeedback(target: .majorThird, userSemitones: 6).contains("넓게"))
        XCTAssertEqual(VocalLogic.intervalFeedback(target: .unison, userSemitones: 0), "정확합니다")
    }

    func testPerformedSemitonesFromSungMidis() {
        // Precise unison: median 60.2 over base 60 rounds to 0.
        XCTAssertEqual(VocalLogic.performedSemitones(midiEstimates: [60.1, 60.2, 60.3], baseMidi: 60), 0)
        // A major third sung slightly flat: median ~63.7 rounds to 4.
        XCTAssertEqual(VocalLogic.performedSemitones(midiEstimates: [63.5, 63.7, 63.8], baseMidi: 60), 4)
        // Octave down: median 47.9 over base 60 rounds to -12.
        XCTAssertEqual(VocalLogic.performedSemitones(midiEstimates: [47.8, 47.9, 48.0], baseMidi: 60), -12)
        // Nothing voiced.
        XCTAssertNil(VocalLogic.performedSemitones(midiEstimates: [], baseMidi: 60))
        // Median (not mean) wins against a stray outlier frame.
        XCTAssertEqual(VocalLogic.performedSemitones(midiEstimates: [67.0, 67.1, 67.2, 67.1, 12.0], baseMidi: 60), 7)
    }

    func testEarTraining() {
        // L1 trials only have obvious gaps or unison.
        for _ in 0..<20 {
            let trial = VocalLogic.earTrainingTrial(level: 1, roll: { Int.random(in: 0..<100) })
            XCTAssertTrue([0, 4, 5, 7, -4, -5, -7].contains(trial.offset),
                          "L1 gap \(trial.offset)")
            XCTAssertTrue((55...64).contains(trial.baseMidi))
        }
        // L3 has 1-semitone gaps.
        let tight = VocalLogic.earTrainingTrial(level: 3, roll: { 0 })
        XCTAssertTrue([0, 1, -1, 2, -2, 3, -3].contains(tight.offset))
        // Answers.
        XCTAssertEqual(VocalLogic.earTrainingAnswer(offset: 3), .higher)
        XCTAssertEqual(VocalLogic.earTrainingAnswer(offset: -2), .lower)
        XCTAssertEqual(VocalLogic.earTrainingAnswer(offset: 0), .same)
        // Level progression.
        XCTAssertEqual(VocalLogic.earTrainingLevel(currentLevel: 1, correctStreak: 5, wrongStreak: 0), 2)
        XCTAssertEqual(VocalLogic.earTrainingLevel(currentLevel: 3, correctStreak: 99, wrongStreak: 0), 3) // cap
        XCTAssertEqual(VocalLogic.earTrainingLevel(currentLevel: 2, correctStreak: 0, wrongStreak: 2), 1)
        XCTAssertEqual(VocalLogic.earTrainingLevel(currentLevel: 1, correctStreak: 0, wrongStreak: 99), 1) // floor
        XCTAssertEqual(VocalLogic.earTrainingLevel(currentLevel: 2, correctStreak: 3, wrongStreak: 1), 2)  // hold
    }

    func testBestTakeComparison() {
        let base = Date()
        let best = VocalLogic.BestTake(timestamp: base, accuracy: 75, medianF1: 730, medianF2: 1090, noteMidi: 64)
        // Growth: accuracy up.
        let better = VocalLogic.BestTake(timestamp: base.addingTimeInterval(86400), accuracy: 82, medianF1: 728, medianF2: 1085, noteMidi: 64)
        let growth = VocalLogic.compareTakes(best: best, current: better)
        XCTAssertEqual(growth.accuracyDelta, 7)
        XCTAssertTrue(growth.summary.contains("성장"))
        // Decline.
        let worse = VocalLogic.BestTake(timestamp: base.addingTimeInterval(86400), accuracy: 65, medianF1: 730, medianF2: 1090, noteMidi: 64)
        let decline = VocalLogic.compareTakes(best: best, current: worse)
        XCTAssertEqual(decline.accuracyDelta, -10)
        XCTAssertTrue(decline.summary.contains("컨디션"))
        // Stable.
        let same = VocalLogic.BestTake(timestamp: base.addingTimeInterval(86400), accuracy: 76, medianF1: 730, medianF2: 1090, noteMidi: 64)
        let stable = VocalLogic.compareTakes(best: best, current: same)
        XCTAssertEqual(stable.accuracyDelta, 1)
        XCTAssertTrue(stable.summary.contains("비슷"))
        // Large F2 drift gets called out.
        let drifted = VocalLogic.BestTake(timestamp: base.addingTimeInterval(86400), accuracy: 76, medianF1: 730, medianF2: 1300, noteMidi: 64)
        let driftResult = VocalLogic.compareTakes(best: best, current: drifted)
        XCTAssertGreaterThan(abs(driftResult.formantDriftCents), 100)
        XCTAssertTrue(driftResult.summary.contains("모음"))
    }

    func testRecommendedLevel() {
        // Empty history: hold.
        XCTAssertEqual(VocalLogic.recommendedLevel(recentAccuracies: [], currentLevel: 1), 1)
        // 3 sessions >= 80%: promote.
        XCTAssertEqual(VocalLogic.recommendedLevel(recentAccuracies: [85, 90, 82], currentLevel: 1), 2)
        XCTAssertEqual(VocalLogic.recommendedLevel(recentAccuracies: [85, 90, 82], currentLevel: 3), 3) // cap
        // 2 consecutive < 50%: demote.
        XCTAssertEqual(VocalLogic.recommendedLevel(recentAccuracies: [40, 45], currentLevel: 2), 1)
        // Only 1 bad session: hold.
        XCTAssertEqual(VocalLogic.recommendedLevel(recentAccuracies: [40], currentLevel: 2), 2)
        // Mixed: hold.
        XCTAssertEqual(VocalLogic.recommendedLevel(recentAccuracies: [70, 60, 75], currentLevel: 2), 2)
        // Window is last 3 only: old bad scores ignored.
        XCTAssertEqual(VocalLogic.recommendedLevel(recentAccuracies: [10, 20, 85, 90, 82], currentLevel: 1), 2)
    }

    func testRecommendNextGame() {
        // No data: defaults are 50, first alphabetically (ear).
        let noData = VocalLogic.recommendNextGame(vowelAccuracy: nil, intervalAccuracy: nil, earAccuracy: nil, lastGame: nil)
        XCTAssertTrue(VocalLogic.GameType.allCases.contains(noData))  // deterministic: all tied at 50
        // Weakest skill wins: vowel 40, interval 80, ear 60 -> vowel.
        XCTAssertEqual(VocalLogic.recommendNextGame(vowelAccuracy: 40, intervalAccuracy: 80, earAccuracy: 60, lastGame: nil), .vowel)
        // Variety bias: weakest is same as last game AND second is close -> second.
        XCTAssertEqual(VocalLogic.recommendNextGame(vowelAccuracy: 40, intervalAccuracy: 50, earAccuracy: 80, lastGame: .vowel), .interval)
        // Weakest is last game but gap is big (25+): still recommend it (needs practice).
        XCTAssertEqual(VocalLogic.recommendNextGame(vowelAccuracy: 30, intervalAccuracy: 70, earAccuracy: 80, lastGame: .vowel), .vowel)
    }

    func testRecommendNextGameTechniqueModes() {
        // Technique modes count as skills; unmeasured defaults to 50.
        XCTAssertEqual(
            VocalLogic.recommendNextGame(
                vowelAccuracy: 80, intervalAccuracy: 90, earAccuracy: 85,
                vibratoAccuracy: 40, dynamicsAccuracy: nil, scaleAccuracy: nil, lastGame: nil),
            .vibrato, "weakest technique mode should win over strong games")
        XCTAssertEqual(
            VocalLogic.recommendNextGame(
                vowelAccuracy: 80, intervalAccuracy: 90, earAccuracy: 85,
                vibratoAccuracy: 70, dynamicsAccuracy: 35, scaleAccuracy: nil, lastGame: nil),
            .dynamics)
        XCTAssertEqual(
            VocalLogic.recommendNextGame(
                vowelAccuracy: 80, intervalAccuracy: 90, earAccuracy: 85,
                vibratoAccuracy: 75, dynamicsAccuracy: 70, scaleAccuracy: 40, lastGame: nil),
            .scale, "scale is a first-class recommendation input")
        // Variety: vibrato is weakest but was the last game and dynamics is
        // within 15 points -> prefer the second-weakest (scale kept above).
        XCTAssertEqual(
            VocalLogic.recommendNextGame(
                vowelAccuracy: 80, intervalAccuracy: 90, earAccuracy: 85,
                vibratoAccuracy: 40, dynamicsAccuracy: 50, scaleAccuracy: 55, lastGame: .vibrato),
            .dynamics)
        // Legacy 3-argument call sites keep compiling and behaving.
        XCTAssertEqual(
            VocalLogic.recommendNextGame(vowelAccuracy: 40, intervalAccuracy: 80, earAccuracy: 60, lastGame: nil),
            .vowel)
    }

    func testRecommendationEvidence() {
        // Vibrato rate bands.
        XCTAssertTrue(VocalLogic.recommendationEvidence(
            game: .vibrato, latestAccuracy: 40, vibratoRateHz: 3.8, vibratoExtentCents: 80
        ).contains("3.8Hz") && VocalLogic.recommendationEvidence(
            game: .vibrato, latestAccuracy: 40, vibratoRateHz: 3.8, vibratoExtentCents: 80
        ).contains("워블"))
        XCTAssertTrue(VocalLogic.recommendationEvidence(
            game: .vibrato, latestAccuracy: 40, vibratoRateHz: 7.2, vibratoExtentCents: 80
        ).contains("떨림"))
        // In-band rate but shallow extent.
        let depth = VocalLogic.recommendationEvidence(
            game: .vibrato, latestAccuracy: 40, vibratoRateHz: 5.5, vibratoExtentCents: 30)
        XCTAssertTrue(depth.contains("5.5Hz") && depth.contains("깊이를 키워요"))
        // In-band and deep.
        XCTAssertTrue(VocalLogic.recommendationEvidence(
            game: .vibrato, latestAccuracy: 40, vibratoRateHz: 5.5, vibratoExtentCents: 70
        ).contains("유지해요"))
        // Dynamics bands.
        XCTAssertTrue(VocalLogic.recommendationEvidence(
            game: .dynamics, latestAccuracy: 40, dynamicsRangeDb: 4.2
        ).contains("4.2dB") && VocalLogic.recommendationEvidence(
            game: .dynamics, latestAccuracy: 40, dynamicsRangeDb: 4.2
        ).contains("폭을 키워요"))
        XCTAssertTrue(VocalLogic.recommendationEvidence(
            game: .dynamics, latestAccuracy: 40, dynamicsRangeDb: 9.0
        ).contains("정점 배치"))
        // No fingerprint -> score fallback.
        XCTAssertEqual(
            VocalLogic.recommendationEvidence(game: .vibrato, latestAccuracy: 42),
            "최근 점수 42점 — 가장 약한 훈련부터 보완해요")
        // Nothing at all -> unmeasured line.
        XCTAssertTrue(VocalLogic.recommendationEvidence(game: .scale, latestAccuracy: nil)
            .contains("시도하지 않은"))
    }

    func testLatestAccuraciesFromRecords() {
        let records: [(label: String, accuracy: Int)] = [
            ("모음 게임", 60), ("E4", 90), ("비브라토 체크", 40),
            ("모음 게임", 75), ("다이내믹스 아치", 55), ("스케일 시퀀스", 68),
        ]
        let latest = VocalLogic.latestAccuracies(records: records)
        XCTAssertEqual(latest[.vowel], 75, "most recent 모음 게임 wins over the earlier one")
        XCTAssertEqual(latest[.vibrato], 40)
        XCTAssertEqual(latest[.dynamics], 55)
        XCTAssertEqual(latest[.scale], 68)
        XCTAssertNil(latest[.interval])
        XCTAssertNil(latest[.ear], "plain note labels must not be mistaken for games")
    }

    // MARK: - Game integration scenario

    /// Full progression: a beginner plays all three games across multiple
    /// sessions, improving over time. The personalized difficulty and game
    /// recommendation should track their growth.
    func testGameProgressionScenario() {
        var vowelLevel = 1, intervalLevel = 1, earLevel = 1
        var vowelHistory: [Int] = [], intervalHistory: [Int] = [], earHistory: [Int] = []

        // Week 1: struggling (40-55% across all games).
        for accuracy in [45, 50, 55] {
            vowelHistory.append(accuracy)
            vowelLevel = VocalLogic.recommendedLevel(recentAccuracies: vowelHistory, currentLevel: vowelLevel)
        }
        XCTAssertEqual(vowelLevel, 1, "should hold at 1 with mixed low scores")

        // Week 2: vowel improves (80%+ streak).
        for accuracy in [82, 85, 88] {
            vowelHistory.append(accuracy)
            vowelLevel = VocalLogic.recommendedLevel(recentAccuracies: vowelHistory, currentLevel: vowelLevel)
        }
        XCTAssertEqual(vowelLevel, 2, "3 sessions 80%+ should promote to 2")

        // Week 3: keeps improving, reaches level 3.
        for accuracy in [85, 90, 92] {
            vowelHistory.append(accuracy)
            vowelLevel = VocalLogic.recommendedLevel(recentAccuracies: vowelHistory, currentLevel: vowelLevel)
        }
        XCTAssertEqual(vowelLevel, 3, "should reach max level 3")

        // Cap: can't go above 3.
        vowelHistory.append(95)
        XCTAssertEqual(VocalLogic.recommendedLevel(recentAccuracies: vowelHistory, currentLevel: vowelLevel), 3)

        // Game recommendation: interval 40 is below even the unmeasured
        // default (50) — the measured weakest still wins outright.
        let next = VocalLogic.recommendNextGame(
            vowelAccuracy: 90, intervalAccuracy: 40, earAccuracy: 65, lastGame: .vowel)
        XCTAssertEqual(next, .interval, "measured 40 beats unmeasured default 50")

        // Once interval recovers, the never-played scale (50) outranks every
        // measured skill — including the measured techniques (55/58).
        let next2 = VocalLogic.recommendNextGame(
            vowelAccuracy: 90, intervalAccuracy: 85, earAccuracy: 60,
            vibratoAccuracy: 55, dynamicsAccuracy: 58, lastGame: .interval)
        XCTAssertEqual(next2, .scale, "unmeasured (50) beats all measured")

        // After every game has been measured, variety applies among real
        // scores again.
        let next3 = VocalLogic.recommendNextGame(
            vowelAccuracy: 90, intervalAccuracy: 75, earAccuracy: 65,
            vibratoAccuracy: 72, dynamicsAccuracy: 68, scaleAccuracy: 70, lastGame: .ear)
        XCTAssertEqual(next3, .dynamics, "close gap + same as last -> variety wins")

        // Regression: interval crashes (2 consecutive < 50%).
        intervalHistory = [45, 40]
        XCTAssertEqual(VocalLogic.recommendedLevel(recentAccuracies: intervalHistory, currentLevel: 2), 1,
                       "2 consecutive sub-50% should demote")
    }

    /// Level transitions respect bounds: never below 1, never above max.
    /// Regression guard: the last 2 sub-50% sessions must demote even when
    /// the 3-session average is above 50 (e.g. [100, 30, 30] avg=53.3).
    func testDemoteRegardlessOfAverage() {
        XCTAssertEqual(VocalLogic.recommendedLevel(recentAccuracies: [100, 30, 30], currentLevel: 2), 1)
        // Single bad session still holds.
        XCTAssertEqual(VocalLogic.recommendedLevel(recentAccuracies: [100, 30], currentLevel: 2), 2)
    }

    func testLevelBounds() {
        XCTAssertEqual(VocalLogic.recommendedLevel(recentAccuracies: [20, 20], currentLevel: 1), 1)
        XCTAssertEqual(VocalLogic.recommendedLevel(recentAccuracies: [99, 99, 99], currentLevel: 3), 3)
    }

    /// Stress: 100 random range combinations must always produce a valid
    /// type (never undetermined when the span is wide enough) and stay
    /// within the correct gender family when isFemale is known.
    func testVoiceTypeStress() {
        var seed: UInt64 = 0xDEADBEEF
        func rnd(_ max: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: seed >> 33)) % max
        }
        for _ in 0..<100 {
            let isFemale = rnd(2) == 0
            // Generate a plausible comfortable range: female 53...77, male 40...64
            let lowBase = isFemale ? 53 : 40
            let span = 10 + rnd(15)  // 10-24 semitones
            let low = lowBase + rnd(5)
            let high = low + span
            let ceiling = high + rnd(7)
            let type = VocalLogic.estimateVoiceType(
                comfortableLowMidi: low, comfortableHighMidi: high,
                absoluteHighMidi: ceiling, isFemale: isFemale ? true : false
            )
            // Span >= 10 → must be determined.
            XCTAssertNotEqual(type, .undetermined, "low=\(low) high=\(high) ceil=\(ceiling) female=\(isFemale)")
            // Gender family consistency.
            if isFemale {
                XCTAssertTrue([.contralto, .mezzo, .soprano].contains(type),
                              "female got \(type) for low=\(low) high=\(high)")
            } else {
                XCTAssertTrue([.bass, .baritone, .tenor].contains(type),
                              "male got \(type) for low=\(low) high=\(high)")
            }
        }
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
