# ROUND 8 — 기능 업그레이드(에코 3음) + 코드/프론트 최적화 + 엔드투엔드 테스트

날짜: 2026-09-03 · 조사 결과(ROUND5/6 로드맵)를 토대로 구현·검증

## 1. 기능 업그레이드: 에코 3음 모드

근거: Pfordresher & Greenspon 2024 — 넓은 음역 에코(모방) 훈련이 단음 매칭을
유의하게 향상시킨 유일한 실험 입증 드릴. ROUND6 로드맵 1순위 항목.

동작: 시작음(목표음 선택)에서 ±2~5반음 이동 2회로 3음 시퀀스 생성(43..72 MIDI
클램프, A-B-A 아치형 허용) → 시퀀스 2회 재생(청취) → 음당 2.6초 노래 창 3개 →
활성 창의 목표음 기준 채점 → 마지막 창 종료 시 자동 세션 종료·기록 저장
(target = "E4-D4-E4" 형식). 가이드 재생 중 스피커→마이크 누설 프레임 차단.

| 계층 | 파일 | 구현 |
|---|---|---|
| Swift VM | `ViewModels/PitchTrackerViewModel.swift` | TrackerMode(single/echo), echoTargetMidis/activeEchoIndex, generation 토큰 레이스 가드, activeTargetMidi 통합 채점, 세대별 자동 종료 |
| Swift 캔버스 | `Views/PitchTracker/PitchLineCanvas.swift` | 에코 3목표선(비활성 22% 점선, 활성 강조) |
| Swift 뷰 | `Views/PitchTracker/PitchTrackerView.swift` | 모드 세그먼트 피커, 활성 목표 기준 라이브 노트·피아노 스트립·주파수 |
| 프로토타입 | `preview/live.html` | 동일 스펙 미러(ECHO_T 타이밍 상수 — 테스트 가변), 테스트 훅 |

## 2. 코드/프론트 최적화 + 버그 수정

1. **연구소 카테고리 필터 전면 불능(실버그)** — CAT_LIST id가 JSON 키와 불일치
   (`direction` vs `sound_direction` 등 5/6개 불일치) → JSON 키로 수정.
   수정 후 브라우저 실측: breathing 6 · falsetto_switch 11 · jaw_larynx 12 ·
   nasal_resonance 6 · practical_tips 12 · sound_direction 5 (합 52, JSON 분포 일치).
2. **프레임당 DOM 낭비 제거** — updateTrackerDom이 매 피치 프레임마다
   innerHTML 재구성 + querySelectorAll(".pkey") 전체 스캔 → 노트/색 변경시에만
   재구성, 숫자는 textContent만 갱신. 초과 35¢ 색을 Swift(.vocalAlert)와 정렬.
3. Swift 히스토리 상한(120)·캔버스 용량 결정론은 기존 구현 확인 후 유지(병목 없음).
4. 프로토타입 온보딩 카피 동기화("gliding 해보세요" → Swift 수정본).

## 3. 엔드투엔드 테스트 (실브라우저, 로컬 http 서버 + 실제 코드 경로)

피치 프레임은 마이크 대신 `__test.feed()`가 **마이크 콜백과 동일한 함수**
(trackerPitchHandler)를 호출 — YIN 정확도는 엔진 자가진단이 별도 커버.

### 에코 3음 E2E — 전 항목 통과
- 시퀀스 스펙: 시작음=선택 목표음(E4=64) ✓, 이동 2..5반음 ✓, 43..72 클램프 ✓
- 가이드 재생 중 채점 차단: 프레임 공급에 voiced=0 유지 ✓ (ignoreUntil=Infinity)
- 창 전환: idx 0→1→2 ✓
- 채점 정확도: 창0에 오답 4+정답 8, 창1·2에 정답 8 → voiced 28, hits 24, **정확도 86% = 기대치 정확히 일치** ✓
- 자동 종료(listening=false) ✓, 기록 저장(target="E4-D4-E4", acc=86) ✓
- 세대 가드: 재시작 시 구 태스크 무시(구현+코드 검토) ✓

### 회귀 — 통과
- YIN 엔진 자가진단: 6주파수 전통과, 최대 오차 **0.135¢**, 무성 노이즈 기각 ✓
- 단음 모드: 정답 12프레임 → 100% ✓ (기존 동작 보존)
- 온보딩 완료 플로우 → 탭 전환 → 각 화면 렌더 ✓
- 검색("가성") 6건 ✓, 성장 기록: 스트릭·최근 피치 카드·주간 목표 표시 ✓
  (스트릭 0일은 신규 오리진 localStorage에 루틴 세션 없음 — 올바른 동작)
- 영속성: pitchRecords 2건(에코+단음) Store 저장 확인 ✓

### 스크린샷
IAB 스크린샷 파이프라인이 타임아웃(3회 재시도, 탭 재개 포함) — 기능 검증은
전부 DOM 어서션으로 완료했으므로 아티팩트만 생략. 이후 재개 가능.

## 4. 최종 검증 (실행 결과)

- `verify_swift_parse.sh` → **통과 32 / 실패 0**
- `verify_static.py` → **ALL CHECKS PASSED** (52 tips)
- `preview/live.html` JS → vm.Script 구문 검증 통과

## 5. 남은 로드맵

12음 히스토그램+A4 캘리브레이션, 성공 기반 적응 난이도(91.5% 음역 내 배치),
목 아픔 신호 감지 강제 종료, Swift 에코 모드 실기(Mac) 검증.
