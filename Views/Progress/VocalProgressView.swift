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

                        VocalRangeChart(
                            hasMeasuredRange: viewModel.hasMeasuredRange,
                            baselineRangeText: viewModel.baselineRangeText,
                            currentRangeText: viewModel.currentRangeText,
                            expansionSemitones: viewModel.rangeExpansionSemitones
                        )
                        .padding(.horizontal, 20)

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

    // MARK: - Summary grid

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
