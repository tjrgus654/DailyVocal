//
//  OnboardingView.swift
//  5VocalMaster
//
//  4-step onboarding: welcome -> analogy intro -> REAL vocal range
//  measurement (mic + live pitch, saved as the growth baseline) ->
//  reminder/key preferences -> start.
//

import SwiftUI
import SwiftData

public struct OnboardingView: View {
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @Environment(\.modelContext) private var modelContext

    @State private var currentPage = 0
    @State private var rangeTest = RangeTestModel()

    public init() {}

    private let pageCount = 4

    public var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                headerBar

                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    analogyPage.tag(1)
                    RangeTestPage(rangeTest: rangeTest).tag(2)
                    preferencesPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                bottomBar
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header / bottom bar

    private var headerBar: some View {
        HStack {
            Spacer()
            if currentPage < pageCount - 1 {
                Button("건너뛰기") {
                    finishOnboarding()
                }
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .padding(.trailing, 24)
                .padding(.top, 16)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            Button(action: handleNext) {
                HStack {
                    Text(currentPage == pageCount - 1 ? "5분 보컬 시작하기" : "다음")
                        .font(.headline)
                        .fontWeight(.bold)
                    Image(systemName: "arrow.right")
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(LinearGradient.primaryButton)
                .clipShape(RoundedRectangle(cornerRadius: DesignLayout.cornerRadiusButton, style: .continuous))
                .shadow(color: Color.brandPrimary.opacity(0.4), radius: 10, y: 5)
            }
            .padding(.horizontal, 24)

            if currentPage == 0 {
                Text("로그인 없이 모든 기능이 기기 내에 안전하게 저장됩니다.")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(.bottom, 32)
    }

    private func handleNext() {
        HapticManager.shared.buttonTap()
        if currentPage < pageCount - 1 {
            withAnimation { currentPage += 1 }
        } else {
            finishOnboarding()
        }
    }

    private func finishOnboarding() {
        persistRangeBaseline()
        persistPreferences()
        rangeTest.stop()
        onboardingCompleted = true
    }

    // MARK: - Page 0: welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.15))
                    .frame(width: 220, height: 220)
                Circle()
                    .stroke(LinearGradient.timerRing, lineWidth: 3)
                    .frame(width: 170, height: 170)
                Image(systemName: "mic.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundStyle(LinearGradient.primaryButton)
                    .shadow(color: Color.brandPrimary.opacity(0.6), radius: 15)
            }
            .padding(.bottom, 16)

            Text("하루 15분,\n목소리가 달라집니다")
                .font(.screenTitle)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)

            Text("발성 이론을 몰라도 괜찮습니다.\n오보컬 쇼츠 48개와 연구 기반 비법,\n실시간 피치 가이드가 혼자 연습의 길을 안내합니다.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.textSecondary)
                .lineSpacing(6)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 1: analogies

    private var analogyPage: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 14) {
                analogyCard(emoji: "🎈", title: "풍선 주둥이 비유", desc: "배를 쥐어짜지 않고 횡격막을 자연스럽게 유지")
                analogyCard(emoji: "👏", title: "손바닥 포개기 비유", desc: "가성을 먼저 켜고 부드럽게 성대 접지 걸기")
                analogyCard(emoji: "🦆", title: "오리 소리 비유", desc: "마녀 웃음(네이)으로 파사지오 구간 돌파")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Text("초보자 눈높이 맞춤 비유")
                .font(.screenTitle)
                .foregroundColor(.white)

            Text("복잡한 성대 해부학 용어 대신,\n몸으로 바로 느껴지는 감각으로 노래합니다.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    private func analogyCard(emoji: String, title: String, desc: String) -> some View {
        HStack(spacing: 16) {
            Text(emoji)
                .font(.system(size: 32))
                .frame(width: 50, height: 50)
                .background(Color.surfaceDark)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            Spacer()
        }
        .glassCard(cornerRadius: 16, padding: 14)
    }

    // MARK: - Page 3: preferences

    @AppStorage("prefersHigherKeyGuide") private var prefersHigherKeyGuide = false
    @State private var reminderEnabled = true

    private var preferencesPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundColor(.brandSecondary)
                .padding(.bottom, 6)

            Text("마지막 설정")
                .font(.screenTitle)
                .foregroundColor(.white)

            VStack(spacing: 18) {
                Toggle(isOn: $reminderEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("매일 저녁 8시 연습 알림")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text("연속 기록이 끊기기 전에 밤 10:30에 알려드려요")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }
                }
                .tint(Color.brandPrimary)

                Divider().background(Color.borderGlass)

                Picker("가이드 톤 키", selection: $prefersHigherKeyGuide) {
                    Text("남성 키 (C3 기준)").tag(false)
                    Text("여성 키 (C4 기준)").tag(true)
                }
                .pickerStyle(.segmented)

                Text("가이드 피아노 톤의 시작 음 높이입니다.\n언제든지 루틴 화면에서 바꿀 수 있습니다.")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            .glassCard(cornerRadius: 16, padding: 18)
            .padding(.horizontal, 28)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Persistence helpers

    private func fetchProfile() -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>()
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func persistRangeBaseline() {
        guard rangeTest.hasResult, let profile = fetchProfile() else { return }
        profile.baselineLowestNoteName = rangeTest.lowestNoteName
        profile.baselineLowestFrequency = rangeTest.lowestFrequency
        profile.baselineHighestNoteName = rangeTest.highestNoteName
        profile.baselineHighestFrequency = rangeTest.highestFrequency
        profile.lowestNoteName = rangeTest.lowestNoteName
        profile.lowestFrequency = rangeTest.lowestFrequency
        profile.highestNoteName = rangeTest.highestNoteName
        profile.highestFrequency = rangeTest.highestFrequency
        profile.hasMeasuredRange = true
        try? modelContext.save()
    }

    private func persistPreferences() {
        if let profile = fetchProfile() {
            profile.prefersHigherKeyGuide = prefersHigherKeyGuide
            profile.reminderEnabled = reminderEnabled
            try? modelContext.save()
        }
        let notifications = NotificationManager.shared
        if reminderEnabled {
            Task {
                await notifications.enableDailyReminders()
            }
        } else {
            notifications.disableDailyReminders()
        }
    }
}

// MARK: - Range test

/// Tracks the lowest and highest voiced pitch while the user glides through
/// their range. Attached to the engine's frame callback while measuring.
@MainActor
@Observable
private final class RangeTestModel {

    var isMeasuring = false
    private(set) var liveNoteName = "--"
    private(set) var liveFrequency = 0.0
    private(set) var lowestFrequency = 0.0
    private(set) var highestFrequency = 0.0
    private(set) var voicedFrames = 0

    var hasResult: Bool { voicedFrames >= 12 && lowestFrequency > 0 && highestFrequency > lowestFrequency }

    var lowestNoteName: String {
        VocalAudioEngine.noteAndCents(fromFrequency: lowestFrequency).note
    }

    var highestNoteName: String {
        VocalAudioEngine.noteAndCents(fromFrequency: highestFrequency).note
    }

    let audio = VocalAudioEngine.shared

    func start() {
        resetLive()
        isMeasuring = true
        audio.onPitchUpdate = { [weak self] frequency, noteName, _, voiced in
            guard let self, self.isMeasuring, voiced else { return }
            self.liveFrequency = frequency
            self.liveNoteName = noteName
            self.voicedFrames += 1
            if self.lowestFrequency == 0 || frequency < self.lowestFrequency {
                self.lowestFrequency = frequency
            }
            if frequency > self.highestFrequency {
                self.highestFrequency = frequency
            }
        }
        audio.startMicrophone()
    }

    func pause() {
        isMeasuring = false
        audio.stopMicrophone()
    }

    func stop() {
        isMeasuring = false
        audio.stopMicrophone()
        audio.onPitchUpdate = nil
    }

    func restart() {
        stop()
        start()
    }

    private func resetLive() {
        liveNoteName = "--"
        liveFrequency = 0
        lowestFrequency = 0
        highestFrequency = 0
        voicedFrames = 0
    }
}

private struct RangeTestPage: View {
    let rangeTest: RangeTestModel

    var body: some View {
        VStack(spacing: 20) {
            Text("내 음역대 측정")
                .font(.screenTitle)
                .foregroundColor(.white)

            if rangeTest.audio.isMicPermissionDenied {
                Text("마이크 권한이 거부되어 측정할 수 없습니다.\n설정 > 5분 보컬 > 마이크를 허용한 뒤 돌아오세요.\n(건너뛰고 나중에 피치 트래커에서 측정해도 됩니다.)")
                    .font(.caption)
                    .foregroundColor(.vocalWarning)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
            } else {
                Text("마이크를 켜고 가장 낮은 목소리부터 시작해,\n편안하게 올라갈 수 있는 최고음까지 이어 올라가세요.\n이 측정이 4주 성장 기록의 기준선이 됩니다.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.textSecondary)
                    .lineSpacing(5)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 16) {
                Text(rangeTest.isMeasuring ? rangeTest.liveNoteName : "--")
                    .font(.noteDisplay)
                    .foregroundColor(rangeTest.isMeasuring ? Color.brandSecondary : .textSecondary)
                    .contentTransition(.numericText())

                if rangeTest.isMeasuring {
                    Text(String(format: "%.1f Hz", rangeTest.liveFrequency))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.textSecondary)
                }

                HStack(spacing: 24) {
                    rangeColumn(title: "최저음", note: rangeTest.hasResult ? rangeTest.lowestNoteName : "--")
                    Divider().frame(height: 34)
                    rangeColumn(title: "최고음", note: rangeTest.hasResult ? rangeTest.highestNoteName : "--")
                }
            }
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 18, padding: 20)
            .padding(.horizontal, 28)

            HStack(spacing: 12) {
                Button {
                    rangeTest.isMeasuring ? rangeTest.pause() : rangeTest.start()
                } label: {
                    Label(
                        rangeTest.isMeasuring ? "일시정지" : (rangeTest.hasResult ? "다시 측정" : "측정 시작"),
                        systemImage: rangeTest.isMeasuring ? "pause.fill" : "mic.fill"
                    )
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(rangeTest.isMeasuring ? Color.vocalAlert : Color.brandPrimary)
                    .clipShape(Capsule())
                }

                if rangeTest.hasResult {
                    Label("측정 완료!", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.vocalSuccess)
                }
            }

            Spacer()
            Spacer()
        }
        .onDisappear {
            rangeTest.stop()
        }
    }

    private func rangeColumn(title: String, note: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.textSecondary)
            Text(note)
                .font(.title2.weight(.heavy).monospacedDigit())
                .foregroundColor(.white)
        }
    }
}
