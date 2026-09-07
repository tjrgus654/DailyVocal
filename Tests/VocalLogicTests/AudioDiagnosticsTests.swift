import XCTest
@testable import VocalLogic

final class AudioDiagnosticsTests: XCTestCase {

    func testProtocolStepsMatchGuideSection() {
        XCTAssertEqual(AudioDiagnostics.protocolSteps.map(\.code),
                       ["A", "B", "C", "D", "E", "F", "G", "H"])
        // Every step carries the §6.1 criterion and starts unjudged.
        for step in AudioDiagnostics.protocolSteps {
            XCTAssertFalse(step.title.isEmpty, step.code)
            XCTAssertFalse(step.criterion.isEmpty, step.code)
            XCTAssertEqual(step.state, .pending, step.code)
        }
        // The layers the protocol exists to confirm (MAC_BUILD_GUIDE 6.1).
        XCTAssertTrue(AudioDiagnostics.protocolSteps[0].title.contains("음역"))
        XCTAssertTrue(AudioDiagnostics.protocolSteps[5].title.contains("민요"))
        XCTAssertTrue(AudioDiagnostics.protocolSteps[6].title.contains("인터럽션"))
    }

    func testReportComposesEngineFacts() {
        let steps = AudioDiagnostics.protocolSteps
        let report = AudioDiagnostics.report(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            micPermission: true,
            engineRunning: true,
            sampleRate: 48_000,
            channelCount: 1,
            bufferFrames: 2048,
            pitchCallbacks: 300,
            voicedCallbacks: 200,
            observedHzMin: 96.5,
            observedHzMax: 352.1,
            interruptions: 1,
            steps: steps)
        let lines = report.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].contains("하루보컬 실기 오디오 진단"))
        XCTAssertTrue(lines[1].contains("마이크 권한: 허용") && lines[1].contains("엔진: 실행 중"))
        XCTAssertEqual(lines[2], "입력 48.0kHz · 1채널 · 버퍼 2048프레임")
        XCTAssertEqual(lines[3], "피치 콜백 300회 · 유성 67% · 관측 음역 96.5~352.1Hz")
        XCTAssertEqual(lines[4], "인터럽션 1회")
        XCTAssertTrue(report.contains("A 온보딩 음역 측정: 대기"))
        XCTAssertTrue(report.contains("H 백그라운드 전환: 대기"))
        XCTAssertTrue(report.contains("요약: 통과 0/8 · 실패 0 · 대기 8"))
    }

    func testReportHandlesSilentEngine() {
        let report = AudioDiagnostics.report(
            date: Date(),
            micPermission: false,
            engineRunning: false,
            sampleRate: 0,
            channelCount: 0,
            bufferFrames: 2048,
            pitchCallbacks: 0,
            voicedCallbacks: 0,
            observedHzMin: 0,
            observedHzMax: 0,
            interruptions: 0,
            steps: AudioDiagnostics.protocolSteps)
        // No division by zero; the silence itself is the finding.
        XCTAssertTrue(report.contains("피치 콜백 0회 · 유성 —% (마이크 입력 없음)"))
        XCTAssertTrue(report.contains("마이크 권한: 거부/미결정"))
        XCTAssertTrue(report.contains("엔진: 정지"))
        XCTAssertTrue(report.contains("입력 0.0kHz"))
    }

    func testReportCountsVerdicts() {
        var steps = AudioDiagnostics.protocolSteps
        steps[0].state = .pass
        steps[1].state = .pass
        steps[2].state = .fail
        let report = AudioDiagnostics.report(
            date: Date(),
            micPermission: true,
            engineRunning: true,
            sampleRate: 48_000,
            channelCount: 1,
            bufferFrames: 2048,
            pitchCallbacks: 10,
            voicedCallbacks: 9,
            observedHzMin: 100,
            observedHzMax: 200,
            interruptions: 0,
            steps: steps)
        XCTAssertTrue(report.contains("A 온보딩 음역 측정: 통과"))
        XCTAssertTrue(report.contains("C 비브라토 체크: 실패"))
        XCTAssertTrue(report.contains("요약: 통과 2/8 · 실패 1 · 대기 5"))
    }
}
