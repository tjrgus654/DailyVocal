# 2026-09-06 — 다이내믹스 아치(메사 디 보체) 검증 증거

## 만든 것
- `Core/Logic/VocalLogic.swift` — `DynamicsMeasurement`(hasArch) + `DynamicsAnalysis`
  (dB 변환 → 중심 이동평균 5 → 아치 판독) + `dynamicsFeedback` + `dynamicsScore`
- `Tests/VocalLogicTests/DynamicsAnalysisTests.swift` — 8 테스트
- `ViewModels/PitchTrackerViewModel.swift` — `.dynamics` 모드 (guide 1.6s → record 7s),
  `SustainPhase` 공유 위상기계, 엔진 평활 RMS(`audio.amplitude`, 콜백 전 갱신 확인) 수집
- `Views/PitchTracker/PitchTrackerView.swift` — 캡션 4상태 + `DynamicsResultCard`
- `preview/live.html` — JS 미러(동일 상수·공식) + AnalyserNode 시계열 RMS 수집
- `evidence/20260903-rebuild/verify_dynamics_parity.py` — 상태+공식+실행 16축
- `tools/vibrato_ui_e2e.mjs` — 26축으로 확장(비브라토 16 + 다이내믹스 10)

## 근거
- 메사 디 보체 = 여리게→크게→여리게 왕도 훈련(Sing Sharp 앱 핵심 훈련, Google Play 설명)
- RMS 실시간 피드백과 결합한 전용 앱은 2026-09 검색에서 공백 → 차별화
- 채점 기준: 레인지 6dB+, 각 방향 3dB+, 정점 중앙 25-75%, 지터 대비 부드러움

## 실행 결과 (전부 실측)
- swift test --filter DynamicsAnalysisTests: 컴파일 오류 1([Int] 리터럴) + 어서션 오류 2(테스트 인덱스) 수정 → 8/8
- verify_dynamics_parity.py: 섹션 슬라이스 버그 수정 → ALL PASS (실행 16축은 초회부터 전부 통과 — 알고리즘 자체는 첫 구현부터 Swift와 일치)
- node tools/vibrato_ui_e2e.mjs: 26/26 (favicon 404는 판별 완료 아티팩트)
- bash verify_all.sh: 8 게이트 ALL GREEN, swift test 100/100
- CI (직전 커밋 c6b46d0): iOS typecheck success + 시뮬레이터 스모크 success

## 생략
- 실제 목소리 RMS 포락선 검증(실기기) — 합성 데시벨 포락선으로 대체
- LUFS/지각 음향 측정(Youlean류) — 상대 변화만 필요해 RMS-dB로 충분
