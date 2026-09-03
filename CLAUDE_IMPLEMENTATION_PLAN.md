# 🔍 "5분 보컬" iOS 앱 전수 코드 검사 종합 보고서

> **검수 방법**: 4개의 독립 전문 검수 에이전트가 오디오 엔진, 뷰모델, 뷰 레이어, 데이터 모델을 각각 심층 분석한 결과를 종합했습니다.

---

## 🚨 솔직한 총평: D+ (빌드조차 안 되는 수준)

**결론부터 말하면, 이 코드는 Xcode에 넣어도 빌드 자체가 불가능합니다.** 6분 만에 5,500줄을 쏟아냈지만, 빠르게 쓰느라 핵심적인 부분들이 빠지거나 엉켜있습니다.

> [!CAUTION]
> 현재 상태 그대로 Mac Xcode에 가져가면 **컴파일 에러가 20개 이상 발생**하며, 설령 에러를 잡아도 **앱이 크래시하거나 기능이 먹통**인 부분이 다수 존재합니다.

---

## 📊 영역별 검수 결과 요약

| 영역 | 등급 | 핵심 문제 |
|:---|:---:|:---|
| **🔴 오디오 엔진 (YIN 피치 감지)** | **F** | UnsafePointer 크래시, 샘플레이트 불일치(1.5반음 오차), O(N²) CPU 폭탄 |
| **🔴 뷰 레이어 (SwiftUI Views)** | **F** | `glassCard(padding:)` 인자 불일치로 **전 파일 컴파일 실패**, `ProgressView` 이름 충돌 |
| **🟠 뷰모델 레이어** | **D** | 무한루프 앱 멈춤 위험, 실시간 UI 미갱신(Stale), 오디오 상태 누수 |
| **🟡 데이터 모델 & JSON** | **C** | JSON 48개 중 40%가 복붙 더미, @Relationship 초기화 버그 |
| **🟡 기획/UX 완성도** | **C+** | NavigationStack 전무, 유튜브 의존적 설계 |

---

## 🔴 치명적 버그 상세 (빌드 불가 / 크래시)

### 1. `glassCard(padding:)` — 전 파일 컴파일 실패 (20개소 이상)

`Design/GlassCard.swift`의 `.glassCard()` 확장 메서드에는 `padding:` 매개변수가 **정의되어 있지 않습니다**. 그런데 거의 모든 View 파일에서 `padding:` 인자를 넘기고 있어, Xcode가 `Extra argument 'padding' in call` 에러를 **최소 20군데**에서 뿜어냅니다.

```
❌ DailyRoutineView.swift:96  — .glassCard(cornerRadius: 12, padding: 6)
❌ PitchTrackerView.swift:43  — .glassCard(cornerRadius: ..., padding: 0)
❌ VocalLabView.swift:84      — .glassCard(cornerRadius: 10, padding: 4)
❌ ProgressView.swift:104     — .glassCard(cornerRadius: 18, padding: 16)
❌ OnboardingView.swift:184   — .glassCard(cornerRadius: 16, padding: 14)
❌ StepDetailCard.swift:130   — .glassCard(cornerRadius: ..., padding: 18)
❌ HeatmapCalendarView.swift  — .glassCard(cornerRadius: 18, padding: 16)
❌ VocalRangeChart.swift      — .glassCard(cornerRadius: 18, padding: 16)
... 총 20개소 이상
```

### 2. `ProgressView` 이름 충돌 — SwiftUI 기본 컴포넌트와 100% 충돌

`Views/Progress/ProgressView.swift`의 `public struct ProgressView: View`가 SwiftUI 내장 `ProgressView`(로딩 스피너)와 정면 충돌합니다. `MainTabView.swift`에서 `ProgressView()`를 호출하면 컴파일러가 어떤 건지 판별 불가하여 **Ambiguity 에러**가 발생합니다.

### 3. 오디오 엔진 UnsafePointer — 앱 크래시 (EXC_BAD_ACCESS)

