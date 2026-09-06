# 🎙️ "하루보컬" (DailyVocal) — Xcode 빌드 가이드

> **대상:** iPhone(iOS 17.0+, Dynamic Island 기기 권장)
> **스택:** SwiftUI · SwiftData · AVAudioEngine(단일 엔진: YIN/vDSP 피치 감지 + 가이드 신디사이저) · ActivityKit · @Observable

---

## 소스 구조 (2026-09-04 기준)

- 순수 로직(테스트 대상): `Core/Logic/` — VocalLogic·YINPitchDetector·RoutineStep(프리셋)·VocalTip·VocalCategory
- SwiftUI 표현: `Models/VocalCategoryTheme.swift`(색) 등
- 팁 데이터: `Resources/vocal_tips.json` 52종(48 쇼츠 + 4 연구 기반)

## 📱 1. 프로젝트 구조

```
DailyVocal/
├── DailyVocalApp.swift          # @main 진입점, SwiftData 컨테이너
├── Info.plist                     # 마이크 권한, 백그라운드 오디오, arm64
│
├── Design/
│   ├── DesignTokens.swift         # 색상·폰트·그라디언트 토큰
│   └── GlassCard.swift            # 글래스모피즘 modifier + 컨테이너
│
├── Models/                        # SwiftData 모델 + 값 타입
│   ├── UserProfile.swift          # 음역대 baseline/현재, 통계, 알림 설정
│   ├── PracticeSession.swift      # 루틴 세션 기록
│   ├── PitchRecord.swift          # 피치 측정 세션 요약
│   ├── RoutineStep.swift          # 5단계 루틴 정의 + 1~4주차 프리셋
│   ├── VocalCategory.swift        # 6대 카테고리
│   └── VocalTip.swift             # 48개 쇼츠 팁 모델
│
├── Core/
│   ├── Audio/
│   │   ├── YINPitchDetector.swift # YIN F0 추정 (vDSP SIMD 가속, 순수 값 타입)
│   │   ├── VocalAudioEngine.swift # 통합 AVAudioEngine (마이크 탭 + 가이드 톤)
│   │   └── ScaleSequencer.swift   # 5도/옥타브/아르페지오 가이드 시퀀서
│   ├── Haptics/HapticManager.swift
│   ├── LiveActivity/
│   │   ├── VocalActivityAttributes.swift  # 앱+위젯 공유 (양쪽 타깃 멤버십!)
│   │   └── LiveActivityManager.swift
│   └── Notification/NotificationManager.swift
│
├── ViewModels/                    # @Observable 뷰모델 4종
├── Views/                         # 온보딩(음역대 실측) · 루틴 · 피치트래커 · 연구소 · 성장기록
├── Resources/vocal_tips.json      # 52개 팁 (카테고리 재분배 완료)
└── Widget/VocalWidgetBundle.swift # 위젯 익스텐션 전용 (@main 포함)
```

**주의:** `Widget/VocalWidgetBundle.swift`는 **앱 타깃에 넣지 마세요** (`@main` 충돌).
`Core/LiveActivity/VocalActivityAttributes.swift`는 **앱 + 위젯 두 타깃 모두**에 포함해야 합니다.

---

## 🛠️ 2. Xcode 프로젝트 만들기

1. Xcode → **Create New Project…** → **iOS App**
   - Product Name: `DailyVocal` / Interface: **SwiftUI** / Storage: **SwiftData** (체크 안 해도 됨 — 컨테이너를 코드로 생성)
   - Minimum Deployments: **iOS 17.0**
2. 위 폴더의 **`Widget/`을 제외한** 모든 파일·폴더를 네비게이터로 드래그
   - `Copy items if needed` ✅ / `Create groups` ✅ / 타깃 `DailyVocal` ✅
   - **`PrivacyInfo.xcprivacy`도 반드시 포함** (앱 타깃). UserDefaults가
     required-reason API라 매니페스트 없으면 App Store 제출이 거부됨
     (UserDefaults 이유 코드 CA92.1, 수집 데이터 없음, 추적 없음으로 작성돼 있음)
3. `Resources/vocal_tips.json` 선택 → File Inspector의 **Target Membership**에 `DailyVocal` 체크 확인
4. Info 탭에 아래 키가 있는지 확인 (직접 `Info.plist`를 쓰지 않는 경우):
   - `NSMicrophoneUsageDescription` (마이크 권한 문구)
   - `NSSupportsLiveActivities` = YES
   - `UIBackgroundModes` = `audio`
5. **Build Settings → Swift Language Version을 `Swift 5`로 확인**
   - Xcode 16+ 신규 프로젝트 기본이 Swift 6 모드면 본 코드의 일부(deinit 등)가
     strict concurrency 규칙에 걸릴 수 있습니다. `SWIFT_VERSION = 5.0` 권장.
6. **Signing & Capabilities** → `+ Capability` → **Background Modes** → `Audio, AirPlay, and Picture in Picture` 체크
   - ⚠️ Push Notifications capability는 필요 없습니다 (로컬 알림만 사용)

> 알려진 플랫폼 한계: 루틴 실행 중 앱을 강제 종료하면 다이내믹 아일랜드 Live Activity가
> 즉시 사라지지 않을 수 있습니다 (ActivityKit 제약 — 몇 분 내 staleDate 경과로 소멸).

---

## 🏝️ 3. 다이내믹 아일랜드 위젯 (선택, 권장)

1. **File → New → Target… → Widget Extension**, 이름 `VocalWidget`
   - **Include Live Activity** ✅
2. 자동 생성된 위젯 파일들의 내용을 `Widget/VocalWidgetBundle.swift`로 교체
   (이 파일은 `VocalWidget` 타깃에만 속함)
