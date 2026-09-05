//
//  VocalProgressView.swift
//  DailyVocal
//
//  Growth dashboard driven by live SwiftData queries: streak, 12-week
//  heatmap, real vocal range growth (onboarding baseline vs current),
//  totals from actual sessions, and the reminder toggle.
//

import SwiftUI
import SwiftData

public struct VocalProgressView: View {
    @Query(sort: [SortDescriptor(\PracticeSession.date, order: .reverse)])
    private var sessions: [PracticeSession]

    @Query(sort: [SortDescriptor(\PitchRecord.timestamp, order: .reverse)])
    private var pitchRecords: [PitchRecord]

    @Query private var profiles: [UserProfile]

    @State private var viewModel = ProgressViewModel()
    @State private var reminderToggleTask: Task<Void, Never>?

    public init() {}

    private var profile: UserProfile? { profiles.first }

    private func refreshStats() {
        viewModel.update(sessions: sessions, profile: profile, latestPitchRecord: pitchRecords.first)
    }

    public var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 16) {
                headerView

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        streakBanner
                            .padding(.horizontal, 20)

                        if isReminderEnabled {
                            reminderTimeCard
                                .padding(.horizontal, 20)
                        }

                        HeatmapCalendarView(days: viewModel.heatmapDays)
                            .padding(.horizontal, 20)

                        if let rec = nextGameRecommendation {
                            nextGameCard(rec)
                                .padding(.horizontal, 20)
                        }

                        VocalRangeChart(
                            hasMeasuredRange: viewModel.hasMeasuredRange,
                            baselineRangeText: viewModel.baselineRangeText,
                            currentRangeText: viewModel.currentRangeText,
                            expansionSemitones: viewModel.rangeExpansionSemitones
                        )
                        .padding(.horizontal, 20)

                        if viewModel.estimatedVoiceType != .undetermined {
                            voiceTypeCard
                                .padding(.horizontal, 20)
                        }

                        if viewModel.lastVibratoRateHz > 0 || viewModel.lastDynamicsRangeDb > 0 || viewModel.bestSustainSeconds > 0 {
                            techniqueSnapshotCard
                                .padding(.horizontal, 20)
                        }

                        statsSummaryGrid
                            .padding(.horizontal, 20)

                        if pitchRecords.count >= 2 {
                            AccuracyTrendCard(records: Array(pitchRecords.prefix(14).reversed()))
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .onAppear {
            refreshStats()
        }
        .onChange(of: sessions) { _, _ in
            refreshStats()
        }
        .onChange(of: pitchRecords) { _, _ in
            refreshStats()
        }
        .onChange(of: profiles) { _, _ in
            refreshStats()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("4주 성장 기록")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.brandSecondary)
                Text("성장 & 통계")
                    .font(.screenTitle)
                    .foregroundColor(.white)
            }
            Spacer()

            if isReminderEnabled {
                Text(reminderTimeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.brandSecondary)
            }

            reminderButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    /// Reminder time card shown while reminders are on: change the daily HH:MM
    /// and the native schedule is rebuilt immediately.
    private var reminderTimeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bell.badge")
                    .foregroundColor(.brandSecondary)
                Text("연습 알림 시간")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Text("매일 같은 시간에 울립니다")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            DatePicker(
                "알림 시간",
                selection: reminderTimeBinding,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(.brandSecondary)
        }
        .glassCard(cornerRadius: 16, padding: 14)
    }

    private var reminderTimeLabel: String {
        String(format: "%02d:%02d", profile?.reminderHour ?? 20, profile?.reminderMinute ?? 0)
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                let hour = profile?.reminderHour ?? 20
                let minute = profile?.reminderMinute ?? 0
                return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                guard let profile else { return }
                let components = calendar.dateComponents([.hour, .minute], from: newDate)
                profile.reminderHour = components.hour ?? 20
                profile.reminderMinute = components.minute ?? 0
                try? modelContextSave()
                // Rebuild the native schedule with the new time.
                reminderToggleTask?.cancel()
                reminderToggleTask = Task {
                    _ = await NotificationManager.shared.enableDailyReminders(
                        hour: profile.reminderHour,
                        minute: profile.reminderMinute
                    )
                }
            }
        )
    }

    private var calendar: Calendar { .current }

    private var reminderButton: some View {
        Button(action: toggleReminder) {
            Image(systemName: isReminderEnabled ? "bell.fill" : "bell.slash")
                .font(.subheadline)
                .foregroundColor(isReminderEnabled ? .brandSecondary : .textSecondary)
                .frame(width: 36, height: 36)
                .glassCard(cornerRadius: 10, padding: 4)
        }
    }

    private var isReminderEnabled: Bool {
        profile?.reminderEnabled ?? false
    }

    private func toggleReminder() {
        HapticManager.shared.buttonTap()
        guard let profile else { return }
        let enabling = !profile.reminderEnabled
        profile.reminderEnabled = enabling
        try? modelContextSave()

        let notifications = NotificationManager.shared
        if enabling {
            reminderToggleTask?.cancel()
            reminderToggleTask = Task {
                let granted = await notifications.enableDailyReminders(
                    hour: profile.reminderHour,
                    minute: profile.reminderMinute
                )
                if !granted {
                    // Permission denied: revert the stored flag.
                    profile.reminderEnabled = false
                    try? modelContextSave()
                }
            }
        } else {
            notifications.disableDailyReminders()
        }
    }

    private func modelContextSave() throws {
        // SwiftData autosaves via the container; explicit save keeps it immediate.
        try profiles.first?.modelContext?.save()
    }

    // MARK: - Streak banner

    private var streakBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("연속 실천 기록")
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                HStack(spacing: 8) {
                    // SF Symbol flame with glow (Duolingo escalation pattern);
                    // bounces once when the streak count changes.
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundColor(Color(red: 1.0, green: 0.588, blue: 0.0)) // #FF9600
                        .shadow(color: Color(red: 1.0, green: 0.588, blue: 0.0).opacity(0.6), radius: 6)
                        .symbolEffect(.bounce, value: viewModel.currentStreak)
                    Text("\(viewModel.currentStreak)일 연속")
                        .font(.title.weight(.heavy).monospacedDigit())
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: viewModel.currentStreak)
                }
                if viewModel.frozenDaysInStreak > 0 {
                    Text("🧊 보호권으로 이어진 날 \(viewModel.frozenDaysInStreak)일 포함")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }

                // Weekly goal (Duolingo-style milestone framing)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("이번 주 목표")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text("\(viewModel.weeklyPracticeDays)/\(viewModel.weeklyGoalDays)일")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundColor(viewModel.weeklyPracticeDays >= viewModel.weeklyGoalDays ? .vocalSuccess : .brandSecondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule()
                                .fill(viewModel.weeklyPracticeDays >= viewModel.weeklyGoalDays
                                      ? AnyShapeStyle(Color.vocalSuccess)
                                      : AnyShapeStyle(LinearGradient.primaryButton))
                                .frame(width: geo.size.width * CGFloat(min(1.0, Double(viewModel.weeklyPracticeDays) / Double(viewModel.weeklyGoalDays))))
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.top, 6)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("스트릭 보호권")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                Text("\(viewModel.streakFreezeTokens)개 보유 🛡️")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.brandSecondary)
            }
        }
        .glassCard(cornerRadius: 18, padding: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.vocalWarning.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Next-game recommendation

    /// Weakest-skill recommendation from the stored session records — the
    /// VocalLogic rule the web prototype has shown all along, now wired to
    /// the app's growth dashboard (was defined-but-unused ghost logic).
    private var nextGameRecommendation: (game: VocalLogic.GameType, reason: String)? {
        guard !pitchRecords.isEmpty else { return nil }
        let chronological = pitchRecords.reversed()
        let latest = VocalLogic.latestAccuracies(
            records: chronological.map { ($0.targetNoteName, Int($0.accuracyPercentage.rounded())) })
        let lastGame = chronological.last.flatMap { last in
            VocalLogic.GameType.allCases.first {
                VocalLogic.gameLabel(for: $0) == last.targetNoteName
            }
        }
        let game = VocalLogic.recommendNextGame(
            vowelAccuracy: latest[.vowel],
            intervalAccuracy: latest[.interval],
            earAccuracy: latest[.ear],
            vibratoAccuracy: latest[.vibrato],
            dynamicsAccuracy: latest[.dynamics],
            lastGame: lastGame)
        let reason: String
        if let accuracy = latest[game] {
            reason = "최근 점수 \(accuracy)점 — 가장 약한 훈련부터 보완해요"
        } else {
            reason = "아직 시도하지 않은 훈련 — 먼저 한 번 측정해 기준점을 만들어요"
        }
        return (game, reason)
    }

    private func nextGameCard(_ rec: (game: VocalLogic.GameType, reason: String)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.brandAccent)
                Text("오늘의 추천 훈련")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Text("취약점 우선 · 다양성 균형")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            Text(rec.game.rawValue)
                .font(.title3.weight(.heavy))
                .foregroundColor(.brandSecondary)
            Text(rec.reason)
                .font(.caption2)
                .foregroundColor(.textSecondary)
            Text("피치 트래커의 모드에서 바로 시작할 수 있어요")
                .font(.caption2)
                .foregroundColor(.textSecondary.opacity(0.8))
        }
        .glassCard(cornerRadius: 16, padding: 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Summary grid

    /// Last measured technique fingerprints from the sustain checks — the
    /// growth loop for vibrato rate and dynamic range.
    private var techniqueSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path")
                    .foregroundColor(.brandAccent)
                Text("테크닉 스냅샷 (최근 측정)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Text("피치 트래커에서 측정")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            HStack(spacing: 0) {
                if viewModel.lastVibratoRateHz > 0 {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("비브라토")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                        Text(String(format: "%.1fHz · ±%.0f¢", viewModel.lastVibratoRateHz, viewModel.lastVibratoExtentCents))
                            .font(.subheadline.weight(.bold))
                            .foregroundColor((4.5...6.5).contains(viewModel.lastVibratoRateHz) ? .vocalSuccess : .brandSecondary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if viewModel.lastVibratoRateHz > 0 && viewModel.lastDynamicsRangeDb > 0 {
                    Divider()
                        .frame(height: 30)
                        .background(Color.borderGlass)
                }
                if viewModel.lastDynamicsRangeDb > 0 {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("셈여림 레인지")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                        Text(String(format: "%.1fdB", viewModel.lastDynamicsRangeDb))
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(viewModel.lastDynamicsRangeDb >= 6 ? .vocalSuccess : .brandSecondary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            Text("비브라토 4.5~6.5Hz·±50~100¢ / 셈여림 6dB+ 가 목표 범위입니다")
                .font(.caption2)
                .foregroundColor(.textSecondary)
            if viewModel.bestSustainSeconds > 0 {
                Text(String(format: "최장 지속 %.1f초 (한 호흡 최대 발성) — 15초 이상이 건강 기준", viewModel.bestSustainSeconds))
                    .font(.caption2)
                    .foregroundColor(viewModel.bestSustainSeconds >= 15 ? .vocalSuccess : .vocalWarning)
            }
        }
        .glassCard(cornerRadius: 16, padding: 14)
        .accessibilityElement(children: .combine)
    }

    /// 성종(voice type) card: estimated type, why, and the personal
    /// passaggio zone the W3 routine targets.
    private var voiceTypeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.wave.2")
                    .foregroundColor(.brandAccent)
                Text("내 성종 (추정)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Text("측정 음역 기준")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            Text(viewModel.estimatedVoiceType.rawValue)
                .font(.title2.weight(.heavy))
                .foregroundColor(.brandSecondary)
            if viewModel.speechMedianFrequency > 0 {
                Text(String(format: "말하기 피치 중앙값 %.0fHz · 음역 추정과 교차 확인", viewModel.speechMedianFrequency))
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            } else {
                Text("피치 트래커의 '말하기 10초' 측정을 하면 정확도가 올라갑니다")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            if let zone = viewModel.passaggioZone {
                let low = VocalAudioEngine.noteAndCents(fromFrequency: VocalAudioEngine.frequency(forMidi: Double(zone.lowerBound))).note
                let high = VocalAudioEngine.noteAndCents(fromFrequency: VocalAudioEngine.frequency(forMidi: Double(zone.upperBound))).note
                Text("성구전환(파사지오) 구간: \(low) ~ \(high)\n3주차 루틴이 이 구간을 통과하도록 설계되어 있습니다.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineSpacing(3)
            }
        }
        .glassCard(cornerRadius: 16, padding: 14)
    }

    private var statsSummaryGrid: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.brandSecondary)
                        Text("총 연습 시간")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Text(viewModel.totalPracticeTimeFormatted)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 16, padding: 14)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.vocalSuccess)
                        Text("완료 세션")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Text("\(viewModel.totalSessions)회 완료")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 16, padding: 14)
            }

            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.brandAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("최근 피치 측정")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                    Text(viewModel.latestPitchSummary ?? "아직 기록이 없어요. 피치 트래커에서 첫 측정을 시작하세요.")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(viewModel.latestPitchSummary == nil ? .textSecondary : .white)
                }
                Spacer()
            }
            .glassCard(cornerRadius: 16, padding: 14)
        }
    }
}