`VocalAudioEngine.swift`에서 오디오 콜백의 `floatChannelData` 포인터를 **복사 없이** 백그라운드 큐로 넘기고 있습니다. CoreAudio가 콜백을 끝내면 해당 메모리를 즉시 재사용하므로, 백그라운드에서 YIN 연산을 돌리는 순간 **이미 덮어씌워진 메모리를 읽어** 크래시하거나 노이즈 데이터를 감지합니다.

### 4. 하드웨어 샘플레이트 불일치 — 음정이 1.5반음 틀림

코드가 `sampleRate = 44100.0`을 하드코딩하지만, iPhone 15 Pro Max는 실제로 **48000Hz**로 마이크를 구동합니다. `setPreferredSampleRate`는 요청일 뿐 강제가 아닙니다.
$$\frac{44100}{48000} \approx 0.919 \quad \Rightarrow \quad \text{약 1.5반음 낮게 측정}$$
**C4를 불러도 B3으로 표시**되는 치명적인 음정 오차가 발생합니다.

### 5. `calculateStreak` 무한루프 — 앱 완전 멈춤

`ProgressViewModel.swift`의 `while true` 루프에서 `Calendar.date(byAdding:)` 실패 시 `?? checkDate`가 반환되면 날짜가 변하지 않아 **무한 루프에 빠져 앱이 영구적으로 멈춥니다**.

---

## 🟠 주요 기능 미작동 문제

### 6. 실시간 파형/스케일 표시가 안 됨 (Stale UI)

`DailyRoutineView`가 `viewModel`만 `@StateObject`로 관찰하고, `viewModel.audioEngine`(싱글톤)은 관찰 대상이 아닙니다. 따라서 **마이크로 소리를 내도 파형 게이지가 전혀 움직이지 않고**, 스케일이 재생되어도 음표 뱃지가 갱신되지 않습니다.

### 7. 피치 트래커 백그라운드 상태 누수

`PitchTrackerViewModel.handleFrequencyUpdate()`에 `guard isListening` 체크가 없어, 측정을 끄거나 다른 탭으로 이동해도 **백그라운드에서 계속 햅틱을 진동시키고, 히스토리를 채우고, 정확도를 왜곡**합니다.

### 8. NavigationStack 전면 누락

`MainTabView`의 4개 탭 어디에도 `NavigationStack`이 없어, 화면 간 푸시 전환이 완전히 불가능합니다. 팁 상세 화면이나 설정 화면으로의 네비게이션이 아예 동작하지 않습니다.

### 9. DB 변경이 통계에 반영 안 됨

`ProgressViewModel`이 SwiftData의 `@Query`를 사용하지 않고 수동 `fetch()`를 1회만 수행합니다. 루틴을 완료하고 성장 기록 탭으로 이동해도 **세션 수, 스트릭, 히트맵이 갱신되지 않습니다**.

---

## 🟡 데이터 품질 문제

### 10. 48개 쇼츠 데이터 중 40%가 복붙 더미

| 카테고리 | 개수 | 문제 |
|:---|:---:|:---|
| practical_tips | **19개 (40%)** | 19개 전부 동일한 "지퍼 잠그기" 비유와 "네이→모음→가사" 실천법으로 복사됨 |
| breathing | 5개 | 5개 전부 동일한 "풍선 주둥이" 비유 |
| 기타 4개 카테고리 | 각 5~7개 | 카테고리 내 모든 항목이 동일한 대표 텍스트 |

**제목과 유튜브 ID만 다르고, 핵심 교육 콘텐츠(비유, 실천법)가 전부 복사-붙여넣기**입니다. 이 상태로는 발성 연구소가 같은 내용만 반복하는 무의미한 화면입니다.

### 11. `relatedShorts`가 산술 공식으로 생성

