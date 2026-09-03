# Evidence — 라운드 4: "실제 작동" 검증 인프라 구축 (2026-09-03)

## 요청 배경

"병렬 에이전트 활용 + 레퍼런스/기능 리서치 + Mac 없이도 최대한 완벽하게 + 실제 작동도 되어야 함"

## 1. Windows에 실제 Swift 컴파일러 설치 → 진짜 구문 검증

- winget으로 **Swift 6.3.3 공식 툴체인** 설치 (경로: `%LocalAppData%\Programs\Swift\Toolchains\6.3.3+Asserts`).
- 학습된 실행 노하우: `swiftc.exe` 드라이버는 이 셸에서 서브프로세스 스폰 실패 → **`swift-frontend.exe -parse` 직접 호출**,
  且 PATH에 `Toolchains/usr/bin` + `Runtimes/6.3.3/usr/bin`(swiftCore.dll 소재) 둘 다 필요.
- 음성 대조군: 고의 문법 오류 파일 → 정확히 `error: expected parameter name...` 진단 + exit 1 (검증기가 진짜 작동함을 증명).
- **결과: 32/32 파일 PARSE 통과.** 검증 중 실제 버그 1건 발견·수정:
  `VocalAudioEngine.swift:76` 함수 타입에 인자 레이블(`(frequency: Double, ...) -> Void`) —
  **Xcode 빌드를 깨았을 P0**. 정규식 검사로는 발견 불가능한 부류 → 컴파일러 검증의 가치 실증.
- 재사용 스크립트: `verify_swift_parse.sh` (수정 후 재검증 포함 전 통과).

## 2. 실동작 프로토타입 (preview/live.html) — 핵심 루프 실증

Swift 구현과 동일 스펙의 JS 포팅(YIN 알고리즘·중앙값3·옥타브 가드·4AM 롤오버·프리즈 소모)으로
브라우저에서 실제 도는 앱: 실마이크 분석, WebAudio 가이드 톤(삼각파+2배음+ADSR), 벽시계 루틴 타이머,
localStorage 영속화(세션/스트릭/즐겨찾기/측정 기록).

### 자가진단 (마이크 불필요, 순수 계산) — `window.runSelfTest()`

| 목표(Hz) | 측정(Hz) | 오차(센트) |
|---|---|---|
| 82.41 | 82.41004 | 0.0008 |
| 110 | 110.00016 | 0.0024 |
| 220 | 220.00199 | 0.016 |
| 329.63 | 329.63401 | 0.021 |
| 440 | 440.01829 | 0.072 |
| 659.25 | 659.30148 | 0.135 |

**전 대역 오차 < 0.14¢, 무음 기각 PASS, ALL PASS.** Swift `YINPitchDetector`와 동일 스펙의
알고리즘이 실제로 정확히 작동함을 증명.

### DOM 기능 플로우 실측 (Playwright)

- 온보딩 렌더→시작 ✅ / 48팁 JSON 로드 ✅ / 카테고리 그리드 ✅
- 스트릭 3일 ✅ / 주간 목표 3/5 ✅ / 음역대 +4반음 ✅ / 최근 측정 87점 표시 ✅
- 새로고침 후 영속성(세션·즐겨찾기) ✅
- **프리즈 자동 소모**: 어제 결석+3일 전까지 실천 → "3일 연속" + "보호권으로 이어진 날 1일" + 토큰 2→1 ✅
- 검증 중 프로토타입 JS의 **4AM 롤오버 이중 시프트 버그** 발견·수정 (Swift 쪽은 동일 로직이 처음부터 올바름 — 교차 검증의 효과)

## 3. 병렬 에이전트 3종 결과 요약

1. **디자인 레퍼런스** — 12개 구체 제안(±5/±12¢ 지각 임계값, numericText(countsDown:),
   flame.fill+glow+bounce, 링 글로우 스펙, snappy/smooth/bouncy 매핑, 탭바 thinMaterial 등).
   이 중 S-size 5건 즉시 앱에 적용.
2. **기능 2차** — TOP5: ①선청각 이어트레이닝(근거 최강: Berglin/Pfordresher 2022) ②홀드 게임
   ③공유 결과 카드(ImageRenderer+ShareLink, 카톡 커버) ④정확도 추이 차트 ⑤허밍 모드.
   anti: 목숨 시스템, 호흡 모듈. → ①을 이번에 구현, ②~⑤는 로드맵 문서화.
3. **Mac 없는 검증법** — 2단계 파이프라인 확정:
   1단계(완료): Windows swift-frontend -parse.
   2단계(제공): `.github/workflows/typecheck.yml` — 공개 저장소 macOS 러너 무료,
   `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios17.0-simulator`
   (앱/위젯 분리 typecheck, @main 충돌 방지). Apple 계정·Mac·xcodeproj 불필요.

## 4. 이번 라운드 앱 코드 변경

- P0 수정: 함수 타입 인자 레이블 제거 (컴파일러 발견)
- 신규: **선청각 모드**(🎧 토글 → 목표음 2회 → 시각 베일 → 종료 시 궤적 공개)
- 디자인 승리 5건: numericText(countsDown:) + .snappy, flame.fill 심볼(글로우+bounce+numericText),
  마지막 3초 펄스(시안+1.12스케일), 탭바 thinMaterial, ±12¢ 지각 임계 반영
- `.github/workflows/typecheck.yml` 추가

## 5. 최종 검증 상태

- `verify_swift_parse.sh`: **32/32 통과** (수정 후 재확인)
- `verify_static.py`: ALL CHECKS PASSED
- 프로토타입 DOM 실측: 전 항목 통과 (상기)
- 한계: 타입 검사는 여전히 macOS 필요 → typecheck.yml push로 해결 가능 (사용자 액션)

## 6. 다음 로드맵 (리서치 기반, 구현 순서)

1. GitHub 공개 저장소 push → Actions typecheck 녹색 확인 (사용자)
2. Mac 빌드 → 실기기 (사용자)
3. 홀드 게임(S-M) → 공유 카드(S-M) → 정확도 추이 차트(M) → 허밍 모드(S)
