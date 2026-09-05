# 하루보컬 (DailyVocal)

초보자를 위한 iOS 보컬 트레이닝 앱. 하루 15분(또는 2분 퀵) 루틴, 실시간 YIN 피치
감지, 근거기반 훈련 콘텐츠로 혼자서도 안전하게 발성을 연습합니다.

- **대상 기기**: iPhone, iOS 17.0+ (Dynamic Island 기기 권장)
- **스택**: SwiftUI · SwiftData · AVAudioEngine(단일 엔진: YIN/vDSP + 가이드 신디) · ActivityKit · @Observable
- **Mac 빌드 방법**: [docs/MAC_BUILD_GUIDE.md](docs/MAC_BUILD_GUIDE.md) — 이 문서 하나면 됩니다.

## 기능 요약

| 영역 | 내용 |
|---|---|
| 일일 루틴 | 4주 로드맵(힘빼기→가성→파사지오→실전) 15분 · 2분 퀵 · 목 상태 "아픔" 선택 시 쉬는 날 루틴 자동 강제 |
| 피치 트래커 | 실시간 YIN 감지(±12/35¢ 색 코드) · 선청각 모드 · **훈련 모드 9종**: 단음 유지(MPT 자동 측정) · 에코 3음 · 말하기 10초 · 모음 게임(포먼트) · 비브라토 체크(속도·진폭·규칙성 자기상관) · 셈여림 아치(메사 디 보체 RMS) · 스케일 따라부르기(자체 합성 반주) · 음정 게임 · 귀훈련 · A4 켈리브레이션(435~445Hz) |
| 성장 기록 | 스트릭(4AM 롤오버·프리즈 자동 소모) · 주간 목표 5/7 · 음역대 확장 · 정확도 추이 · **테크닉 스냅샷**(비브라토 Hz·셈여림 dB·최장 지속) · **오늘의 추천 훈련**(6종 취약점+다양성, 측정값 근거 문구, 탭하면 해당 모드로 딥링크) |
| 발성 연구소 | 오보컬 쇼츠 48 + 연구 기반 팁 9 = 57종, 즐겨찾기·검색·카테고리 |

## 저장소 구조

```
DailyVocalApp.swift   # @main 진입점
Core/                   # 오디오 엔진·YIN·시퀀서·로직(Logic은 순수 Swift, Windows 테스트 가능)
Design/                 # 디자인 토큰·글래스 카드
Models/                 # SwiftData 모델 + 루틴 프리셋 + 팁 모델
ViewModels/             # @Observable 뷰모델 4종
Views/                  # SwiftUI 화면(루틴/트래커/연구소/기록/온보딩 5단계)
Widget/                 # 위젯 익스텐션
Resources/              # vocal_tips.json (57종)
Tests/                  # swift test 유닛 테스트 (Windows/macOS 공용, 순수 로직)
preview/                # 실동작 웹 프로토타입(마이크 YIN·영속화) — 설계 미러
docs/                   # Mac 빌드 가이드 · 보컬 핸드북 · 역사 문서
evidence/               # 라운드별 검증 증거(ROUND1~12) · 검증 로그
.github/workflows/      # macOS CI 타입체크(push마다 자동)
```

## 검증 상태

- **로컬 원샷**: `bash verify_all.sh` — 9게이트(파스 48파일 · swift test 115 ·
  정적 교차검증 · 에코/스케일 파리티 13축 · 스트릭/추천 파리티 · JS 구문 ·
  비브라토 파리티 15실행축 · 다이내믹스 16실행축 · 최장지속 9실행축).
- **CI(실제 macOS)**: 앱+위젯 swiftc -typecheck + `swift test`(**120 테스트** =
  순수 115 + macOS 오디오 파이프라인 실측 6: 합성 음성 버퍼→프레임→YIN→RMS→
  Goertzel 종단) — push마다 자동 실행.
- **시뮬레이터 스모크 CI**: 빌드→설치→런치→크래시 검증 + 온보딩 5페이지
  스크린샷 캡처(런치 인자 딥링크)·빈 화면·해시 상이성 검증.
- **실행 파리티 3종**: JS 이중 구현을 Swift 테스트와 동일한 합성 벡터로 실행해
  교차 검증(비브라토·다이내믹스·최장지속 40실행축).
- **웹 프로토타입 E2E 48축**: 브라우저에서 전 플로우 실측(가짜 마이크 오디오 E2E,
  추천 딥링크, 측정값 근거 문구 포함).
- 상세: [evidence/VERIFICATION_LOG.md](evidence/VERIFICATION_LOG.md) · 검증 265+항

## 로컬 검증 명령

```bash
bash verify_all.sh   # 원샷: 아래 6게이트를 한 번에 (Windows 개발 머신 기준)
```

개별 실행:

```bash
bash verify_swift_parse.sh                            # 1. 전 소스 구문 검사
bash run_swift_tests.sh                               # 2. 순수 로직 유닛테스트(실실행)
python evidence/20260903-rebuild/verify_static.py     # 3. 정적 교차검증(데이터 정합)
python evidence/20260903-rebuild/verify_echo_parity.py    # 4. 에코 파리티(웹↔Swift)
python evidence/20260903-rebuild/verify_streak_parity.py  # 5. 스트릭 파리티(웹↔Swift)
node -e "..."                                        # 6. live.html JS 구문 (verify_all.sh 참조)
```

## 주의

- `.zcode/skills/`는 이 저장소에서 쓰는 에이전트 스크립트 모음입니다(빌드와 무관).
- 루트의 `Package.swift`는 **Windows 테스트 전용**이며 Xcode 프로젝트와 무관합니다.
  앱 타깃 구성은 `docs/MAC_BUILD_GUIDE.md`를 따르세요.
