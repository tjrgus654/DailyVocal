//
//  VocalLogic.swift
//  DailyVocal
//
//  Pure, Foundation-only decision logic shared by the app AND by the
//  cross-platform unit tests (swift test on Windows/macOS). No UIKit,
//  AVFoundation or SwiftUI imports are allowed in this file.
//

import Foundation

/// Namespace for the pure logic: note math, streak system, heatmap layout,
/// echo-sequence design and session grading.
public enum VocalLogic {

    // MARK: - Note <-> frequency (A4-calibratable)

    public static let standardA4 = 440.0

    public static func midiNumber(forFrequency frequency: Double, a4: Double = standardA4) -> Double {
        guard frequency > 0 else { return 0 }
        return 69.0 + 12.0 * log2(frequency / a4)
    }

    public static func frequency(forMidi midi: Double, a4: Double = standardA4) -> Double {
        a4 * pow(2.0, (midi - 69.0) / 12.0)
    }

    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    public static func noteAndCents(fromFrequency frequency: Double, a4: Double = standardA4) -> (note: String, midi: Int, cents: Double) {
        guard frequency > 0 else { return ("--", 0, 0) }
        let exact = midiNumber(forFrequency: frequency, a4: a4)
        let midi = Int(exact.rounded())
        let cents = (exact - Double(midi)) * 100.0
        let name = noteNames[(midi % 12 + 12) % 12]
        let octave = midi / 12 - 1
        return ("\(name)\(octave)", midi, cents)
    }

    /// Parses note names like "C4", "F#3" into a MIDI number.
    public static func midiNumber(forNoteName name: String) -> Int? {
        let letters: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var base = 0
        var foundBase = false
        var accidental = 0
        var octave: Int?

        for char in name.trimmingCharacters(in: .whitespaces) {
            if char.isNumber {
                if let digit = char.wholeNumberValue {
                    octave = (octave ?? 0) * 10 + digit
                }
            } else if char == "#" {
                accidental += 1
            } else if char == "b" && foundBase {
                accidental -= 1
            } else if let value = letters[char] {
                base = value
                foundBase = true
            } else {
                return nil
            }
        }
        guard foundBase, let octave, (0...9).contains(octave) else { return nil }
        return (octave + 1) * 12 + base + accidental
    }

    // MARK: - Practice day (4 AM rollover) & streak

