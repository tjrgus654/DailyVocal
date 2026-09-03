# ROUND 9 — 개선 3종: 세션 음 분포 히스토그램 · 쉬는 날 모드 · 정확도 추이

날짜: 2026-09-03 · ROUND8 로드맵 및 근거 기반 지속 개선

## 1. 세션 결과 12음 히스토그램

근거: Vocal Pitch Monitor의 "귀를 비추는 거울" 패턴 — 사용자 극찬 1위 기능.
세션 종료 후 피치 클래스(C...B, 옥타브 접힘) 분포 바를 카드로 표시한다.

- Swift: `PitchTrackerViewModel.noteBinCounts`(voiced 프레임당 midi%12 증가,
  startTracking서 초기화) + `NoteHistogramCard`(세션 결과 있을 때만 표시,
  max 정규화 바 높이). PitchRecord 스키마 변경 없음(표시 전용).
- JS 미러: `App.bins` + 결과 카드(`#hist`), 세션 시작 시 초기화.

E2E 실측: E4 10프레임 + A4 5프레임 → bins[4]=10, bins[9]=5, 합=15=voiced,
카드 표시 ✓, 새 세션 시작 시 초기화+카드 소멸 ✓.

## 2. 목 상태 체크 + 쉬는 날 루틴 (성대 보호 가드)

근거: Iowa voice-rest 프로토콜(상대적 휴성, 속삭임 금지) + ROUND6 체크리스트
"중단 신호 감시". 아픈 날 일반 워크로드를 절대 실행하지 않게 강제한다.

- `RoutinePresets.restRoutine()`: 2분, 아주 작은 빨대 발성→저음 허밍→조용한
  한숨. 속삭임 금지 안내 포함. 딱지 비유로 근거 전달.
- Swift VM: `RoutineMode.rest`(피커 비노출, 내부 전환 전용), `VocalCondition`
  (good/tired/sore, UserDefaults "vocalCondition" 영속), sore 선택·재실행·
  재진입 모두 rest로 강제(refreshFromProfile에서 cond 회복 시 full 복귀),
  `restNotice` 1회 알림, 완료 알림·세션 노트("쉬는 날")·배지 분기.
- View: "오늘 목 상태" 칩 3개(아픔 선택 시 적색), sore 알림 alert.
- JS 미러: STEPS_REST + cond 칩 + setCondition/startRoutine 이중 가드 +
  헤더/완료 토스트 분기.

E2E 실측: cond=2 → mode "rest" + STEPS_REST 로드 ✓, cond 복원 → "full" 복귀 ✓,
아픈 상태에서 풀코스 수동 선택 후 start → 여전히 rest로 강제 ✓, 완료 세션
mode:"rest"/full:true 저장 ✓, 헤더 "쉬는 날 루틴" ✓.

## 3. 정확도 추이 미니 차트 (성장 기록)

- Swift: `AccuracyTrendCard` — 최근 14회 PitchRecord 온피치율 바(70%↑ 초록),
  최근 3회 vs 이전 3회 평균 델타 캡션. 기존 @Query 재사용, 신규 쿼리 없음.
- JS 미러: progress 화면 동일 카드(기록 2건 이상 시).

E2E 실측: 기록 5건 → 카드 렌더, 바 5개(=min(14, 기록수)) ✓.

## 4. 부수 카피 교정

"나의 보컬 여정"(번역투 여정 패턴, korean-ux-copy 체크리스트 5번) →
"4주 성장 기록" — Swift·JS 양쪽.

## 5. 검증 (실행 결과)

- `verify_swift_parse.sh` → **통과 32 / 실패 0**
- `verify_static.py` → **ALL CHECKS PASSED**
- `preview/live.html` JS → vm.Script 구문 통과
- E2E 3종 전 항목 통과 (위 각 절)

## 6. 남은 로드맵

A4 주파수 캘리브레이션, 성공 기반 적응 난이도(91.5% 음역 내 배치),
신규 3기능의 Mac 실기 검증(파스·프로토타입 E2E로는 검증 완료).
