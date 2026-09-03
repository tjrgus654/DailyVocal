# 5분 보컬 (5VocalMaster)

초보자를 위한 iOS 보컬 트레이닝 앱. 하루 15분(또는 2분 퀵) 루틴, 실시간 YIN 피치
감지, 근거기반 훈련 콘텐츠로 혼자서도 안전하게 발성을 연습합니다.

- **대상 기기**: iPhone, iOS 17.0+ (Dynamic Island 기기 권장)
- **스택**: SwiftUI · SwiftData · AVAudioEngine(단일 엔진: YIN/vDSP + 가이드 신디) · ActivityKit · @Observable
- **Mac 빌드 방법**: [docs/MAC_BUILD_GUIDE.md](docs/MAC_BUILD_GUIDE.md) — 이 문서 하나면 됩니다.

## 기능 요약

| 영역 | 내용 |
|---|---|
| 일일 루틴 | 4주 로드맵(힘빼기→가성→파사지오→실전) 15분 · 2분 퀵 · 목 상태 "아픔" 선택 시 쉬는 날 루틴 자동 강제 |
| 피치 트래커 | 실시간 YIN 감지(±12/35¢ 색 코드) · 선청각 모드 · **에코 3음**(적응 난이도 1~3단계) · A4 켈리브레이션(435~445Hz) · 세션 음 분포 히스토그램 |
| 성장 기록 | 스트릭(4AM 롤오버·프리즈 자동 소모) · 주간 목표 5/7 · 음역대 확장 · 정확도 추이 |
| 발성 연구소 | 오보컬 쇼츠 48 + 연구 기반 팁 4 = 52종, 즐겨찾기·검색·카테고리 |

## 저장소 구조

```
5VocalMasterApp.swift   # @main 진입점
Core/                   # 오디오 엔진·YIN·시퀀서·로직(Logic은 순수 Swift, Windows 테스트 가능)
Design/                 # 디자인 토큰·글래스 카드
Models/                 # SwiftData 모델 + 루틴 프리셋 + 팁 모델
ViewModels/             # @Observable 뷰모델 4종
Views/                  # SwiftUI 화면(루틴/트래커/연구소/기록/온보딩)
Widget/                 # 위젯 익스텐션
Resources/              # vocal_tips.json (52종)
Tests/                  # swift test 유닛 테스트 (Windows/macOS 공용, 순수 로직)
preview/                # 실동작 웹 프로토타입(마이크 YIN·영속화) — 설계 미러
docs/                   # Mac 빌드 가이드 · 보컬 핸드북 · 역사 문서
evidence/               # 라운드별 검증 증거(ROUND1~12) · 검증 로그
.github/workflows/      # macOS CI 타입체크(push마다 자동)
```

## 검증 상태

- **CI(실제 macOS swiftc -typecheck)**: 앱 32파일 + 위젯 — 초록. push마다 자동 실행.
- **Windows에서 실제 Swift 실행 테스트**: `swift test` — YIN 정확도(합성 주파수),
  스트릭/프리즈/4AM 롤오버, 에코 시퀀스 스펙, 노트 산수·A4 켈리브레이션을
  앱과 동일 소스로 검증. (YIN은 `#if canImport(Accelerate)`로 vDSP/스칼라 이중 구현)
- **웹 프로토타입 E2E**: 브라우저에서 전 플로우 실측(자가진단 0.135¢ 포함).
- 상세: [evidence/20260903-rebuild/](evidence/20260903-rebuild/) · [evidence/VERIFICATION_LOG.md](evidence/VERIFICATION_LOG.md)

## 로컬 검증 명령

```bash
bash verify_swift_parse.sh                          # Windows: 전 소스 구문 검사
python evidence/20260903-rebuild/verify_static.py   # 정적 교차검증(데이터 정합)
swift test                                          # Windows/macOS: 순수 로직 유닛테스트
```

## 주의

- `.zcode/skills/`는 이 저장소에서 쓰는 에이전트 스크립트 모음입니다(빌드와 무관).
- 루트의 `Package.swift`는 **Windows 테스트 전용**이며 Xcode 프로젝트와 무관합니다.
  앱 타깃 구성은 `docs/MAC_BUILD_GUIDE.md`를 따르세요.
