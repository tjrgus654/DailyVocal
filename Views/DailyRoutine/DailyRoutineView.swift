//
//  DailyRoutineView.swift
//  5VocalMaster
//
//  15-minute routine screen: circular step timer, step dots, step detail
//  card with live feedback, guide-tone settings, and transport controls.
//

import SwiftUI
import SwiftData

public struct DailyRoutineView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DailyRoutineViewModel()

    public init() {}

    public var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 14) {
                headerView

                Picker("루틴 모드", selection: Binding(
                    get: { viewModel.mode },
                    set: { viewModel.setMode($0) }
                )) {
                    Text("15분 풀코스").tag(DailyRoutineViewModel.RoutineMode.full)
                    Text("2분 퀵").tag(DailyRoutineViewModel.RoutineMode.quick)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                voiceConditionBar
                    .padding(.horizontal, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        circularTimerSection
                        stepIndicatorView
                        StepDetailCard(step: viewModel.currentStep)
                            .padding(.horizontal, 20)
                        audioSettingsCard
                            .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 16)
                }

                bottomControlsBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
            }
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
        }
        .onDisappear {
            viewModel.pause()
        }
        .alert(
            "오늘 성대 컨디션",
            isPresented: Binding(
                get: { viewModel.restNotice != nil },
                set: { if !$0 { viewModel.restNotice = nil } }
            )
        ) {
            Button("확인", role: .cancel) { viewModel.restNotice = nil }
        } message: {
            Text(viewModel.restNotice ?? "")
        }
        .alert(
            completionAlertTitle,
            isPresented: Binding(
                get: { viewModel.isSessionCompleted },
                set: { if !$0 { viewModel.reset() } }
            )
        ) {
            Button("확인", role: .cancel) { viewModel.reset() }
        } message: {
            if viewModel.isVoiceRestRecommended {
                Text("오늘 \(viewModel.sessionsCompletedToday)회째 완료! 성대 회복을 위해 물을 마시고 허밍·립트릴 쿨다운을 충분히 해주세요. 무리한 반복은 피로만 쌓입니다.")
            } else if viewModel.mode == .quick {
                Text("2분으로도 성대는 깨어났어요.\n여유가 생기면 15분 풀코스도 이어가 보세요.")
            } else if viewModel.mode == .rest {
                Text("오늘은 쉬어가는 것만으로 충분해요.\n내일 컨디션이 좋으면 풀코스로 돌아옵니다.")
            } else {
                Text("목에 힘을 뺀 채 완주했어요.\n내일도 15분이면 충분해요.")
            }
        }
    }

    private var completionAlertTitle: String {
        switch viewModel.mode {
        case .quick: return "오늘 2분 퀵 루틴을 마쳤어요"
        case .rest: return "쉬는 날 루틴을 마쳤어요"
        case .full: return "오늘 15분 루틴을 마쳤어요"
        }
    }

    /// Daily voice-condition check. "아픔" silently swaps the routine for the
    /// minimal-SOVT rest day — a sore voice must not run the normal workload.
    private var voiceConditionBar: some View {
        HStack(spacing: 8) {
            Text("오늘 목 상태")
                .font(.caption2)
                .foregroundColor(.textSecondary)
            Spacer()
            ForEach(DailyRoutineViewModel.VocalCondition.allCases) { condition in
                Button {
                    viewModel.vocalCondition = condition
                } label: {
                    Text(conditionLabel(condition))
                        .font(.caption2.weight(.bold))
                        .foregroundColor(viewModel.vocalCondition == condition ? .white : .textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.vocalCondition == condition
                                ? (condition == .sore ? Color.vocalAlert : Color.brandPrimary)
                                : Color.white.opacity(0.06)
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .glassCard(cornerRadius: 14, padding: 10)
        .overlay(alignment: .bottom) {
            if viewModel.vocalCondition == .sore {
                Text("아픔이 2일 이상 계속되면 이비인후과 진료를 받아보세요.")
                    .font(.caption2)
                    .foregroundColor(.vocalWarning)
                    .padding(.bottom, -22)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func conditionLabel(_ condition: DailyRoutineViewModel.VocalCondition) -> String {
        switch condition {
        case .good: return "좋음"
        case .tired: return "피곤함"
        case .sore: return "아픔"
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("5분 보컬")
                    .font(.eyebrow)
                    .foregroundColor(.brandSecondary)
                Text("일일 루틴")
                    .font(.screenTitle)
                    .foregroundColor(.white)
            }
            Spacer()

            MicActiveIndicator()

            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.vocalWarning)
                Text(weekBadgeText)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassCard(cornerRadius: 12, padding: 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var weekBadgeText: String {
        if viewModel.mode == .rest { return "쉬는 날" }
        if viewModel.isMaintenanceMode {
            return "유지 모드"
        }
        let titles = ["1주차: 힘빼기", "2주차: 가성 스위치", "3주차: 파사지오", "4주차: 실전 완성"]
        return titles[viewModel.trainingWeek - 1]
    }

    // MARK: - Circular timer

    private var circularTimerSection: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 13)
                .frame(width: 258, height: 258)

            Circle()
                .trim(from: 0, to: CGFloat(viewModel.currentStepProgress))
                .stroke(
                    LinearGradient.timerRing,
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 258, height: 258)
                .shadow(color: Color.brandPrimary.opacity(0.35), radius: 14, x: 0, y: 2)
                .animation(.linear(duration: 0.3), value: viewModel.currentStepProgress)

            VStack(spacing: 8) {
                Text("Step \(viewModel.currentStepIndex + 1)/\(viewModel.routineSteps.count)")
                    .font(.eyebrow)
                    .foregroundColor(.brandSecondary)

                Text(viewModel.formattedRemainingTime)
                    .font(.timerDisplay)
                    .foregroundColor(remainingColor)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: viewModel.remainingSeconds)
                    .scaleEffect(pulseScale)
                    .animation(.bouncy(duration: 0.35), value: pulseScale)

                GuideNoteBadge(idleTitle: viewModel.currentStep.title)
            }
        }
        .padding(.vertical, 6)
    }

    // Final-3-seconds countdown treatment (workout-app pattern): the numeral
    // turns cyan and pulses once per tick.
    private var remainingColor: Color {
        viewModel.remainingSeconds <= 3 && viewModel.isTimerRunning ? .brandSecondary : .white
    }

    private var pulseScale: CGFloat {
        viewModel.remainingSeconds <= 3 && viewModel.isTimerRunning
            && viewModel.remainingSeconds > 0 ? 1.12 : 1.0
    }

    // MARK: - Step dots

    private var stepIndicatorView: some View {
        HStack(spacing: 12) {
            ForEach(0..<viewModel.routineSteps.count, id: \.self) { index in
                Circle()
                    .fill(index < viewModel.currentStepIndex ? Color.vocalSuccess
                         : index == viewModel.currentStepIndex ? Color.brandPrimary
                         : Color.white.opacity(0.2))
                    .frame(
                        width: index == viewModel.currentStepIndex ? 14 : 9,
                        height: index == viewModel.currentStepIndex ? 14 : 9
                    )
                    .overlay(
                        Circle().stroke(
                            index == viewModel.currentStepIndex ? Color.brandSecondary : Color.clear,
                            lineWidth: 2
                        )
                    )
                    .animation(.spring(response: 0.3), value: viewModel.currentStepIndex)
            }
        }
    }

    // MARK: - Guide-tone settings

    @AppStorage("prefersHigherKeyGuide") private var prefersHigherKeyGuide = false
    @AppStorage("guideTranspose") private var guideTranspose = 0

    private var audioSettingsCard: some View {
        VStack(spacing: 12) {
            Toggle(isOn: Bindable(viewModel).isScaleAutoPlayEnabled) {
                HStack(spacing: 8) {
                    Image(systemName: "pianokeys")
                        .foregroundColor(.brandSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("피아노 가이드 톤 자동 재생")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text("스텝별 최적 스케일을 들으며 따라 부르기")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .tint(Color.brandPrimary)

            if viewModel.isScaleAutoPlayEnabled {
                Divider().background(Color.borderGlass)

                Picker("가이드 톤 키", selection: $prefersHigherKeyGuide) {
                    Text("남성 키 (C3 기준)").tag(false)
                    Text("여성 키 (C4 기준)").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: prefersHigherKeyGuide) { _, newValue in
                    viewModel.syncProfileKeyPreference(newValue)
                }

                Stepper(value: $guideTranspose, in: -5...5) {
                    HStack {
                        Text("키 미세조정")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text(guideTranspose == 0 ? "원키" : (guideTranspose > 0 ? "+\(guideTranspose)키" : "\(guideTranspose)키"))
                            .font(.caption)
                            .foregroundColor(.brandSecondary)
                    }
                }
                .onChange(of: guideTranspose) { _, newValue in
                    viewModel.sequencer.setTranspose(newValue)
                    HapticManager.shared.buttonTap()
                }
                .onAppear {
                    viewModel.sequencer.setTranspose(guideTranspose)
                }
            }
        }
        .glassCard(cornerRadius: 16, padding: 14)
    }

    // MARK: - Transport

    private var bottomControlsBar: some View {
        HStack(spacing: 24) {
            Button(action: viewModel.previousStep) {
                Image(systemName: "backward.fill")
                    .font(.title3)
                    .foregroundColor(viewModel.currentStepIndex > 0 ? .white : .white.opacity(0.3))
                    .frame(width: 52, height: 52)
                    .background(Color.surfaceDark)
                    .clipShape(Circle())
            }
            .disabled(viewModel.currentStepIndex == 0)

            Button(action: viewModel.togglePlayPause) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isTimerRunning ? "pause.fill" : "play.fill")
                        .font(.title2)
                    Text(viewModel.isTimerRunning ? "일시정지" : "루틴 시작")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(LinearGradient.primaryButton)
                .clipShape(Capsule())
                .shadow(color: Color.brandPrimary.opacity(0.5), radius: 10, y: 4)
            }

            Button(action: viewModel.nextStep) {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.surfaceDark)
                    .clipShape(Circle())
            }
        }
    }
}

/// Live mic indicator (App Review 2.5.14: a clear visual indication while
/// recording/analyzing). Isolated leaf so its state change doesn't re-render
/// the routine screen.
private struct MicActiveIndicator: View {
    let audio = VocalAudioEngine.shared

    var body: some View {
        if audio.isMicrophoneRunning {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.vocalAlert)
                    .frame(width: 6, height: 6)
                Text("분석 중")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
        }
    }
}

/// Guide-note badge shown inside the timer. Isolated so the ~2 Hz sequencer
/// updates don't re-render the whole routine screen.
private struct GuideNoteBadge: View {
    let idleTitle: String
    let sequencer = ScaleSequencer.shared

    var body: some View {
        if sequencer.isPlaying {
            HStack(spacing: 4) {
                Image(systemName: "music.note")
                    .font(.caption2)
                    .foregroundColor(.brandAccent)
                Text(sequencer.currentNoteName)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.brandAccent)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.brandAccent.opacity(0.15))
            .clipShape(Capsule())
        } else {
            Text(idleTitle)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
        }
    }
}
