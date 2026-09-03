//
//  VocalLogic.swift
//  5VocalMaster
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
            return (count, min(1.0, Double(count) / 3.0))
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
