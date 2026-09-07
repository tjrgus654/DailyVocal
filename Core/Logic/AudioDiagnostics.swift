//
//  AudioDiagnostics.swift
//  DailyVocal
//
//  Pure logic for the on-device audio self-check (MAC_BUILD_GUIDE §6.1).
//  The 10-minute protocol used to be a manual table; the debug diagnostics
//  screen now observes the engine live and composes this report, so the
//  last release blocker (physical-mic confirmation) is a one-tap export
//  instead of hand-written notes. Step A-F verdicts still need a human ear
//  — the checklist records them, the composer formats them.
//

import Foundation

/// Per-step verdict of the §6.1 protocol checklist.
public enum AudioCheckState: String, Codable, CaseIterable {
    case pending = "대기"
    case pass = "통과"
    case fail = "실패"
}

/// One row of the §6.1 protocol (A-H), its pass criterion and verdict.
public struct AudioChecklistStep: Identifiable, Equatable {
    public let code: String
    public let title: String
    public let criterion: String
    public var state: AudioCheckState

    public var id: String { code }

    public init(code: String, title: String, criterion: String,
                state: AudioCheckState = .pending) {
        self.code = code
        self.title = title
        self.criterion = criterion
        self.state = state
    }
}

public enum AudioDiagnostics {

    /// The §6.1 ten-minute protocol, verbatim criteria — device build only.
    public static let protocolSteps: [AudioChecklistStep] = [
        AudioChecklistStep(
            code: "A", title: "온보딩 음역 측정",
            criterion: "궤적이 글라이딩을 추적, 최저/최고음 저장"),
        AudioChecklistStep(
            code: "B", title: "단음 유지 15초",
            criterion: "얼럿에 '최장 지속 ≥ 14초'(호흡 지원 지문)"),
        AudioChecklistStep(
            code: "C", title: "비브라토 체크",
            criterion: "결과 카드에 속도 4~7Hz·규칙성 표시(일부러 흔들면)"),
        AudioChecklistStep(
            code: "D", title: "셈여림 아치",
            criterion: "여림→셈→여림 후 레인지 ≥ 6dB 인정"),
        AudioChecklistStep(
            code: "E", title: "화음 부르기",
            criterion: "드론 2초 후 성부 유지, 방향 피드백 표시"),
        AudioChecklistStep(
            code: "F", title: "민요 1곡(아리랑)",
            criterion: "데모 청취 후 노트별 창 이동, 점수 저장"),
        AudioChecklistStep(
            code: "G", title: "인터럽션",
            criterion: "측정 중 전화 수신 거절 → 세션이 깨끗이 종료"),
        AudioChecklistStep(
            code: "H", title: "백그라운드 전환",
            criterion: "홈 화면 10초 → 복귀 시 측정 계속 or 정상 종료"),
    ]

    /// Text report for `evidence/<date>-device-audio/` — everything the
    /// engine observed plus the human verdicts, ready to paste.
    public static func report(
        date: Date,
        micPermission: Bool,
        engineRunning: Bool,
        sampleRate: Double,
        channelCount: Int,
        bufferFrames: Int,
        pitchCallbacks: Int,
        voicedCallbacks: Int,
        observedHzMin: Double,
        observedHzMax: Double,
        interruptions: Int,
        steps: [AudioChecklistStep]
    ) -> String {
        let stamp = Self.stampFormatter.string(from: date)
        var lines: [String] = []
        lines.append("하루보컬 실기 오디오 진단 — \(stamp)")
        let permission = micPermission ? "허용" : "거부/미결정"
        let running = engineRunning ? "실행 중" : "정지"
        lines.append("마이크 권한: \(permission) | 엔진: \(running)")
        let khz = String(format: "%.1f", sampleRate / 1000)
        lines.append(
            "입력 \(khz)kHz · \(channelCount)채널 · 버퍼 \(bufferFrames)프레임")
        if pitchCallbacks > 0 {
            let voicedPct = Int((Double(voicedCallbacks) / Double(pitchCallbacks) * 100).rounded())
            let hzMin = String(format: "%.1f", observedHzMin)
            let hzMax = String(format: "%.1f", observedHzMax)
            lines.append(
                "피치 콜백 \(pitchCallbacks)회 · 유성 \(voicedPct)% · 관측 음역 \(hzMin)~\(hzMax)Hz")
        } else {
            lines.append("피치 콜백 0회 · 유성 —% (마이크 입력 없음)")
        }
        lines.append("인터럽션 \(interruptions)회")
        lines.append("")
        for step in steps {
            lines.append("\(step.code) \(step.title): \(step.state.rawValue)")
        }
        let failed = steps.filter { $0.state == .fail }.count
        let passed = steps.filter { $0.state == .pass }.count
        lines.append("")
        lines.append("요약: 통과 \(passed)/\(steps.count) · 실패 \(failed) · 대기 \(steps.count - passed - failed)")
        return lines.joined(separator: "\n")
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