/// Last N pitch sessions' accuracy as a mini bar trend with a 3-vs-3 delta
/// caption — shows whether matching is actually improving over time.
struct AccuracyTrendCard: View {
    let records: [PitchRecord]

    private var trendDelta: Int? {
        guard records.count >= 6 else { return nil }
        let recent = records.suffix(3).map(\.accuracyPercentage).reduce(0, +) / 3
        let previous = records.dropLast(3).suffix(3).map(\.accuracyPercentage).reduce(0, +) / 3
        return Int(recent - previous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.brandAccent)
                Text("정확도 추이")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                if let delta = trendDelta {
                    Text(delta >= 0 ? "최근 3회 평균 +\(delta)%p" : "최근 3회 평균 \(delta)%p")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(delta >= 0 ? .vocalSuccess : .vocalWarning)
                }
            }

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(record.accuracyPercentage >= 70 ? Color.vocalSuccess : Color.brandSecondary)
                        .frame(height: max(4, CGFloat(record.accuracyPercentage) / 100.0 * 52))
                        .frame(maxWidth: .infinity)
                }
            }
            Text("최근 \(records.count)회 세션 온피치율 · 초록 70% 이상")
                .font(.caption2)
                .foregroundColor(.textSecondary)
        }
        .glassCard(cornerRadius: 16, padding: 14)
    }
}
