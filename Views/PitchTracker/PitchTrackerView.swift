//
//  PitchTrackerView.swift
//  DailyVocal
//
//  Real-time pitch coaching screen. The live note display reads the audio
//  engine directly (isolated subview), history/accuracy/target come from the
//  tracking view model.
//

import SwiftUI
import SwiftData
import UIKit

public struct PitchTrackerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = PitchTrackerViewModel()

    private let targetNotes = ["C3", "E3", "G3", "A3", "C4", "D4", "E4", "F4", "G4", "A4", "C5"]

    public init() {}

    public var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 14) {
                headerSection

                if viewModel.audio.isMicPermissionDenied {
                    PermissionGuideCard()
                    Spacer()
                } else {
                    if viewModel.isListenFirstMode && viewModel.isListening {
                        ListenFirstVeil()
                    } else {
                        LiveNoteDisplay(targetNoteName: viewModel.activeTargetName)
                    }

                    PianoStrip(targetNoteName: viewModel.activeTargetName)
                        .padding(.horizontal, 20)

                    PitchCanvasSection(viewModel: viewModel)

                    if viewModel.lastSessionScore != nil {
                        NoteHistogramCard(binCounts: viewModel.noteBinCounts)
                            .padding(.horizontal, 20)
                    }

                    if viewModel.mode == .vibrato,
                       viewModel.vibratoPhase == .done,
                       let result = viewModel.vibratoResult {
                        VibratoResultCard(result: result, tips: viewModel.vibratoTips)
                    }

                    if viewModel.mode == .dynamics,
                       viewModel.dynamicsPhase == .done,
                       let result = viewModel.dynamicsResult {
                        DynamicsResultCard(result: result, tips: viewModel.dynamicsTips)
                    }

                    modePicker
                        .padding(.horizontal, 20)

                    if viewModel.mode == .echo {
                        Text(viewModel.echoLevel >= 3
                             ? "에코 난이도 3단계 · 최고 난이도입니다"
                             : "에코 난이도 \(viewModel.echoLevel)단계 · 성공하면 이동 폭이 넓어져요")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    if viewModel.mode == .scale {
                        let pattern = VocalLogic.scalePattern(level: viewModel.echoLevel)
                        Text("패턴: \(pattern.rawValue) · 시작음 \(viewModel.targetNoteName) — 데모 후 노트마다 따라 부르세요\(viewModel.echoLevel >= 3 ? "" : " · 성공하면 다음 단계 패턴으로")")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    if viewModel.mode == .vowel {
                        Text("목표 모음: \(viewModel.vowelTarget.rawValue) — 소리를 듣고 그대로 따라 하세요")
                            .font(.caption2)
                            .foregroundColor(.brandSecondary)
                            .frame(maxWidth: .infinity)
                        if !viewModel.lastVowelTips.isEmpty {
                            Text(viewModel.lastVowelTips.joined(separator: "\n"))
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    if viewModel.mode == .vibrato {
                        Text(viewModel.vibratoPhase == .guide
                             ? "기준음이 먼저 울립니다 — 같은 음을 5초간 길게 끌며 비브라토를 넣어보세요"
                             : (viewModel.vibratoPhase == .recording
                                ? "지금 길게 '아~' — 목소리를 자연스럽게 흔들어보세요"
                                : (viewModel.vibratoResult != nil
                                   ? "측정 완료 — 결과 카드를 확인하세요"
                                   : "시작하면 기준음이 울립니다 — 그 음을 길게 끌며 비브라토를 넣어보세요")))
                            .font(.caption2)
                            .foregroundColor(.brandSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    if viewModel.mode == .dynamics {
                        Text(viewModel.dynamicsPhase == .guide
                             ? "기준음이 먼저 울립니다 — 그 음을 한 호흡으로 여리게 → 크게 → 여리게"
                             : (viewModel.dynamicsPhase == .recording
                                ? "지금 '아~'를 여리게 시작해 점점 크게, 다시 여리게 — 숨을 아껴가며"
                                : (viewModel.dynamicsResult != nil
                                   ? "측정 완료 — 아래 아치 결과를 확인하세요"
                                   : "메사 디 보체: 한 음을 셈→여림으로 부풀렸다가 줄이는 왕도 훈련입니다")))
                            .font(.caption2)
                            .foregroundColor(.brandSecondary)
                            .frame(maxWidth: .infinity)
                    }

                    targetNoteSelectorBar
                        .padding(.horizontal, 20)

                    tuningReferenceBar
                        .padding(.horizontal, 20)

                    Spacer(minLength: 4)

                measureControlButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                }
            }
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
            // One-shot deep link from the growth dashboard's recommendation.
            if let mode = AppRouter.shared.pendingTrackerMode {
                viewModel.mode = mode
                AppRouter.shared.pendingTrackerMode = nil
            }
        }
        .onDisappear {
            viewModel.stopTracking()
            viewModel.clearEngineCallback()
        }
        .alert(
            "이번 세션 \(viewModel.lastSessionScore ?? 0)점",
            isPresented: Binding(
                get: { viewModel.lastSessionScore != nil },
                set: { if !$0 { viewModel.dismissScoreAlert() } }
            )
        ) {
            Button("확인", role: .cancel) { viewModel.dismissScoreAlert() }
        } message: {
            Text(alertMessageText)
        }
    }

    private var alertMessageText: String {
        let label = viewModel.lastSessionTargetLabel
        var text = "등급 \(viewModel.lastSessionGrade) · 목표음 \(label.isEmpty ? viewModel.targetNoteName : label) 온피치 \(Int(viewModel.accuracyScore.rounded()))%"
        if let sustain = viewModel.lastSustainTip, viewModel.mode == .single {
            text += "\n\(sustain)"
        }
        if let delta = viewModel.lastEchoLevelDelta {
            text += delta > 0
                ? "\n에코 난이도가 \(viewModel.echoLevel)단계로 올라갔어요. 이동 폭이 넓어져요."
                : "\n에코 난이도가 \(viewModel.echoLevel)단계로 조정됐어요. 편한 폭으로 다시 시작해요."
        }
        text += "\n결과는 성장 기록에 반영됩니다."
        return text
    }

    /// A4 reference tuning: keeps note naming and cents aligned with whatever
    /// the user sings along to (435...445 Hz, 0.5 Hz steps). @AppStorage is
    /// the observable mirror of the engine's UserDefaults-backed value, so
    /// the label updates the moment a stepper is tapped.
    @AppStorage("referenceA4") private var referenceA4Raw = 0.0
    private var displayedA4: Double {
        VocalLogic.clampedA4(referenceA4Raw)
    }

    private var tuningReferenceBar: some View {
        HStack(spacing: 10) {
            Text("기준 피치 A4")
                .font(.caption2)
                .foregroundColor(.textSecondary)
            Spacer()
            Button {
                referenceA4Raw = displayedA4 - 0.5
                hapticTick()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("기준 피치 0.5 헤르츠 내리기")
            Text(String(format: "%.1f Hz", displayedA4))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundColor(.white)
                .frame(minWidth: 64)
            Button {
                referenceA4Raw = displayedA4 + 0.5
                hapticTick()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("기준 피치 0.5 헤르츠 올리기")
        }
        .glassCard(cornerRadius: 14, padding: 10)
    }

    private func hapticTick() {
        HapticManager.shared.buttonTap()
    }

    // MARK: - Mode

    /// 단음 유지 vs 에코 3음 (Pfordresher 2024: 넓은 음역 모방 훈련이 음정
    /// 매칭 실력을 올리는 유일한 실험 입증 드릴).
    private var modePicker: some View {
        @Bindable var vm = viewModel
        return Picker("훈련 모드", selection: $vm.mode) {
            ForEach(PitchTrackerViewModel.TrackerMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("실시간 음정 코칭")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.brandSecondary)
                Text("피치 트래커")
                    .font(.screenTitle)
                    .foregroundColor(.white)
            }
            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isListening ? Color.vocalSuccess : Color.textSecondary)
                    .frame(width: 8, height: 8)
                Text(viewModel.isListening ? "감지 중" : "대기")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCard(cornerRadius: 10, padding: 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    // MARK: - Target selector

    private var targetNoteSelectorBar: some View {
        HStack {
            Text(viewModel.mode == .echo ? "시작음:" : "목표음:")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(targetNotes, id: \.self) { note in
                        Button(action: { viewModel.setTargetNote(note) }) {
                            Text(note)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(note == viewModel.targetNoteName ? .white : .textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(note == viewModel.targetNoteName ? Color.brandPrimary : Color.surfaceDark)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Listen-first ear training toggle (visuals hidden while singing)
            Button(action: {
                viewModel.isListenFirstMode.toggle()
                HapticManager.shared.buttonTap()
            }) {
                Image(systemName: viewModel.isListenFirstMode ? "headphones" : "headphones")
                    .font(.caption)
                    .foregroundColor(viewModel.isListenFirstMode ? .black : .white)
                    .frame(width: 32, height: 32)
                    .background(viewModel.isListenFirstMode ? Color.brandSecondary : Color.surfaceDark)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(
                            viewModel.isListenFirstMode ? Color.clear : Color.borderGlass,
                            lineWidth: 1
                        )
                    )
            }

            Button(action: viewModel.playTargetTone) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.brandAccent)
                    .clipShape(Circle())
            }
        }
        .glassCard(cornerRadius: 14, padding: 10)
    }

    // MARK: - Measure control

    private var measureControlButton: some View {
        Button(action: {
            viewModel.isListening ? viewModel.stopTracking() : viewModel.startTracking()
        }) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isListening ? "stop.fill" : "mic.fill")
                    .font(.headline)
                Text(viewModel.isListening ? "측정 종료" : "실시간 피치 측정 시작")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(viewModel.isListening ? Color.vocalAlert : Color.brandPrimary)
            .cornerRadius(DesignLayout.cornerRadiusButton)
            .shadow(
                color: (viewModel.isListening ? Color.vocalAlert : Color.brandPrimary).opacity(0.4),
                radius: 10, y: 4
            )
        }
    }
}

/// Canvas + live stats, isolated so the ~23 Hz history updates re-render only
/// this leaf instead of the whole tracker screen.
private struct PitchCanvasSection: View {
    let viewModel: PitchTrackerViewModel

    var body: some View {
        VStack(spacing: 14) {
            if viewModel.isListenFirstMode && viewModel.isListening {
                VStack(spacing: 10) {
                    Image(systemName: "headphones")
                        .font(.system(size: 34))
                        .foregroundColor(.brandSecondary)
                    Text("귀에만 집중하세요")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("방금 들은 목표음을 기억해 그대로 불러보세요.\n측정을 종료하면 궤적과 점수가 공개됩니다.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: DesignLayout.cornerRadiusCard, padding: 0)
                .padding(.horizontal, 20)
            } else {
                PitchLineCanvas(
                    history: viewModel.pitchHistory,
                    targetNoteName: viewModel.activeTargetName,
                    targetFrequency: viewModel.activeTargetFrequency,
                    echoTargetFrequencies: viewModel.echoTargetMidis.map {
                        VocalAudioEngine.frequency(forMidi: Double($0))
                    },
                    activeEchoIndex: viewModel.activeEchoIndex
                )
                .frame(height: 210)
                .glassCard(cornerRadius: DesignLayout.cornerRadiusCard, padding: 0)
                .padding(.horizontal, 20)

                statsRow

                // Explicit numeric thresholds beat binary pass/fail: they teach
                // the *pattern* of one's own error (e.g. "always ~20¢ flat on
                // descending lines") — the pitch-monitor design consensus.
                Text("🟢 ±12센트 이내 = 정확 · 🟡 ±35센트 = 살짝 벗어남 · 🔴 그 이상 = 크게 빗나감")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
            }
        }
    }

    private var statsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("목표음 주파수")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                Text(String(format: "%.1f Hz", viewModel.activeTargetFrequency))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .monospacedDigit()
            }

            Spacer()

            Divider()
                .frame(height: 30)
                .background(Color.borderGlass)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("이번 세션 정확도")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                Text(String(format: "%.0f%%", viewModel.accuracyScore))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(viewModel.accuracyScore >= 70 ? .vocalSuccess : .brandSecondary)
                    .monospacedDigit()
            }
        }
        .glassCard(cornerRadius: 16, padding: 14)
        .padding(.horizontal, 20)
    }
}

/// Post-session pitch-class distribution (C...B, octaves folded) — the
/// "mirror for your ear": which notes the voice actually used most.
private struct NoteHistogramCard: View {
    let binCounts: [Int]
    private let labels = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("이번 세션 음 분포")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Text("어떤 음에 목소리가 머무는지 보여줍니다")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(binCounts.enumerated()), id: \.offset) { index, count in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(count > 0 ? Color.brandSecondary : Color.white.opacity(0.08))
                            .frame(height: max(4, CGFloat(count) / CGFloat(max(binCounts.max() ?? 1, 1)) * 56))
                        Text(labels[index])
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .glassCard(cornerRadius: 16, padding: 14)
    }
}

/// Vibrato measurement readout: oscillation rate, extent, periodicity, and
/// the coaching lines derived from them (literature band: 4.5–6.5 Hz,
/// ±50–150 cents — Nix 2016; JASA 2022).
private struct VibratoResultCard: View {
    let result: VocalLogic.VibratoMeasurement
    let tips: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("비브라토 분석")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Text(result.hasVibrato ? "비브라토 감지 ✓" : "감지 안 됨")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(result.hasVibrato ? .vocalSuccess : .vocalWarning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (result.hasVibrato ? Color.vocalSuccess : Color.vocalWarning).opacity(0.18)
                    )
                    .clipShape(Capsule())
            }

            HStack(spacing: 0) {
                metric(
                    title: "속도",
                    value: result.rateHz > 0 ? String(format: "%.1f Hz", result.rateHz) : "—",
                    reference: "이상적 4.5~6.5"
                )
                metricDivider
                metric(
                    title: "진폭",
                    value: result.extentCents > 0 ? "±\(Int(result.extentCents.rounded()))¢" : "—",
                    reference: "목표 ±50~100¢"
                )
                metricDivider
                metric(
                    title: "규칙성",
                    value: "\(Int((result.regularity * 100).rounded()))%",
                    reference: "주기 일관성"
                )
            }

            ForEach(tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundColor(.brandSecondary)
                    Text(tip)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .glassCard(cornerRadius: 16, padding: 14)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    private var metricDivider: some View {
        Divider()
            .frame(height: 34)
            .background(Color.borderGlass)
            .padding(.horizontal, 10)
    }

    private func metric(title: String, value: String, reference: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.textSecondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .monospacedDigit()
            Text(reference)
                .font(.system(size: 9))
                .foregroundColor(.textSecondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Messa di voce readout: dynamic range, crescendo/decrescendo legs, apex
/// position, envelope smoothness, plus coaching lines.
private struct DynamicsResultCard: View {
    let result: VocalLogic.DynamicsMeasurement
    let tips: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("다이내믹스 아치")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Text(result.hasArch ? "아치 완성 ✓" : "아치 미완성")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(result.hasArch ? .vocalSuccess : .vocalWarning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (result.hasArch ? Color.vocalSuccess : Color.vocalWarning).opacity(0.18)
                    )
                    .clipShape(Capsule())
            }

            HStack(spacing: 0) {
                metric(
                    title: "레인지",
                    value: String(format: "%.1f dB", result.rangeDb),
                    reference: "목표 6dB+"
                )
                metricDivider
                metric(
                    title: "셈→여림",
                    value: String(format: "+%.1f/−%.1f dB", result.crescendoDb, result.decrescendoDb),
                    reference: "각 3dB+"
                )
                metricDivider
                metric(
                    title: "정점",
                    value: "\(Int((result.peakPosition * 100).rounded()))%",
                    reference: "중앙 25~75%"
                )
            }

            ForEach(tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundColor(.brandSecondary)
                    Text(tip)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .glassCard(cornerRadius: 16, padding: 14)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    private var metricDivider: some View {
        Divider()
            .frame(height: 34)
            .background(Color.borderGlass)
            .padding(.horizontal, 10)
    }

    private func metric(title: String, value: String, reference: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.textSecondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .monospacedDigit()
            Text(reference)
                .font(.system(size: 9))
                .foregroundColor(.textSecondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Placeholder shown instead of the live note readout while singing in
/// listen-first mode.
private struct ListenFirstVeil: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.title3)
                .foregroundColor(.brandSecondary)
            Text("듣고 부르기 진행 중: 시각 피드백 숨김")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
        }
        .frame(height: 62)
    }
}

/// Shown when the user has explicitly denied microphone access
/// (App Review 2.5.14 also expects a clear in-app recording indicator,
/// which the 감지 중 badge and this card provide).
private struct PermissionGuideCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 40))
                .foregroundColor(.vocalWarning)

            Text("마이크 권한이 필요합니다")
                .font(.headline)
                .foregroundColor(.white)

            Text("실시간 음정 분석은 기기 안에서만 처리되고\n어디에도 전송되지 않습니다.\n설정 > 하루보컬 > 마이크를 허용해주세요.")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text("설정 앱으로 이동")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(LinearGradient.primaryButton)
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .glassCard(cornerRadius: 16, padding: 18)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

/// Diatonic keyboard strip (C3...C5). Isolated so engine note changes only
/// redraw the strip.
private struct PianoStrip: View {
    let targetNoteName: String
    let audio = VocalAudioEngine.shared

    private static let notes: [String] = {
        let degrees = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24]
        return degrees.map { degree in
            VocalAudioEngine.noteAndCents(
                fromFrequency: VocalAudioEngine.frequency(forMidi: Double(48 + degree))
            ).note
        }
    }()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.notes, id: \.self) { note in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(keyColor(for: note))
                        .frame(height: 36)
                    Text(note)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(note == audio.currentNoteName ? .brandSecondary : .textSecondary)
                }
            }
        }
        .padding(8)
        .glassCard(cornerRadius: 12, padding: 6)
    }

    private func keyColor(for note: String) -> Color {
        if note == audio.currentNoteName {
            return Color.brandSecondary
        } else if note == targetNoteName {
            return Color.brandPrimary.opacity(0.8)
        } else {
            return Color.white.opacity(0.12)
        }
    }
}

