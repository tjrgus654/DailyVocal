# 설계 노트 — 프리즈 토큰 소모를 조회 경로 밖으로 이동하기 (P2-4)

상태: **설계만 완료, 구현 보류** (Mac 실기 런타임 검증 후 착수 권장)
근거: VERIFICATION_LOG '수용된 잔여 위험' — `ProgressViewModel.update`가
읽기 경로에서 SwiftData 프로필을 변경·저장한다.

## 현재 동작과 문제

```
VocalProgressView.onAppear / onChange(of: sessions, profiles)
  └─ ProgressViewModel.update(...)
       └─ VocalLogic.calculateStreak → consumedDays
            └─ profile.streakFreezeTokens -= n; frozenDays += [...]; try? save()
```

- "성장 탭을 여는 것"이 저장을 유발 → `onChange(of: profiles)` 재유발 →
  다중 갭이 있을 때 토큰 회계가 렌더 1회에 수렴(단일 슬롯 결함은
  consumedDays 배열화로 이미 해결)하나, 읽기-쓰기 결합은 남아 있다.
- `try? save()` 실패가 무음이다.
- SwiftUI 갱신 사이클에 부수효과가 묶여 있어, 향후 뷰 계층 변화가
  예상치 못한 재소모를 만들 여지가 있다.

## 목표 설계

**불변식**: 스트릭 판정은 항상 순수 계산이고, 토큰 차감은 하루 1회·
명시적 시점에만 발생한다.

1. **판정(읽기) 순수화** — `update()`는 `calculateStreak` 결과를
   `frozenDaysInStreak`/`currentStreak` 표시에만 쓴다. 프로필 쓰기 금지.
   "오늘 브리지가 필요한 상태"는 `pendingBridgeDays: [String]` 계산값으로
   노출(저장 안 함).
2. **소모 시점 일원화** — 두 후보 중 택1:
   - **A(권장): 세션 완료 시** — `DailyRoutineViewModel.persistSession`과
     `PitchTrackerViewModel.persistSessionSummary`에서 오늘 날짜가
     스트릭 마지막 날이 아니면 `settleFreezeTokens(for: today)` 호출.
     "연습을 했을 때만 보호권이 소모된다"는 Duolingo 관례와 일치.
   - B: 앱 포그라운드 복귀 시 1회 — `scenePhase.active`에서 마지막
     정착 날짜(UserDefaults `lastFreezeSettlementDay`)와 다르면 실행.
     연습 없는 날에도 소모된다는 점에서 덜 직관적.
3. **정찰 함수** — `ProfileService.settleFreezeTokens(profile:, on: Date)`
   새 파일로: 오늘 이전의 미실천 갭 중 토큰으로 브리지 가능한 것만
   차감·`frozenDayKeys` 기록·`save()` (do/catch + 오류 로그).
   멱등: 이미 `frozenDayKeys`에 있으면 재차감 없음.
4. **롤백 안전망** — 정산 전 상태를 `frozenDayKeys`에서 복원 가능하게
   설계하지 않는다(과설계). 대신 정산 직후 즉시 저장.

## 검증 계획 (구현 시)

- VocalLogic에 `settlePlan(practiceDays:frozenDays:tokens:today:)` 순수 함수
  추가 → consumedDays와 동일 규칙임을 계약 테스트로 고정.
- 기존 StreakSystemTests의 소모 시나리오가 그대로 통과해야 함(회계 규칙
  불변). 새로 "성장 탭 100회 열어도 토큰 불변" 테스트 추가.
- 웹 프로토타입 미러 동일 규칙으로 갱신 후 verify_echo_parity.py 스타일
  파리티 게이트 추가.

## 왜 지금 구현하지 않는가

- 현재 구현은 수렴형으로 동작하며 데이터 손실 경로가 없다(결함이 아니라
  구조 부채). 뷰모델 저장 시점을 바꾸는 작업은 SwiftData 마이그레이션과
  Live Activity 갱신 타이밍에 닿아, 런타임 검증 수단이 있는 Mac 실기
  환경에서 수행하는 것이 리스크/이득 비율상 맞다.
