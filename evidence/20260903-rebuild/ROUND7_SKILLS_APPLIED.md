# ROUND 7 — 스킬 리서치·설치·적용 (AI티 청산 + 리뷰 수정)

날짜: 2026-09-03

## 1. 스킬 리서치 결과 (GitHub 순위 기준)

| 소스 | 규모 | 채택 |
|---|---|---|
| [travisvn/awesome-claude-skills](https://github.com/travisvn/awesome-claude-skills) | 14.9k★ (최대 전용 리스트) | 탐색 인덱스로 사용 |
| [anthropics/skills](https://github.com/anthropics/skills) (공식) | — | **frontend-design 채택** ("AI slop/제네릭 미학 회피" 명시) |
| [obra/superpowers](https://github.com/obra/superpowers) | 최상위 인기 스킬 모음 | **verification-before-completion, requesting-code-review 채택** |
| [conorluddy/ios-simulator-skill](https://github.com/conorluddy/ios-simulator-skill) | iOS 에이전트 자동화 | **채택** (Mac 확보 시 실기 검증 경로) |
| 카피 AI티 전용 | 어느 컬렉션에도 없음 | **korean-ux-copy 직접 제작** (한국어 UI 카피 AI티 체크리스트 10항) |

## 2. 설치 (워크스페이스 `.zcode/skills/`, 5종)

frontend-design · verification-before-completion · requesting-code-review ·
ios-simulator-skill · korean-ux-copy(자체 제작, SKILL.md 포함)

## 3. 적용 1차: korean-ux-copy 체크리스트 전수 스캔 → 12건 수정

- 알림 제목 이모지(🎉🎙)·장식 이모지(💡🏆) 제거, "gliding 해보세요" 영어혼용 제거,
  빈 상태 em-dash→원인+행동 문장, "따라해보세요/함께 보면 좋은 비법"→기능 명칭,
  RoutineStep em-dash 3곳 분리, preview HTML 장식 이모지 3종 제거.

## 4. 적용 2차: requesting-code-review 스킬로 리뷰 서브에이전트 디스패치

리뷰 결과 P1 6건 / P2 15건 → 전수 수정:

**P1 (6)**
1. 센트 범례 🔴 ↔ 실제 채색 불일치 → noteColor >35¢를 `.vocalAlert`(적색)로 수정
2. 연구 팁(49-52)에 "쇼츠 #N" 오표시 → viewCount 분기 배지 + 헤더 "오보컬 쇼츠 · 연구 기반 비법"
3. 퀵 모드 완료 메시지가 15분 전제 → 모드별 분기 + 레지스터 통일(해요체)
4. 조사 오류 "스트릭를" → "연속 기록이 끊기기 전에 밤 10:30에 알려드려요"
5. 성대 해부학 오기("근육이 아니다") → "표면은 얇은 점막으로 덮여…"로 교정
6. "소리 내지 않는 허밍" 자기모순 → "아주 가벼운 빨대 발성과 짧은 허밍만"

**P2 주요 (15 중 전부 반영)**
- sessionsCompletedToday가 퀵/스킵 세션까지 가산 → `isFullCompletion || duration>=300` 필터
- 스킵 관통 0초 세션이 스트릭에 기록되는 기존 결함 → `elapsed>=60 && !steps.isEmpty` 저장 가드
- 퀵 완료 메시지 분기, em-dash 잔존 4곳, "OK"→"괜찮습니다", 합니다체/하세요체 혼용 4곳,
  팁 51 제목, "한계가 있습니다"→"부족합니다", 붙여쓰기 통일, 파사지오 테너 기준 주석,
  파솔→파사지오 용어 통일, "1곡 만에 목이 나감" 과장 완화 2곳, '으-'→'웅-'(비음),
  팁 48 결과 보장형 완화, 팁 28 차가운 음료 과학적 완화, 연구 팁 섹션 제목 "핵심 원리" 분기.

## 5. 검증 (실행 결과 — verification-before-completion 스킬 적용)

- `verify_swift_parse.sh` → **통과 32 / 실패 0**
- `verify_static.py` → **ALL CHECKS PASSED** (52 tips 정합)
- 잔존 스캔: Swift Text 문자열 내 장식 이모지 0건, JSON 내 em-dash 0건

## 6. 비고

- 리뷰 지적 중 🧊/🛡️(프리즈 토큰), 🟢🟡🔴(색 범례)는 기능형 아이콘으로 유지 (korean-ux-copy 규칙 1의 예외 조항).
- verify_static.py는 팁 개수를 하드 어서트하지 않음(출력만) — 요구사항 확정 시 assert 추가 여지.
