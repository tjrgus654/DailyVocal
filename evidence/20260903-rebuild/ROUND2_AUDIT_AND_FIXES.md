# Evidence — 라운드 2: 병렬 에이전트 감사·리서치 + 프론트 HD 재검증 + 전수 수정 (2026-09-03)

## 실행한 병렬 작업 (3 에이전트 + 메인 스레드)

1. **코드 전수 재감사 에이전트** — 32파일 5,257줄 전부 판독, P0 1건/P1 9건/P2 9건 보고 (아래 표).
2. **Apple 플랫폼 리서치 에이전트** — 공식 문서 기반 출시 체크리스트 (프라이버시 매니페스트 필수 등).
3. **경쟁 앱 제품 리서치 에이전트** — 2025-26 보컬 앱 표준기능/리텐션 패턴/한국 시장 (출처 URL 포함).
4. **메인: 프론트 HD 재검증** — 1.6배 확대 렌더링으로 7+3개 상태 재촬영, 비전 리뷰 재판정.

## 감사 결과 → 수정 매핑 (F1~F19)

| ID | 등급 | 내용 | 처리 |
|---|---|---|---|
| F1 | **P0** | 탭 클로저의 self 없는 `detector` 프로퍼티 접근 = 빌드 브레이커 | ✅ 지역 상수 캡처로 수정 |
| F2 | P1 | @State VM 재생성이 엔진 단일 콜백을 훔침 → 트래커 2회차 방문부터 사망 | ✅ 콜백 등록/해제를 startTracking/stopTracking으로 이동 |
| F3 | P1 | 탭 전환만으로 진행 중 루틴 세션 초기화 | ✅ 진행 중이면 refresh 스킵 |
| F4 | P1 | ScaleSequencer 재시작 레이스(구 태스크 finish가 isPlaying 뒤집음) | ✅ 세대(generation) 토큰 + Task 본문에서 isPlaying=true |
| F5 | P1 | 세션 길이가 히스토리 잘림으로 최대 ~5초로 오측정 | ✅ sessionStartDate 기준 계산 |
| F6 | P1 | 스트릭 보호권이 소비되지 않음(데드 데이터) | ✅ 하루 결석 시 자동 소모 + frozenDayKeys 기록(4am 롤오버 포함) |
| F7 | P1 | 마이크 권한 거부 시 무한 "감지 중" | ✅ 거부 전용 카드+설정 이동(트래커·온보딩 측정 페이지) |
| F8 | P1 | 일시정지 중 Live Activity 타이머 역방향 증가 | ✅ pausedRemainingText 정적 렌더 |
| F9 | P1 | 타이머 드리프트/백그라운드 서스펜션 미반영 | ✅ stepEndDate 벽시계 기반 tick 재계산 |
| F10 | P2 | 23Hz 상태를 큰 body에서 읽어 전체 리렌더 | ✅ PitchCanvasSection 잎사귀 뷰로 격리 |
| F11 | P2 | 오디오 경로 프레임당 힙 할당 | ⏸ 의도적 보류(23Hz에서 치명치 않음, 무컴파일 환경에서 리스크>이득) |
| F12 | P2 | 탭 전환마다 48팁 JSON 재디코드 | ✅ loadTips 가드 |
| F13 | P2 | HeatmapDay UUID 재발급 → 84셀 전체 재생성 | ✅ id=dayKey |
| F14 | P2 | 키 선호 AppStorage/프로필 이중 출처 불일치 | ✅ 피커 onChange에서 프로필 동기화 |
| F15 | P2 | PitchRecord 쓰기 전용 | ✅ 성장 기록 "최근 피치 측정" 카드로 표시 |
| F16 | P2 | 스텝 종료 off-by-one(+1s/스텝) | ✅ 새 tick 로직에서 0 도달 tick에 즉시 advance |
| F17 | P2 | 프로필 생성 try? 삼킴 → 중복 insert 가능 | ✅ 실패 시 로그+스킵 |
| F18 | P2 | Swift 6 언어 모드 빌드 리스크(deinit 등) | 📄 README에 SWIFT_VERSION=5 지침으로 문서화 |
| F19 | P2 | 강제 종료 시 Live Activity 잔존 | 📄 플랫폼 제약 — README 알림사항으로 문서화 |

## 리서치 기반 신규 기능 (이번 라운드 추가)

- **PrivacyInfo.xcprivacy** — UserDefaults=required-reason API로 매니페스트 없으면 App Store 거부
  (NSPrivacyTracking=false, 수집데이터 없음, UserDefaults CA92.1). Apple 공식 문서 근거.
- **스트릭 보호권 자동 소모 + 오전 4시 날짜 롤오버** — Duolingo 패턴(스트릭 단절=이탈), 한국 심야 연습 문화.
- **노래방식 세션 점수(0-100, S~D등급) + 완료 알림** — 한국 점수 문화(TJ 퍼펙트스코어).
- **YIN 옥타브 점프 거부 가드 + 캔버스 C3/C4/C5 기준선** — pYIN/Smart-Median 문헌의 저비용 대응.
- **가이드 톤 반음 미세조정(-5~+5) 스테퍼 + 4주 후 유지 모드 배지** — TJ노래방 키조절 멘탈모델, 콘텐츠 절벽 완화.
- **"분석 중" 마이크 표시(루틴 헤더)** — App Review 2.5.14 요구사항.
- **setPreferredIOBufferDuration + 가이드 톤 볼륨 보정** — .measurement 모드 부작용 대응(Apple 문서).

## 프론트 HD 재검증 (라운드 2)

- 1.6배 확대 렌더링 → 신규 상태 3종(펼친 실천 가이드/카테고리 필터링/권한 거부) + 핵심 2화면 HD 재촬영.
- 판정: 이전 저해상도 오판("라벨 만곡" 등) 정정됨. 타이머 중심정렬·도트 3상태·캔버스 명확성·행갈이 hanging indent·칩 선택성·권한카드 유도 모두 "우수/정상".
- 남은 지적은 프리뷰 프레임 아티팩트(스크롤 잘림 등)로 실앱 무관.

## 최종 검증

- `verify_static.py` 재실행: **ALL CHECKS PASSED** (유령 심볼 0, 괄호 균형 33파일, 멤버 참조 정합, JSON 48개, Info.plist arm64/audio, @main 배치).
- PrivacyInfo.xcprivacy XML 유효성 확인.
- 잔여 위험 참조 grep(self.detector/statsPanel/구 finish()) 0건.
- 규모: Swift 33파일 5,674줄.

## 한계 (변경 없음)

Windows 무컴파일 환경 — 최종 판정은 Mac Xcode 빌드에 의존. F11(오디오 버퍼 풀)은 기기 검증 후 적용 권장.