3. `Core/LiveActivity/VocalActivityAttributes.swift`의 Target Membership을
   `DailyVocal` + `VocalWidget` **둘 다** 체크

---

## 📲 4. 실기기 설치

1. iPhone 연결 → 기기 신뢰 → 설정 > 개인정보 보호 및 보안 > **개발자 모드 켬**
2. Xcode 상단에서 기기 선택 → `Cmd + R`
3. 첫 실행 시 마이크 권한 요청 → 허용

---

## ✅ 5. 빌드 후 체크리스트

- [ ] 온보딩 3페이지에서 **음역대 실측**이 동작하는가 (마이크 켜고 최저~최고음 글라이딩)
- [ ] 일일 루틴: 타이머·가이드 톤·파형이 스텝마다 전환되는가
- [ ] 피치 트래커: 목표음 선택 → 측정 시작 → 궤적/정확도/햅틱이 실시간인가
- [ ] 성장 기록: 세션 완료 즉시 스트릭·잔디·음역대가 갱신되는가
- [ ] 루틴 중 화면 잠금 시 다이내믹 아일랜드에 카운트다운이 뜨는가

문제가 발생하면 콘솔에 출력되는 `VocalAudioEngine`/`SwiftData` 오류 메시지를 함께 확인하세요.

---

## 🎙️ 6. 실기 오디오 확인 절차 (마지막 기술 갭 — 물리 마이크→inputNode)

CI가 입증한 것은 "버퍼 이후 전 경로"입니다(macOS 통합 테스트 6종: 합성 음성 →
AVAudioPCMBuffer → 프레임 → YIN(vDSP) → RMS → Goertzel). 실기에서만 확인할 수
있는 것은 그 앞의 **물리 마이크 → AVAudioSession → inputNode tap** 구간 —
기기 마이크 하드웨어·세션 활성화·권한 타이밍은 시뮬레이터와 다르게 동작합니다.

### 6.1 10분 실측 프로토콜 (개발 빌드, 기기 연결 상태)

각 단계에서 실패하면 콘솔 로그를 evidence에 남기세요.

| # | 단계 | 통과 기준 | 확인 중인 계층 |
|---|---|---|---|
| A | 온보딩 음역 측정 | 궤적이 글라이딩을 추적, 최저/최고음 저장 | inputNode tap + YIN |
| B | 단음 유지 15초 | 얼럿에 '최장 지속 ≥ 14초'(호흡 지원 지문) | 지속 측정 + 얼럿 라인 |
| C | 비브라토 체크 | 결과 카드에 속도 4~7Hz·규칙성 표시(일부러 흔들면) | 창별 수집 + 자기상관 |
| D | 셈여림 아치 | 여림→셈→여림 후 레인지 ≥ 6dB 인정 | RMS 포락선 |
| E | 화음 부르기 | 드론 2초 후 성부 유지, 방향 피드백 표시 | 드론 재생 + 센트 수집 |
| F | 민요 1곡(아리랑) | 데모 청취 후 노트별 창 이동, 점수 저장 | 시퀀스 드릴 + 스텝 지문 |
| G | 인터럽션 | 측정 중 전화 수신 거절 → 세션이 깨끗이 종료 | 오디오 인터럽션 옵저버 |
| H | 백그라운드 전환 | 홈 화면 10초 → 복귀 시 측정 계속 or 정상 종료 | 세션 수명 |

- **A~F는 각 모드의 실측 파이프라인 전경로**, G~H는 iOS 수명주기.
- 통과 기준을 만족하면 `evidence/<날짜>-device-audio/`에 단계별 스크린샷/로그를
  남기고 VERIFICATION_LOG에 기록 — 이 문서의 프로토콜이 증거 형식을 정의합니다.

### 6.2 기기별 확인 우선순위

1. **자주 쓰는 기기 1대**(주 사용 기종) — 위 8단계 전체
2. 세대가 다른 기기 1대(구형) — A·B·G만: 마이크 하드웨어 차이와 인터럽션
3. 이어폰(유선/무선) 1회 — B·E: 입력 경로 전환 시 세션 재시작 동작

---

## 🚀 7. TestFlight 베타 전 단계 (실기 확인 다음)

사전 조건: Apple Developer Program(유료) 계정.

1. **App Store Connect에 앱 등록** — 번들 ID `com.tjrgus654.dailyvocal` 매칭,
   SKU 설정. 앱 이름은 설명문 초안의 '하루보컬'(APP_STORE_CHECKLIST §4 참고).
2. **아이콘 에셋 추가** — AppIcon.appiconset 1024×1024(§3 사전 작업).
3. **Archive 업로드** — Xcode > Product > Archive > Distribute App >
   App Store Connect. 코드 서명은 자동 관리.
4. **내부 테스터 등록**(최대 100명, 심사 없음) — 팀 멤버. 베타 1차 확인:
   - 위 6.1 프로토콜 A~F를 테스터 기기에서 1회씩
   - 크래시 없음(스모크 CI가 런타임 크래시는 이미 걸러줌)
5. **외부 테스터**(심사 필요, 간단 정보 제출) — 필요 시.
6. **TestFlight 배포 후 1주일 관찰** — 크래시 리포트·마이크 관련 피드백 위주.
   PrivacyInfo.xcprivacy가 이미 준비돼 있어 심사 정보 입력은 최소화됩니다.

### 출시 블로커 체크 (현재 상태)

- [x] 기능 완성도(CI 크래시 검증) · [x] 프라이버시(수집 0종) ·
  [x] 저작권(PD 원형만) · [x] 의료 주장 부재
- [ ] **아이콘 1024** · [ ] **실기 6.1 프로토콜** · [ ] 스크린샷 촬영(§6 가이드)
