//
//  AudioDiagnosticsView.swift
//  DailyVocal
//
//  DEBUG BUILDS ONLY — the §6.1 on-device audio self-check
//  (MAC_BUILD_GUIDE 6.1). Launched with the `--audio-diag` argument:
//  it observes the live engine (permission, hardware format, pitch
//  callbacks, interruptions) while the tester walks the A-H protocol,
//  then exports the verdict report to the clipboard for
//  `evidence/<date>-device-audio/`.
//

#if DEBUG
import SwiftUI

struct AudioDiagnosticsView: View {

    // Matches VocalAudioEngine's installTap buffer size.
    private let tapBufferFrames = 2048
    private let audio = VocalAudioEngine.shared

    @State private var steps = AudioDiagnostics.protocolSteps
    @State private var callbacks = 0
    @State private var voicedCallbacks = 0
    @State private var observedHzMin: Double = .infinity
    @State private var observedHzMax: Double = 0
    @State private var reportCopied = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    liveCard
                    checklistCard
                    reportCard
                }
                .padding(16)
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.12))
            .navigationTitle("실기 오디오 진단")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(.cyan)
                }
            }
        }
        .onDisappear(perform: stopObserving)
    }

    // MARK: - Live engine facts

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("엔진 관측")
                .font(.headline)
                .foregroundStyle(.cyan)
            LabeledRow(label: "마이크 권한",
                       value: audio.hasMicPermission ? "허용" : "거부/미결정")
            LabeledRow(label: "엔진",
                       value: audio.isMicrophoneRunning ? "실행 중" : "정지")
            if audio.inputSampleRate > 0 {
                LabeledRow(
                    label: "입력 포맷",
                    value: String(format: "%.1fkHz · %d채널 · 버퍼 %d프레임",
                                  audio.inputSampleRate / 1000,
                                  audio.inputChannelCount, tapBufferFrames))
            }
            if callbacks > 0 {
                LabeledRow(
                    label: "피치 콜백",
                    value: "\(callbacks)회 · 유성 \(voicedPct)%")
                LabeledRow(
                    label: "관측 음역",
                    value: String(format: "%.1f~%.1fHz",
                                  min(observedHzMin, observedHzMax), observedHzMax))
            }
            LabeledRow(label: "현재 음", value: "\(audio.currentNoteName) \(centsText)")
            LabeledRow(label: "인터럽션", value: "\(audio.interruptionCount)회")
            if let error = audio.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button(audio.isMicrophoneRunning ? "측정 정지" : "측정 시작") {
                audio.isMicrophoneRunning ? stopObserving() : startObserving()
            }
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.cyan.opacity(0.18), in: Capsule())
            .foregroundStyle(.cyan)
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - A-H checklist

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("§6.1 프로토콜 A–H")
                .font(.headline)
                .foregroundStyle(.cyan)
            ForEach($steps) { $step in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(step.code) · \(step.title)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Spacer()
                        Text(step.state.rawValue)
                            .font(.caption.bold())
                            .foregroundStyle(stateColor(step.state))
                    }
                    Text(step.criterion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(AudioCheckState.allCases, id: \.self) { state in
                            Button(state.rawValue) {
                                step.state = state
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                step.state == state
                                    ? Color.cyan.opacity(0.3)
                                    : Color.white.opacity(0.08),
                                in: Capsule())
                            .foregroundStyle(step.state == state ? .cyan : .secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Report export

    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("보고서")
                .font(.headline)
                .foregroundStyle(.cyan)
            Text("복사한 내용을 evidence/<날짜>-device-audio/ 에 붙여넣으세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(reportCopied ? "복사됨 ✓" : "클립보드로 복사") {
                UIPasteboard.general.string = AudioDiagnostics.report(
                    date: .now,
                    micPermission: audio.hasMicPermission,
                    engineRunning: audio.isMicrophoneRunning,
                    sampleRate: audio.inputSampleRate,
                    channelCount: audio.inputChannelCount,
                    bufferFrames: tapBufferFrames,
                    pitchCallbacks: callbacks,
                    voicedCallbacks: voicedCallbacks,
                    observedHzMin: callbacks > 0 ? min(observedHzMin, observedHzMax) : 0,
                    observedHzMax: observedHzMax,
                    interruptions: audio.interruptionCount,
                    steps: steps)
                reportCopied = true
            }
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.cyan.opacity(0.18), in: Capsule())
            .foregroundStyle(.cyan)
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private var voicedPct: Int {
        guard callbacks > 0 else { return 0 }
        return Int((Double(voicedCallbacks) / Double(callbacks) * 100).rounded())
    }

    private var centsText: String {
        audio.centsDeviation >= 0
            ? String(format: "+%.0f¢", audio.centsDeviation)
            : String(format: "%.0f¢", audio.centsDeviation)
    }

    private func stateColor(_ state: AudioCheckState) -> Color {
        switch state {
        case .pass: return .green
        case .fail: return .red
        case .pending: return .secondary
        }
    }

    /// Owns the pitch callback while observing — the dedicated debug surface
    /// has no tracker flow to collide with.
    private func startObserving() {
        callbacks = 0
        voicedCallbacks = 0
        observedHzMin = .infinity
        observedHzMax = 0
        audio.onPitchUpdate = { frequency, _, _, voiced in
            callbacks += 1
            guard voiced, frequency > 0 else { return }
            voicedCallbacks += 1
            observedHzMin = min(observedHzMin, frequency)
            observedHzMax = max(observedHzMax, frequency)
        }
        audio.startMicrophone()
    }

    private func stopObserving() {
        audio.onPitchUpdate = nil
        audio.stopMicrophone()
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}
#endif
