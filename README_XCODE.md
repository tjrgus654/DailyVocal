# 🎙️ "5분 보컬" (5VocalMaster) — Xcode 빌드 가이드

> **대상:** iPhone(iOS 17.0+, Dynamic Island 기기 권장)
> **스택:** SwiftUI · SwiftData · AVAudioEngine(단일 엔진: YIN/vDSP 피치 감지 + 가이드 신디사이저) · ActivityKit · @Observable

---

## 📱 1. 프로젝트 구조

```
5VocalMaster/
├── 5VocalMasterApp.swift          # @main 진입점, SwiftData 컨테이너
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
├── Resources/vocal_tips.json      # 48개 팁 (카테고리 재분배 완료)
└── Widget/VocalWidgetBundle.swift # 위젯 익스텐션 전용 (@main 포함)
```

**주의:** `Widget/VocalWidgetBundle.swift`는 **앱 타깃에 넣지 마세요** (`@main` 충돌).
`Core/LiveActivity/VocalActivityAttributes.swift`는 **앱 + 위젯 두 타깃 모두**에 포함해야 합니다.

---

## 🛠️ 2. Xcode 프로젝트 만들기

1. Xcode → **Create New Project…** → **iOS App**
   - Product Name: `5VocalMaster` / Interface: **SwiftUI** / Storage: **SwiftData** (체크 안 해도 됨 — 컨테이너를 코드로 생성)
   - Minimum Deployments: **iOS 17.0**
2. 위 폴더의 **`Widget/`을 제외한** 모든 파일·폴더를 네비게이터로 드래그
   - `Copy items if needed` ✅ / `Create groups` ✅ / 타깃 `5VocalMaster` ✅
   - **`PrivacyInfo.xcprivacy`도 반드시 포함** (앱 타깃). UserDefaults가
     required-reason API라 매니페스트 없으면 App Store 제출이 거부됨
     (UserDefaults 이유 코드 CA92.1, 수집 데이터 없음, 추적 없음으로 작성돼 있음)
3. `Resources/vocal_tips.json` 선택 → File Inspector의 **Target Membership**에 `5VocalMaster` 체크 확인
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
   `5VocalMaster` + `VocalWidget` **둘 다** 체크

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