/// Big current-note readout. Isolated so engine frame updates (~23 Hz) only
/// redraw this block and the canvas, not the whole tracker screen.
public struct LiveNoteDisplay: View {
    let targetNoteName: String
    let audio = VocalAudioEngine.shared

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(audio.currentNoteName)
                .font(.noteDisplay)
                .foregroundColor(noteColor)
                .contentTransition(.numericText())

            if audio.currentFrequency > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%+.0f¢", audio.centsDeviation))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(noteColor)
                    Text(String(format: "%.1f Hz", audio.currentFrequency))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .frame(height: 62)
    }

    private var noteColor: Color {
        guard audio.currentFrequency > 0 else { return .textSecondary }
        guard let targetMidi = VocalAudioEngine.midiNumber(forNoteName: targetNoteName) else {
            return .brandSecondary
        }
        let currentMidi = VocalAudioEngine.noteAndCents(fromFrequency: audio.currentFrequency).midi
        guard currentMidi == targetMidi else { return .brandSecondary }
        // Perceptual thresholds: ±12¢ audible to untrained ears, ±35¢ clearly off.
        if abs(audio.centsDeviation) <= 12 { return .vocalSuccess }
        if abs(audio.centsDeviation) <= 35 { return .vocalWarning }
        return .vocalAlert
    }
}
