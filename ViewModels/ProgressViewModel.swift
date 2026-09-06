//
//  ProgressViewModel.swift
//  DailyVocal
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
    /// Estimated 성종 (voice type) from the measured comfortable range.
    public private(set) var estimatedVoiceType: VocalLogic.VoiceType = .undetermined
    public private(set) var passaggioZone: ClosedRange<Int>? = nil
    /// Hz; 0 = speak-mode measurement not yet taken.
    public private(set) var speechMedianFrequency: Double = 0
    /// Last vibrato check: rate in Hz. 0 = not yet measured.
    public private(set) var lastVibratoRateHz: Double = 0
    public private(set) var lastVibratoExtentCents: Double = 0
    /// Last messa di voce check: dynamic range in dB. 0 = not yet measured.
    public private(set) var lastDynamicsRangeDb: Double = 0
    /// Longest single-note hold ever recorded, in seconds. 0 = not yet measured.
    public private(set) var bestSustainSeconds: Double = 0
    /// Signed cents bias of the last harmony check per direction.
    public private(set) var harmonyAboveCents: Double = 0
    public private(set) var harmonyBelowCents: Double = 0

    /// Technique trend sparkline: latest technique measure series with >= 2
    /// points (vibrato Hz or dynamics dB, whichever has more points).
    public struct TechniqueTrend {
        public let kind: String   // "비브라토 속도(Hz)" / "셈여림 레인지(dB)" / ...
        public let points: [(index: Int, value: Double)]
        /// Step-error series: lower is better, so the bars invert.
        public var lowerIsBetter: Bool = false
        public init(kind: String, points: [(index: Int, value: Double)], lowerIsBetter: Bool = false) {
            self.kind = kind
            self.points = points
            self.lowerIsBetter = lowerIsBetter
        }
    }
    public private(set) var techniqueTrend: TechniqueTrend?
    private var pitchRecordsInternal: [PitchRecord] = []

    public init() {
        heatmapDays = VocalLogic.buildEmptyHeatmap(dayCount: 84)
    }

    /// The recommended tip id (for the deep link), nil mirrors the line.
    public var recommendedTipID: Int? {
        // Same inputs as recommendedTipLine; duplicated call is cheap/pure.
        let isMale: Bool
        if case .tenor = estimatedVoiceType { isMale = true }
        else if case .baritone = estimatedVoiceType { isMale = true }
        else if case .bass = estimatedVoiceType { isMale = true }
        else { isMale = false }
        return VocalLogic.recommendedTip(
            vibratoRateHz: lastVibratoRateHz,
            dynamicsRangeDb: lastDynamicsRangeDb,
            bestSustainSeconds: bestSustainSeconds,
            isMaleVoice: isMale)?.id
    }

    /// Data-driven tip recommendation line ("오늘 읽을 팁: {title} — {reason}").
    public var recommendedTipLine: String? {
        let isMale: Bool
        if case .tenor = estimatedVoiceType { isMale = true }
        else if case .baritone = estimatedVoiceType { isMale = true }
        else if case .bass = estimatedVoiceType { isMale = true }
        else { isMale = false }
        guard let rec = VocalLogic.recommendedTip(
            vibratoRateHz: lastVibratoRateHz,
            dynamicsRangeDb: lastDynamicsRangeDb,
            bestSustainSeconds: bestSustainSeconds,
            isMaleVoice: isMale) else { return nil }
        return "팁 #\(rec.id) — \(rec.reason)"
    }

    /// Latest step-error fingerprint for a sequence game (semitones), 0 if none.
    public func latestStepError(for game: VocalLogic.GameType) -> Double {
        pitchRecordsInternal.last {
            $0.targetNoteName == VocalLogic.gameLabel(for: game) && $0.techniqueValue > 0
        }?.techniqueValue ?? 0
    }

    // MARK: - Update entry point (called by the view with @Query results)

    public func update(sessions: [PracticeSession], profile: UserProfile?, latestPitchRecord: PitchRecord? = nil, allPitchRecords: [PitchRecord] = []) {
        pitchRecordsInternal = allPitchRecords.sorted { $0.timestamp < $1.timestamp }
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

        // Read-only by design (P2-4 redesign): token consumption happens once,
        // at session completion (DailyRoutineViewModel.persistSession), never
        // on a dashboard render. This view merely reports bridged days.
        frozenDaysInStreak = result.usedFrozenCount

        var dayCounts: [String: Int] = [:]
        for session in sessions {
            dayCounts[VocalLogic.practiceDayKey(for: session.date), default: 0] += 1
        }

        // Weekly goal: practice days in the current Mon..Sun week (pinned to
        // Monday — CLDR week starts differ by locale, the header does not).
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        ) ?? today
        let weekKeys = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart).map { VocalLogic.dayFormatter.string(from: $0) }
        }
        weeklyPracticeDays = weekKeys.filter { practiceDays.contains($0) }.count

        heatmapDays = VocalLogic.buildHeatmap(dayCounts: dayCounts, dayCount: 84)

        if let profile {
            let rangeType = VocalLogic.estimateVoiceType(
                comfortableLowMidi: Int(VocalAudioEngine.midiNumber(forFrequency: profile.lowestFrequency).rounded()),
                comfortableHighMidi: Int(VocalAudioEngine.midiNumber(forFrequency: profile.highestFrequency).rounded()),
                absoluteHighMidi: Int(VocalAudioEngine.midiNumber(forFrequency: profile.baselineHighestFrequency).rounded()),
                isFemale: profile.prefersHigherKeyGuide ? true : nil
            )
            // Second axis: habitual speech pitch (anatomy-driven screen).
            let type = profile.speechMedianFrequency > 0
                ? VocalLogic.refinedVoiceType(
                    rangeBased: rangeType,
                    medianSpeechMidi: Int(VocalAudioEngine.midiNumber(forFrequency: profile.speechMedianFrequency).rounded()),
                    isFemale: profile.prefersHigherKeyGuide ? true : nil
                  )
                : rangeType
            estimatedVoiceType = type
            passaggioZone = VocalLogic.passaggioZone(for: type)
            speechMedianFrequency = profile.speechMedianFrequency
            lastVibratoRateHz = profile.lastVibratoRateHz
            lastVibratoExtentCents = profile.lastVibratoExtentCents
            lastDynamicsRangeDb = profile.lastDynamicsRangeDb
            bestSustainSeconds = profile.bestSustainSeconds
            harmonyAboveCents = profile.harmonyAboveCents
            harmonyBelowCents = profile.harmonyBelowCents
            streakFreezeTokens = profile.streakFreezeTokens
            hasMeasuredRange = profile.hasMeasuredRange
            baselineRangeText = "\(profile.baselineLowestNoteName) ~ \(profile.baselineHighestNoteName)"
            currentRangeText = "\(profile.lowestNoteName) ~ \(profile.highestNoteName)"
            rangeExpansionSemitones = VocalLogic.rangeExpansionSemitones(
                baselineTopHz: profile.baselineHighestFrequency,
                currentTopHz: profile.highestFrequency
            )
        }

        // Technique trend: sessions carrying a fingerprint, in order.
        let records = pitchRecordsInternal
        let vib = records.filter { $0.targetNoteName == VocalLogic.gameLabel(for: .vibrato) && $0.techniqueValue > 0 }
        let dyn = records.filter { $0.targetNoteName == VocalLogic.gameLabel(for: .dynamics) && $0.techniqueValue > 0 }
        // Sustained single-note sessions carry MPT seconds as their value.
        let sus = records.filter { $0.targetNoteName == VocalLogic.gameLabel(for: .vibrato) ? false : ($0.targetNoteName == VocalLogic.gameLabel(for: .dynamics) ? false : $0.techniqueValue >= 7.5) }
        // Step-error series (semitones) — LOWER is better, bars invert.
        let scaleErr = records.filter { $0.targetNoteName == VocalLogic.gameLabel(for: .scale) && $0.techniqueValue > 0 }
        let melodyErr = records.filter { $0.targetNoteName == VocalLogic.gameLabel(for: .melody) && $0.techniqueValue > 0 }
        if vib.count >= 2 && vib.count >= dyn.count && vib.count >= sus.count && vib.count >= scaleErr.count && vib.count >= melodyErr.count {
            techniqueTrend = TechniqueTrend(kind: "비브라토 속도(Hz)", points: vib.enumerated().map { ($0.offset, $0.element.techniqueValue) })
        } else if dyn.count >= 2 && dyn.count >= sus.count && dyn.count >= scaleErr.count && dyn.count >= melodyErr.count {
            techniqueTrend = TechniqueTrend(kind: "셈여림 레인지(dB)", points: dyn.enumerated().map { ($0.offset, $0.element.techniqueValue) })
        } else if sus.count >= 2 && sus.count >= scaleErr.count && sus.count >= melodyErr.count {
            techniqueTrend = TechniqueTrend(kind: "최장 지속(초)", points: sus.enumerated().map { ($0.offset, $0.element.techniqueValue) })
        } else if scaleErr.count >= 2 && scaleErr.count >= melodyErr.count {
            techniqueTrend = TechniqueTrend(kind: "스케일 오차(반음)", points: scaleErr.enumerated().map { ($0.offset, $0.element.techniqueValue) }, lowerIsBetter: true)
        } else if melodyErr.count >= 2 {
            techniqueTrend = TechniqueTrend(kind: "멜로디 오차(반음)", points: melodyErr.enumerated().map { ($0.offset, $0.element.techniqueValue) }, lowerIsBetter: true)
        } else {
            techniqueTrend = nil
        }

        if let record = latestPitchRecord {
            let grade = VocalLogic.sessionGrade(forScore: Int(record.accuracyPercentage.rounded()))
            latestPitchSummary = "\(Int(record.accuracyPercentage.rounded()))점 · \(grade)등급 · 목표음 \(record.targetNoteName)"
        } else {
            latestPitchSummary = nil
        }
    }

}
