# ROUND 12 — Mac 인계 전 완벽화 패스 (구조·실행검증·다이어트·비전 QA)

날짜: 2026-09-04 · 사용자 지시: "맥에서 오류 하나도 못 찾게, 검증 20회 이상, 멀티모달 에이전트·MCP 활용"

## 1. 구조·문서 다이어트 (A단계)

- `docs/` 신설: MAC_BUILD_GUIDE.md(구 README_XCODE) · VOCAL_MASTER_GUIDE.md ·
  history/(CLAUDE 계획서·리빌드 보고) — 루트에는 README.md만.
- `README.md` 신규: 기능 요약·구조·검증 상태·로컬 검증 명령.
- `ios_simulator.html` 폐기(문서화된 폐기 대상).
- 참조 스캔 후 이동(깨진 링크 0).

## 2. 순수 로직 추출 + Windows 실실행 검증 (B단계 — 핵심)

"Windows에서 Swift 실행이 안 된다"를 되게 한 방법:
1. Foundation 전용 `Core/Logic/VocalLogic.swift`로 노트 산수(A4 켈리브레이션)·
   스트릭/프리즈/4AM 롤오버·히트맵·에코 시퀀스 설계·세션 등급을 추출
   (앱과 테스트가 **동일 소스**를 컴파일 — 드리프트 불가능 구조).
2. YINPitchDetector를 `#if canImport(Accelerate)` vDSP/스칼라 이중 구현으로
   Windows에서도 실행 가능하게 이동(수학 동일).
3. 루트 `Package.swift` + `Tests/VocalLogicTests`(유닛테스트 20개).
4. **매니페스트 컴파일 실패(SDKROOT 누락)를 툴체인 수색으로 해결**:
   Platforms/6.3.3/Windows.platform SDK 발견 → `run_swift_tests.sh`에 SDKROOT 세팅.

실측 결과가 낸 진짜 결함(실행 없이는 불가능했던 것들):
- swift test 런1: YIN 저음 정확도 임계 초과 → **테스트 신호의 인벨로프가 원인**
  (정지 신호로 교체, 앱 무결) + **롤오버 테스트 기대값 버그**(앱 로직 무결,
  자정-4h는 어제 키가 정답) — 실패 3건 중 2건이 테스트 수정, 1건(신호)도 액션이었지만
  근거 명확. 수정 후 20/20 그린.
- CI 3라운드 추가 결함: Package.swift 편입(제외 규칙), practiceDayKey 위임 누락.

## 3. 코드 다이어트 (C단계 — 보수적)

- 로직 추출로 ProgressViewModel 237→103줄, PitchTrackerViewModel/엔진에서
  이동 로직 제거. 단일 사용 `now()` 래퍼 인라인. 미사용 UIKit import 없음 확인.
- "다이어트가 문제되면 안 한다" 원칙: 런타임 미검증 영역(뷰 구조)은 손대지 않음.

## 4. 멀티모달 비전 QA (D단계 — GLM 비전 에이전트)

- IAB 스크린샷 불안정 → **해결책 2단**: ①새 탭 캡처(5화면 성공) ②이후 불안 시
  **URL 해시 시드 하네스(#qa=base64) + Edge 헤드리스** 로 재현 가능 캡처 체계 구축
  (비주얼 회귀 테스트 재사용 가능).
- 스크린샷 → git push → raw URL → **비전 에이전트(analyze_image) 2라운드**:
  라운드1(5화면) 실개선 3종 도출·적용: A4 스테퍼 44pt 터치타깃(Swift+JS),
  카테고리 칩 스크롤 페이드 힌트, 자리표시자 대시 통일.
  라운드2(활성 3화면): P1 후보 2건 모두 오판 판명(시드 날짜 창 밖·옥타브 앵커 설계).
- 오탐 판별 기록 VERIFICATION_LOG.md에 영속.

## 5. 최종 상태

- 로컬: 파스 38/38 · swift test 20/20 · 정적 ALL PASS(신구조 반영) · JS 구문 OK
- CI: 그린(앱+위젯 typecheck, 신규 구조에서 3라운드 만에 통과 후 유지)
- 저장소: 20 커밋, 검증 로그 24행, docs/ 정리 완료
- Mac 잔여: 빌드·런타임 구동·실기 오디오뿐 (docs/MAC_BUILD_GUIDE.md)