관련 쇼츠가 `[(id % 48) + 1, ((id + 3) % 48) + 1]`로 기계적으로 생성되어, 호흡 팁의 관련 쇼츠가 비강공명이나 박효신 후두 쇼츠를 추천하는 등 **전혀 상관없는 콘텐츠끼리 연결**되어 있습니다.

---

## 📐 사용자 요구 vs 현실 격차

> **"어플 자체 기능만으로 보컬 트레이닝이 가능했으면 하는거야"**

현재 앱이 이 요구를 충족하지 못하는 이유:

| 요구 | 현재 상태 | 부족한 이유 |
|:---|:---|:---|
| **앱만으로 발성 교정** | ❌ 유튜브 링크 의존 | 팁 카드에 유튜브 링크만 있고, **앱 내 시범 오디오/애니메이션 없음** |
| **실시간 피치 가이드** | ❌ 빌드 불가 | 오디오 엔진이 크래시하고 음정이 1.5반음 틀림 |
| **단계별 진척 확인** | ❌ DB 미연동 | 루틴 완료해도 통계가 안 올라감 |
| **초보자 눈높이** | ⚠️ 부분 충족 | 48개 팁 중 40%가 동일 내용 복붙 |
| **매일 사용 가능** | ❌ 앱 멈춤 위험 | 무한루프 버그, 메모리 누수 |

---

## ✅ 이걸 완벽하게 고치려면 어떻게 해야 하는가?

> [!IMPORTANT]
> 아래 재구현 계획을 승인해 주시면, 모든 치명적 버그를 수정하고, 48개 쇼츠를 각각 고유한 내용으로 채우고, 앱 자체만으로 보컬 트레이닝이 가능한 수준까지 완성하겠습니다.

### Phase 1: 즉시 수정 — 빌드 가능하게 (컴파일 에러 0개)
1. `GlassCard.glassCard()` 메서드에 `padding:` 매개변수 추가
2. `ProgressView` → `VocalProgressView`로 리네이밍
3. 오디오 엔진 `@MainActor` 제거 + `nonisolated` 분리 설계
4. `UnsafePointer` → `[Float]` 배열 복사 후 백그라운드 전달
5. 하드웨어 `inputFormat.sampleRate` 동적 적용
6. `calculateStreak` 무한루프 방어 가드 추가

### Phase 2: 기능 정상화 — 핵심 기능 동작
7. iOS 17 `@Observable` 매크로로 4개 뷰모델 전면 전환
8. `PitchTrackerViewModel`에 `guard isListening` 가드 추가
9. `ProgressView`에 SwiftData `@Query` 도입 → 실시간 DB 반영
10. `MainTabView` 각 탭에 `NavigationStack` 래핑
11. 오디오 엔진 YIN 루프를 Accelerate `vDSP` 벡터 연산으로 최적화
12. 오디오 엔진 백프레셔(Backpressure) 처리 + 링 버퍼 누적
13. 오디오 세션 인터럽트 핸들링 (전화, 에어팟 연결 등)

### Phase 3: 콘텐츠 완성 — "앱만으로 보컬 트레이닝 가능"
14. **48개 쇼츠 각각 고유한 비유/실천법/키워드로 전수 재작성** (더미 복붙 제거)
15. `relatedShorts`를 실제 내용 기반으로 재매핑
16. 카테고리 편중 해소 (practical_tips 19개 → 8개 수준으로 재분류)
17. **앱 내장 발성 시범 오디오 가이드** 추가 (유튜브 없이 단독 동작)
18. 각 스텝별 **동작 애니메이션 또는 일러스트** (입모양, 호흡 방향 등)
19. 온보딩 음역대 테스트 실제 구현 (현재는 껍데기만 있음)

### Phase 4: 품질 보증
20. `deinit` 및 `.onDisappear` 리소스 정리 전면 추가
21. 오디오 세션 `.setActive(false)` 적절한 시점 호출
22. DateFormatter 캐싱, SwiftData 배열 변경 감지 헬퍼
23. 전체 파일 Swift 6 Strict Concurrency 호환성 검증
