# 2026-09-05 — 비브라토 체크 기능 검증 증거

## 무엇을 만들었나
- `Core/Logic/VocalLogic.swift` — `VibratoMeasurement` + `VibratoAnalysis`
  (analyze(frequencies:frameRate:) / analyze(times:frequencies:) 오버로드,
  normalizedCorrelation, cycleExtentCents) + `vibratoFeedback` + `vibratoScore`
- `Tests/VocalLogicTests/VibratoAnalysisTests.swift` — 9 테스트
- `ViewModels/PitchTrackerViewModel.swift` — `.vibrato` 모드 (guide 1.6s → record 5.5s → 분석)
- `Views/PitchTracker/PitchTrackerView.swift` — 안내 캡션 4상태 + `VibratoResultCard`
- `preview/live.html` — JS 미러(동일 상수·공식·harmonic 게이트) + 모드칩/캡션/결과카드
- `evidence/20260903-rebuild/verify_vibrato_parity.py` — 상수+공식+실행 15축 패리티
- `tools/vibrato_ui_e2e.mjs` — headless Edge 16축 UI E2E

## 근거 (왜 이 기준인가)
- 속도 밴드 3.5–8.5Hz / 이상적 4.5–6.5Hz: Nix 2016(J Voice), JASA 2022(4.5–6.5Hz)
- 진폭 센트 단위(100¢=반음), 목표 ±50–100¢: 측정 문헌 통례
- 경쟁: Sing Sharp "Vibrato Pro"가 2026년 상위 iOS 보컬 앱 차별점 (웹 리서치)

## 테스트가 실제로 잡은 결함 (3건 — "테스트 통과"가 아니라 테스트가 일한 증거)
1. **3Hz 워블 오탐**: 대역 내(3.5–8.5Hz) 위상지연 상관 피크가 3.6Hz로 측정됨
   → 배주기 일관성 검사(2×lag 상관 ≥ 0) 추가로 해결. 3Hz의 2×lag 상관은 음수.
2. **무성 프레임 왜곡**: voiced-only 트레이스는 불균일 간격 → 5.0Hz가 5.55Hz로
   → times 오버로드가 중앙-dt 그리드로 선형 보간 리샘플.
3. **idle 상태 "측정 완료" 문구**: UI E2E가 모드 진입 직후 잘못된 문구 발견
   → 4상태 문구로 수정(앱+웹).

## 무엇을 실행했나 (전부 이 세션에서 실측)
- swift test --filter VibratoAnalysisTests: 최초 6/9 → 결함 2건 수정 → 9/9
- 전체 swift test: 92/92 (기존 83 + 신규 9)
- verify_vibrato_parity.py: 최초 FAIL(스크립트 버그 3 + 경계값 1) → ALL PASS
- node tools/vibrato_ui_e2e.mjs: 12/13 → 문구 수정 → 16/16
- bash verify_all.sh: 7 게이트 ALL GREEN
- favicon 404: 브라우저 자동 요청 판별(앱 결함 아님)

## 생략한 것
- 실기기(iOS) 마이크로 녹음한 진짜 비브라토 샘플 검증 — Windows 환경 제약.
  합성 신호(정현 포먼트) + 무성 프레임 탈락 시뮬레이션으로 대체.
  CI 시뮬레이터 스모크는 앱 타깃 빌드·런치만 확인(오디오 입력 없음).