    /// POSIX/Gregorian-pinned so stored day keys (frozenDayKeys) survive
    /// user locale/calendar changes (Buddhist/Hijri would re-key the year).
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter
    }()

    /// A practice performed between 00:00 and 03:59 counts for the previous
    /// calendar day — late-night 연습 습관을 고려한 스트릭 기준.
    public static func practiceDayKey(for date: Date) -> String {
        dayFormatter.string(from: date.addingTimeInterval(-4 * 3600))
    }

    public struct StreakResult: Equatable {
        public var streak: Int
        /// Every gap the walk bridged with a token this pass; the caller must
        /// apply ALL of them in one update (a single-slot value let older
        /// gaps converge one render at a time).
        public var consumedDays: [String]
        public var usedFrozenCount: Int
        public init(streak: Int, consumedDays: [String], usedFrozenCount: Int) {
            self.streak = streak
            self.consumedDays = consumedDays
            self.usedFrozenCount = usedFrozenCount
        }
    }

    /// Consecutive practice days ending today (yesterday still counts while
    /// today isn't practiced yet). One missed day is bridged automatically by
    /// consuming a freeze token; two consecutive missed days end the streak.
    public static func calculateStreak(
        practiceDays: Set<String>,
        frozenDays: Set<String>,
        freezeTokens: Int,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> StreakResult {
        var streak = 0
        var tokens = freezeTokens
        var consumedDays: [String] = []
        var usedFrozenCount = 0

        // Anchor to the 4am-rollover "practice day" of now.
        var cursor = calendar.startOfDay(for: now.addingTimeInterval(-4 * 3600))

        // Streak stays alive until yesterday even if today isn't practiced yet.
        if !practiceDays.contains(dayFormatter.string(from: cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return StreakResult(streak: 0, consumedDays: [], usedFrozenCount: 0)
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
                consumedDays.append(key)
            } else {
                break
            }
            guard let previousDay else { break }
            cursor = previousDay
        }
        return StreakResult(streak: streak, consumedDays: consumedDays, usedFrozenCount: usedFrozenCount + consumedDays.count)
    }

    // MARK: - Heatmap (12 weeks, columns aligned to Mon..Sun)

    public static func buildHeatmap(dayCounts: [String: Int], dayCount: Int) -> [HeatmapDay] {
        buildDays(dayCount: dayCount, now: Date()) { key in
            let count = dayCounts[key, default: 0]
            return (count, heatmapIntensity(sessionCount: count))
        }
    }

    public static func buildEmptyHeatmap(dayCount: Int) -> [HeatmapDay] {
        buildDays(dayCount: dayCount, now: Date()) { _ in (0, 0) }
    }

    private static func buildDays(
        dayCount: Int,
        now: Date,
        content: (String) -> (count: Int, intensity: Double)
    ) -> [HeatmapDay] {
        // Round up to whole weeks: a partial trailing week would render
        // future cells as if they were empty past days.
        let dayCount = ((dayCount + 6) / 7) * 7
        // Pin the week start to Monday: the grid header hardcodes 월화수목금토일
        // while CLDR gives ko_KR/en_US a Sunday first weekday.
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)

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

    // MARK: - Echo sequence design (adaptive difficulty)

    /// Move pools per level (semitones). L1 ±2..3, L2 ±2..5, L3 ±2..7.
    public static let echoMoveSets: [[Int]] = [
        [-3, -2, 2, 3],
        [-5, -4, -3, -2, 2, 3, 4, 5],
        [-7, -5, -4, -3, 2, 3, 4, 5, 7]
    ]

    /// Random move for the current draw, kept inside the G2...C5 band so
    /// clamping can never fold two notes onto the same pitch.
    public static func generateEchoSequence(
        base: Int,
        level: Int,
        roll: () -> Int
    ) -> [Int] {
        let moves = echoMoveSets[min(3, max(1, level)) - 1]
        let clampedBase = min(72, max(43, base))
        let validFrom: (Int) -> [Int] = { from in
            moves.filter { (43...72).contains(from + $0) }
        }
        // roll() may return any Int: normalize so modulo never goes negative.
        func draw(_ pool: [Int]) -> Int {
            var r = roll() % pool.count
            if r < 0 { r += pool.count }
            return pool[r]
        }
        let baseMoves = validFrom(clampedBase)
        guard !baseMoves.isEmpty else { return [clampedBase, clampedBase + 2, clampedBase + 4] }
        let second = clampedBase + draw(baseMoves)
        let secondMoves = validFrom(second)
        guard !secondMoves.isEmpty else { return [clampedBase, second, second + 2] }
        let third = second + draw(secondMoves)
        return [clampedBase, second, third]
    }

    /// Stored-record label for an echo sequence: "C4-E4-G4" (empty when the
    /// list isn't a real 3-note sequence). Single sessions keep their note.
    public static func echoLabel(midis: [Int]) -> String {
        guard midis.count == 3 else { return "" }
        return midis
            .map { noteAndCents(fromFrequency: frequency(forMidi: Double($0))).note }
            .joined(separator: "-")
    }

    // MARK: - Guide-tone patterns & tuning clamp

    /// Semitone offsets of each guide pattern, anchored at the base note.
    /// Consumed by ScaleSequencer.Pattern.offsets for four cases; `.sirenSlide`
    /// intentionally shares the arpeggio shape (the sequencer maps it
    /// explicitly), kept here so every case has one canonical data source.
    public static func guidePattern(for tone: TonePatternType) -> [Int] {
        switch tone {
        case .sirenSlide: return [0, 4, 7, 12, 7, 4, 0]
        case .octaveJump: return [0, 12, 0]
        case .fiveToneScale: return [0, 2, 4, 5, 7, 5, 4, 2, 0]
        case .arpeggio: return [0, 4, 7, 12, 7, 4, 0]
        case .sustainedNote: return [0]
        }
    }

    /// Tuning reference clamp with the 0 = unset sentinel (standard pitch).
    public static func clampedA4(_ raw: Double) -> Double {
        guard raw != 0 else { return standardA4 }
        return min(445.0, max(435.0, raw))
    }

    /// One guide-tone note: the pattern offset transposed up `repetition`
    /// semitones per repeat (the ascending-transposition drill contract).
    public static func guideToneMidi(base: Int, repetition: Int, offset: Int) -> Int {
        base + repetition + offset
    }

    /// Full guide-tone note sequence for scheduling/contracts.
    public static func guideToneSequence(pattern: [Int], base: Int, repetitions: Int) -> [Int] {
        (0..<max(0, repetitions)).flatMap { rep in
            pattern.map { guideToneMidi(base: base, repetition: rep, offset: $0) }
        }
    }

    /// Vocal range growth in semitones vs the onboarding baseline.
    /// 0 Hz is the "not measured" sentinel and yields 0 (no garbage math).
    public static func rangeExpansionSemitones(baselineTopHz: Double, currentTopHz: Double) -> Int {
        guard baselineTopHz > 0, currentTopHz > 0 else { return 0 }
        return Int((midiNumber(forFrequency: currentTopHz) - midiNumber(forFrequency: baselineTopHz)).rounded())
    }

    /// Heatmap cell intensity: 3 sessions in a day saturate the cell.
    public static func heatmapIntensity(sessionCount: Int) -> Double {
        min(1.0, Double(sessionCount) / 3.0)
    }

    /// A step practiced for at least 70% of its duration counts as completed.
    public static func isStepCompleted(elapsedSeconds: Int, durationSeconds: Int) -> Bool {
        guard durationSeconds > 0 else { return false }
        return Double(elapsedSeconds) >= Double(durationSeconds) * 0.7
    }

    /// "N분 S초" / "S초" duration label (minutes hidden when zero).
    public static func durationLabel(seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return mins > 0 ? "\(mins)분 \(secs)초" : "\(secs)초"
    }

    /// Next fire date for a daily HH:MM reminder: today when the time is
    /// still ahead, otherwise tomorrow. Mirrors the UNCalendarNotificationTrigger
    /// repeat behavior for preview and testing.
    public static func nextReminderDate(now: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        guard let today = calendar.date(from: components) else { return nil }
        return today > now
            ? today
            : calendar.date(byAdding: .day, value: 1, to: today)
    }

    // MARK: - Voice type (성종) estimation

    public enum VoiceType: String, Codable, CaseIterable {
        case bass = "베이스"
        case baritone = "바리톤"
        case tenor = "테너"
        case contralto = "알토"
        case mezzo = "메조소프라노"
        case soprano = "소프라노"
        case undetermined = "미확정"
    }

    /// Estimated voice type from the measured comfortable range.
    ///
    /// Classification uses the COMFORTABLE range (the notes the user actually
    /// sings in, i.e. tracker-session extremes) rather than the absolute
    /// biological limit: a beginner's reachable extremes underestimate the
    /// natural type. Voice science (e.g. Bunch & Chapman) classifies by range
    /// + tessitura + timbre; without timbre analysis we use the midpoint of
    /// the comfortable range (tessitura proxy) plus the absolute ceiling,
    /// which the onboarding measurement provides.
    ///
    /// Bands use the classical Fach reference points (midi):
    ///   soprano    midpoint >= 64 (E4)  & ceiling >= 74
    ///   mezzo      midpoint >= 62 (D4)  & ceiling >= 72
    ///   contralto  midpoint >= 60 (C4)
    ///   tenor      midpoint >= 50 (D3)  & ceiling >= 62
    ///   baritone   midpoint >= 47 (B2)  & ceiling >= 59
    ///   bass       below baritone
    /// Returns .undetermined until the comfortable span covers >= 10 semitones
    /// (a too-narrow measurement says more about skill than anatomy).
    public static func estimateVoiceType(
        comfortableLowMidi: Int,
        comfortableHighMidi: Int,
        absoluteHighMidi: Int,
        isFemale: Bool?
    ) -> VoiceType {
        guard comfortableHighMidi - comfortableLowMidi >= 10 else { return .undetermined }
        let midpoint = (comfortableLowMidi + comfortableHighMidi) / 2

        if isFemale == true {
            if midpoint >= 66 && absoluteHighMidi >= 76 { return .soprano }
            if midpoint >= 62 && absoluteHighMidi >= 71 { return .mezzo }
            return .contralto
        }
        if isFemale == false {
            if midpoint >= 50 && absoluteHighMidi >= 62 { return .tenor }
            if midpoint >= 47 && absoluteHighMidi >= 59 { return .baritone }
            return .bass
        }
        // Unknown gender: pick the band by midpoint alone across the merged scale.
        switch midpoint {
        case 64...: return absoluteHighMidi >= 74 ? .soprano : .mezzo
        case 62..<64: return .mezzo
        case 60..<62: return .contralto
        case 50..<60: return absoluteHighMidi >= 62 ? .tenor : .baritone
        case 47..<50: return .baritone
        default: return .bass
        }
    }

    /// Passaggio zone for the estimated type (start..end in midi).
    /// Male passaggio sits around the F#4-A4 primo for tenors, lower for
    /// heavier voices; female secondo around D5-F5.
    public static func passaggioZone(for type: VoiceType) -> ClosedRange<Int>? {
        switch type {
        case .tenor: return 66...69   // F#4..A4
        case .baritone: return 64...67 // E4..G4
        case .bass: return 62...65     // D4..F4
        case .contralto: return 74...77 // D5..F5
        case .mezzo: return 74...77
        case .soprano: return 74...78   // D5..F#5
        case .undetermined: return nil
        }
    }

    /// Median of an unsorted list (even count averages the middle two).
    public static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Speaking-fundamental-frequency voice screening (Baken & Orlikoff
    /// norms): habitual speech pitch is the most anatomy-driven signal
    /// available from a mic — trained singers shift tessitura, but speech
    /// habits move far less.
    /// Male speech norms: bass ~85-95Hz, baritone ~100-120Hz, tenor ~125-150Hz.
    /// Female speech norms: alto ~165-180Hz, mezzo ~190-215Hz, soprano ~220-240Hz.
    public static func speechVoiceTypeBand(medianSpeechMidi: Int, isFemale: Bool?) -> VoiceType {
        if isFemale == true {
            switch medianSpeechMidi {
            case ..<54: return .contralto   // below ~185Hz
            case 54..<57: return .mezzo     // ~185-215Hz
            default: return .soprano        // ~220Hz and above
            }
        }
        if isFemale == false {
            switch medianSpeechMidi {
            case ..<43: return .bass        // below ~98Hz
            case 43..<47: return .baritone  // ~98-123Hz
            default: return .tenor          // ~123Hz and above
            }
        }
        // Unknown gender: split the merged scale at the alto floor (~185Hz).
        switch medianSpeechMidi {
        case ..<47: return .baritone
        case 47..<50: return .tenor
        case 50..<54: return .contralto
        case 54..<57: return .mezzo
        default: return .soprano
        }
    }

    /// Two-axis classification: speech f0 (anatomy) confirms or corrects the
    /// range-based guess. When both axes land in the same register family
    /// (male vs female scale), speech wins ties because it is harder to train
    /// away; when they contradict across families, the measurement is
    /// unreliable and stays undetermined.
    public static func refinedVoiceType(
        rangeBased: VoiceType,
        medianSpeechMidi: Int,
        isFemale: Bool?
    ) -> VoiceType {
        guard rangeBased != .undetermined else { return .undetermined }
        let speech = speechVoiceTypeBand(medianSpeechMidi: medianSpeechMidi, isFemale: isFemale)
        let rangeFamily: Bool? = {
            switch rangeBased {
            case .bass, .baritone, .tenor: return false
            case .contralto, .mezzo, .soprano: return true
            case .undetermined: return nil
            }
        }()
        let speechFamily: Bool? = {
            switch speech {
            case .bass, .baritone, .tenor: return false
            case .contralto, .mezzo, .soprano: return true
            case .undetermined: return nil
            }
        }()
        guard let rf = rangeFamily, let sf = speechFamily else { return rangeBased }
        if rf != sf { return .undetermined }   // contradictory evidence
        if rangeBased == speech { return speech } // agreement
        // Same family, different weight: trust speech for the register axis.
        return speech
    }

    // MARK: - Own audio engine: formant synthesis targets

    /// Korean training vowels with their canonical formant frequencies
    /// (F1/F2/F3 in Hz, Peterson & Barney-style reference values).
    /// Formant values are acoustic facts, not copyrightable content — this
    /// table powers an in-app synthesis demo engine so exercises can
    /// DEMONSTRATE sounds without shipping anyone's recordings.
    public enum TrainingVowel: String, CaseIterable {
        case a = "아"
        case e = "에"
        case i = "이"
        case o = "오"
        case u = "우"
    }

    /// (F1, F2, F3) bandpass centers for a vowel.
    public static func formants(for vowel: TrainingVowel) -> (f1: Double, f2: Double, f3: Double) {
        switch vowel {
        case .a: return (730, 1090, 2440)
        case .e: return (530, 1840, 2480)
        case .i: return (270, 2290, 3010)
        case .o: return (570, 840, 2410)
        case .u: return (300, 870, 2240)
        }
    }

    /// FFT bin index for a frequency given sample rate and bin count.
    public static func fftBin(frequency: Double, sampleRate: Double, binCount: Int) -> Int {
        guard sampleRate > 0, binCount > 0 else { return 0 }
        return min(binCount - 1, max(0, Int(frequency / (sampleRate / Double(binCount)))))
    }

    /// Formant region energy ratio helper for vowel-feedback scoring:
    /// maps [binCount] magnitudes to the (0...1) strength of a vowel's
    /// F1/F2 regions vs total energy — the spectrogram feedback contract.
    public static func formantStrength(magnitudes: [Double], sampleRate: Double,
                                       vowel: TrainingVowel) -> Double {
        guard !magnitudes.isEmpty else { return 0 }
        let binHz = sampleRate / Double(magnitudes.count)
        guard binHz > 0 else { return 0 }
        let f = formants(for: vowel)
        func bandEnergy(_ center: Double) -> Double {
            let lo = max(0, Int((center - binHz * 1.5) / binHz))
            let hi = min(magnitudes.count - 1, Int((center + binHz * 1.5) / binHz))
            guard lo <= hi else { return 0 }
            return magnitudes[lo...hi].reduce(0, +)
        }
        let total = magnitudes.reduce(0, +)
        guard total > 0 else { return 0 }
        let formantSum = bandEnergy(f.f1) + bandEnergy(f.f2)
        return min(1.0, formantSum / total)
    }

    // MARK: - Vowel feedback game (own-engine coaching)

    /// Peak frequency (Hz) within a spectral band — the measured formant.
    public static func peakFrequency(magnitudes: [Double], sampleRate: Double,
                                     band: ClosedRange<Double>) -> Double? {
        let n = magnitudes.count
        guard n > 0, sampleRate > 0 else { return nil }
        let binHz = sampleRate / Double(n)
        let lo = max(0, Int(band.lowerBound / binHz))
        let hi = min(n - 1, Int(band.upperBound / binHz))
        guard lo <= hi else { return nil }
        var bestBin = lo
        var bestMag = -1.0
        for bin in lo...hi where magnitudes[bin] > bestMag {
            bestMag = magnitudes[bin]
            bestBin = bin
        }
        guard bestMag > 0 else { return nil }
        return Double(bestBin) * binHz
    }

    /// Extract the speaker's F1/F2 from a magnitude spectrum.
    public static func measuredFormants(magnitudes: [Double], sampleRate: Double) -> (f1: Double, f2: Double)? {
        guard let f1 = peakFrequency(magnitudes: magnitudes, sampleRate: sampleRate, band: 250...1000),
              let f2 = peakFrequency(magnitudes: magnitudes, sampleRate: sampleRate, band: 1000...2800)
        else { return nil }
        return (f1, f2)
    }

    /// Direction coaching: compares the measured formants to the target
    /// vowel's canonical values and tells the user WHAT TO CHANGE — the
    /// coaching layer a video cannot personalize.
    /// F1 low  -> "open the mouth more" (bigger jaw drop raises F1)
    /// F2 low  -> "tongue more forward" (fronting raises F2 for front vowels)
    public static func vowelDirectionFeedback(target: TrainingVowel,
                                              userF1: Double, userF2: Double) -> [String] {
        let t = formants(for: target)
        var tips: [String] = []
        if userF1 < t.f1 - 120 {
            tips.append("입을 더 크게 벌려보세요 — F1(제1포먼트)이 목표보다 낮습니다")
        } else if userF1 > t.f1 + 120 {
            tips.append("입을 조금만 벌려보세요 — F1이 목표보다 높습니다")
        }
        let frontVowels: Set<TrainingVowel> = [.i, .e]
        if frontVowels.contains(target) {
            if userF2 < t.f2 - 200 { tips.append("혀를 더 앞으로 가져가세요 — F2이 목표보다 낮습니다") }
        } else if userF2 < t.f2 - 200 {
            tips.append("입술을 더 둥글게 말아보세요 — F2이 목표보다 낮습니다")
        }
        return tips
    }

    /// 0...100 round score from the formant strength ratio.
    public static func vowelRoundScore(strength: Double) -> Int {
        Int((min(1.0, max(0, strength)) * 100).rounded())
    }

    /// Contrastive-pair progression: level 1 practices maximally distinct
    /// vowels (아 vs 이), later levels add close pairs (에 vs 이).
    public static func vowelGameRounds(level: Int) -> [TrainingVowel] {
        switch min(3, max(1, level)) {
        case 1: return [.a, .i, .o, .i]          // open vs front vs round
        case 2: return [.a, .e, .o, .u]          // add close neighbors
        default: return [.e, .i, .u, .o, .a, .e] // full discrimination
        }
    }

    // MARK: - Interval (melody) matching game

    /// Named training intervals in semitones — the melody game ladder.
    public enum TrainingInterval: String, CaseIterable {
        case unison = "같은음"
        case majorSecond = "장2도"
        case majorThird = "장3도"
        case perfectFourth = "완전4도"
        case perfectFifth = "완전5도"
        case octave = "옥타브"

        public var semitones: Int {
            switch self {
            case .unison: return 0
            case .majorSecond: return 2
            case .majorThird: return 4
            case .perfectFourth: return 5
            case .perfectFifth: return 7
            case .octave: return 12
            }
        }
    }

    /// Interval ladder per level: L1 unison/fifth/octave (obvious leaps),
    /// L2 adds thirds/fourths, L3 all six in random order.
    public static func intervalRounds(level: Int, roll: () -> Int) -> [TrainingInterval] {
        func pick<T>(_ pool: [T]) -> T { pool[abs(roll()) % pool.count] }
        switch min(3, max(1, level)) {
        case 1: return [.unison, .perfectFifth, .octave, .unison]
        case 2: return [.majorSecond, .majorThird, .perfectFourth, .perfectFifth, .octave]
        default: return (0..<6).map { _ in pick(Array(TrainingInterval.allCases)) }
        }
    }

    /// Score an interval attempt: user sang `userSemitones` from the base
    /// when the target was `target.semitones`. Exact = 100, off-by-one
    /// semitone = partial (40), otherwise 0.
    public static func intervalScore(target: TrainingInterval, userSemitones: Int) -> Int {
        let diff = abs(userSemitones - target.semitones)
        if diff == 0 { return 100 }
        if diff == 1 { return 40 }
        return 0
    }

    /// Coaching feedback for a wrong interval.
    public static func intervalFeedback(target: TrainingInterval, userSemitones: Int) -> String {
        let diff = userSemitones - target.semitones
        if diff == 0 { return "정확합니다" }
        if diff > 0 {
            return "너무 넓게 잡으셨어요 — \(target.rawValue)(\(target.semitones)반음)보다 \(diff)반음 높습니다"
        }
        return "너무 좁게 잡으셨어요 — \(target.rawValue)(\(target.semitones)반음)보다 \(-diff)반음 낮습니다"
    }

    // MARK: - Ear training (pitch discrimination) game

    /// Two-note comparison trial: the player hears A then B and answers
    /// whether B is higher, lower, or the same.
    public enum PitchComparison: String, Codable {
        case higher = "높아요"
        case lower = "낮아요"
        case same = "같아요"
    }

    /// Generate an ear-training trial: a base note and a comparison offset.
    /// L1: obvious gaps (3+ semitones or unison), L2: 2-semitone, L3: 1-semitone.
    public static func earTrainingTrial(level: Int, roll: () -> Int) -> (baseMidi: Int, offset: Int) {
        func rnd() -> Int { abs(roll()) }
        let base = 55 + rnd() % 10  // G3..D4 comfortable listening zone
        let gapPool: [[Int]]
        switch min(3, max(1, level)) {
        case 1: gapPool = [[0, 4, 5, 7, -4, -5, -7]]
        case 2: gapPool = [[0, 2, 3, -2, -3, 4, -4]]
        default: gapPool = [[0, 1, -1, 2, -2, 3, -3]]
        }
        let pool = gapPool[0]
        return (base, pool[rnd() % pool.count])
    }

    /// The correct answer for a trial offset.
    public static func earTrainingAnswer(offset: Int) -> PitchComparison {
        if offset > 0 { return .higher }
        if offset < 0 { return .lower }
        return .same
    }

    /// Streak-based ear training progression: N correct in a row promotes,
    /// 2 wrong in a row demotes. Returns the new level.
    public static func earTrainingLevel(currentLevel: Int, correctStreak: Int, wrongStreak: Int) -> Int {
        if correctStreak >= 5 && currentLevel < 3 { return currentLevel + 1 }
        if wrongStreak >= 2 && currentLevel > 1 { return currentLevel - 1 }
        return currentLevel
    }

    // MARK: - Best-take comparison (self-reference growth)

    /// A saved "best take" snapshot the user can compare against later.
    /// Vowel formants + accuracy form the fingerprint — no audio recording
    /// needed, just the measurable features.
    public struct BestTake: Codable, Equatable {
        public var timestamp: Date
        public var accuracy: Int
        public var medianF1: Double
        public var medianF2: Double
        public var noteMidi: Int

        public init(timestamp: Date, accuracy: Int, medianF1: Double, medianF2: Double, noteMidi: Int) {
            self.timestamp = timestamp
            self.accuracy = accuracy
            self.medianF1 = medianF1
            self.medianF2 = medianF2
            self.noteMidi = noteMidi
        }
    }

    /// Compare a current take to the saved best: positive deltas mean growth.
    /// Accuracy delta + formant stability (closer to canonical = better vowel
    /// control) combine into a single growth summary.
    public static func compareTakes(best: BestTake, current: BestTake) -> (accuracyDelta: Int, formantDriftCents: Double, summary: String) {
        let accDelta = current.accuracy - best.accuracy
        // Formant drift in "cents" (log-frequency distance between F2s — the
        // vowel-identity formant).
        let f2Drift = current.medianF2 > 0 && best.medianF2 > 0
            ? 1200 * log2(current.medianF2 / best.medianF2)
            : 0
        var summary: String
        if accDelta > 5 {
            summary = "베스트 테이크보다 정확도 +\(accDelta)점 — 성장하고 있습니다"
        } else if accDelta < -5 {
            summary = "베스트보다 \(-accDelta)점 낮습니다 — 컨디션 관리도 실력입니다"
        } else {
            summary = "베스트 테이크와 비슷한 수준입니다"
        }
        if abs(f2Drift) > 100 {
            summary += " · 모음 안정성 변화 \(Int(f2Drift))¢"
        }
        return (accDelta, f2Drift, summary)
    }

    // MARK: - Personalized difficulty (session-history based)

    /// A game's recent history drives a recommended starting level:
    /// the last N session accuracies trend determines whether the user
    /// should be pushed, held, or eased. 80%+ average for 3 sessions
    /// promotes, <50% for 2 sessions demotes, otherwise hold.
    public static func recommendedLevel(recentAccuracies: [Int], currentLevel: Int, maxLevel: Int = 3) -> Int {
        guard !recentAccuracies.isEmpty else { return currentLevel }
        let window = recentAccuracies.suffix(3)
        let avg = Double(window.reduce(0, +)) / Double(window.count)
        if avg >= 80 && currentLevel < maxLevel { return currentLevel + 1 }
        if avg < 50 && currentLevel > 1 {
            // Demote only after 2 consecutive sub-50% sessions.
            if window.count >= 2, window.suffix(2).allSatisfy({ $0 < 50 }) {
                return currentLevel - 1
            }
        }
        return currentLevel
    }

    /// Which game to recommend next: the weakest skill gets priority
    /// (lowest recent accuracy), with a bias toward variety (avoid
    /// recommending the same game 3 times in a row).
    public enum GameType: String, CaseIterable {
        case vowel = "모음"
        case interval = "음정"
        case ear = "귀훈련"
    }

    public static func recommendNextGame(
        vowelAccuracy: Int?, intervalAccuracy: Int?, earAccuracy: Int?,
        lastGame: GameType?
    ) -> GameType {
        var scores: [(GameType, Int)] = []
        scores.append((.vowel, vowelAccuracy ?? 50))
        scores.append((.interval, intervalAccuracy ?? 50))
        scores.append((.ear, earAccuracy ?? 50))
        // Sort ascending (weakest first).
        scores.sort { $0.1 < $1.1 }
        // If the weakest is the last game played AND the second-weakest is
        // close (within 15 points), prefer variety.
        if let last = lastGame, scores[0].0 == last, scores.count > 1,
           scores[1].1 - scores[0].1 <= 15 {
            return scores[1].0
        }
        return scores[0].0
    }

    // MARK: - Session grading

    /// Karaoke-style 0...100 score to S/A/B/C/D grade.
    public static func sessionGrade(forScore score: Int) -> String {
        switch score {
        case 90...: return "S"
        case 80..<90: return "A"
        case 70..<80: return "B"
        case 60..<70: return "C"
        default: return "D"
        }
    }
}

public struct HeatmapDay: Identifiable, Hashable {
    /// Stable identity: re-issuing UUIDs on every update would rebuild the
    /// whole 84-cell grid even when only one day changed.
    public var id: String { dayKey }
    public let date: Date
    public let count: Int
    public let intensity: Double
    public let dayKey: String

    public init(date: Date, count: Int, intensity: Double, dayKey: String) {
        self.date = date
        self.count = count
        self.intensity = intensity
        self.dayKey = dayKey
    }
}
