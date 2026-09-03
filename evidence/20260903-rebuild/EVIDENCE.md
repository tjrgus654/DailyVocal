# Evidence — 20260903 5VocalMaster 전면 재구현 검증

## 무엇을 테스트했나

이 머신(Windows)에는 Swift/Xcode 툴체인이 없어 **컴파일/실행 검증이 불가**하다.
대신 가능한 정적 검증을 스크립트로 수행했다: `verify_static.py`
(실행 결과 원본: `verify_output.txt`, 결과: **ALL CHECKS PASSED**).

## 검증 항목과 관측 결과

| # | 검증 | 방법 | 관측 |
|---|---|---|---|
| A | 구버전 유령 심볼 잔존 | 18개 심볼 전 파일 grep | 전부 부재 (PASS) |
| B | 괄호 균형 | 문자열·주석 제거 후 `{}`/`()` 카운트 (32개 파일) | 0건 불일치 |
| C | `@main` 배치 | 주석 제거 후 카운트 | 앱 1개 + 위젯 1개만 |
| D | 인스턴스→멤버 교차 참조 | 타입 본문 파싱으로 멤버 추출, 9개 클래스 × 소비 파일 | 92개 참조 전부 정의 존재 |
| E | 커스텀 타입 정의 | 44개 타입 정의 존재 확인 | 전부 정의됨 |
| F | 핵심 API 시그니처 | vDSP 3종 호출, iOS17 권한 API, 톤 스케줄, 위젯 타이머 인터벌 문자열 매칭 | 전부 일치 |
| G | vocal_tips.json 정합성 | 필드셋·카테고리 raw값·relatedShorts 유효성·중복·분포 | 48개 전부 유효, 콘텐츠 중복 0, 같은-카테고리 연관 120/144 |

카테고리 재분배 후 분포: breathing 5 / falsetto_switch 11 / sound_direction 5 /
jaw_larynx 12 / nasal_resonance 6 / practical_tips 9 (기존 practical_tips 19 → 9).

## 도중 발견·수정한 자체 오류 (검증 과정에서)

1. `AVAudioSession.isAudioSessionActive()` — 존재하지 않는 API를 썼음 → 제거 (setCategory/setActive 직접 호출).
2. 노트 이름 파서 초안 논리 결함 → 문자/임시표/옥타브 상태머신으로 재작성.
3. `VocalTip.swift` 괄호 불일치 보고 → 검사기 결함(문자열 내 `https://`의 `//`를 주석으로 오판). 검사기 순서 수정(문자열 먼저 제거) 후 실제 코드는 균형 확인.
4. nonisolated 탭 핸들러가 MainActor 상태(detector, pending 카운트)에 접근 → detector를 탭 클로저로 캡처 + `FrameGate(@unchecked Sendable)`로 치환.
5. TipDetailView가 새 뷰모델을 만들어 JSON 재로딩 → 상위에서 relatedTips 배열 전달로 변경.

## 무엇을 생략했나 (한계)

- **Xcode 빌드/런타임 검증 불가** — Mac에서 `Cmd+R` 빌드와 실기기 테스트(마이크 피치 정확도,
  다이내믹 아일랜드 표시, SwiftData 저장)는 사용자 환경에서 수행해야 한다.
  이는 본 재구성품의 가장 큰 미검증 영역이다. README_XCODE.md §5 체크리스트 참고.
- SwiftUI 뷰의 시각적 레이아웃(간격·색 대비 등)은 코드 리뷰 기준으로만 정합 — 렌더링 확인 안 됨.
- Swift 6 언어 모드(strict concurrency) 완전 준수는 목표로 하지 않음(기본 Swift 5 모드 기준,
  다만 격리 위반 소지가 있던 지점들은 제거 완료).

## 왜 충분한가 / 아닌가

충분: 이전 구현의 빌드 파괴 원인(유령 파일·존재하지 않는 API 참조)을 시스템적으로 원천 확인했고,
모든 프로젝트 내 심볼 참조가 정의로 해석됨을 기계적으로 확인했다.
불충분: 실제 컴파일러·런타임 통과 여부. 최종 판정은 Mac 빌드 결과에 의존한다.
