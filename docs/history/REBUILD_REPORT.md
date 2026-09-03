# 🛠️ 5VocalMaster 전면 재구현 보고서 (2026-09-03)

> 이 문서는 구버전 `CLAUDE_WALKTHROUGH.md`("결함 23건 100% 수정 완료"를 주장했으나 실제로는
> 빌드 파괴 유령 파일 2개가 남아 있던 문서)를 대체한다.
> 이번 재구현은 기존 Gemini 코드를 신뢰하지 않고, Claude의 검수 계획(Phase 1~4) + 추가로
> 발견된 결함 전체를 기준으로 **처음부터 다시 작성**한 결과다.

---

## 1. 무엇을 다시 만들었나

**원칙:** 이전 코드에서 그대로 가져온 것은 콘텐츠 데이터(`vocal_tips.json` 본문, 디자인 토큰 2개 파일)뿐.
나머지 32개 Swift 파일 전부 재작성. 유령/고아 파일 10개 삭제.

### 아키텍처 변경 (구 → 신)

| 영역 | 구 (Gemini) | 신 (재구현) |
|---|---|---|
| 오디오 | `AVAudioEngine` **2개** (감지용/신디용가 각자 세션 장악) | **엔진 1개**가 마이크 탭 + 가이드 톤 출력을 함께 소유, 유휴 시 자동 정지/세션 비활성화 |
| YIN 피치 감지 | 순수 Swift O(N²) 이중 루프 (주석만 "vDSP") | 차분함수를 `vDSP_vsub`+`vDSP_svesq` **SIMD 가속**, tau 범위를 탐지 대역으로 제한, 신뢰도(concept: 1−CMNDF) 반환 |
| 백프레셔 | isAnalyzing 플래그 (MainActor 경합 소지) | `FrameGate`(@unchecked Sendable, 락 보호) — 최대 2프레임 인플라이트, 초과 프레임 드롭 |
| 상태 관리 | ObservableObject/@Published | **@Observable** (iOS 17) + 뷰에서 `@State` 뷰모델 |
| 뷰 리렌더 | 뷰모델이 엔진 상태를 릴레이 복사 | 엔진·시퀀서를 읽는 잎사귀 뷰(`LiveNoteDisplay`, `PianoStrip`, `GuideNoteBadge`, `LiveFeedbackIndicator`)로 격리 — 23Hz 갱신이 화면 전체를 리렌더하지 않음 |
| 음역대 통계 | **하드코딩** ("C3~F4"→"C3~A4", "+4반음" 고정 문자열) | 온보딩 실측이 baseline, 피치 측정 세션이 현재 음역대를 갱신 → 반음 확장 자동 계산 |
| 루틴 완료 판정 | 건너뛰어도 무조건 전체완료 저장 | 스텝별 70% 이상 실천여부 추적 → 부분완료/전체완료 구분 |
| 주차별 루틴 | `week` 파라미터 무시(매주 동일) | **1~4주차 실제 상이한 프리셋** (가이드의 4주 로드맵 반영) |
| UserProfile | 통계 필드가 전부 데드코드 | 세션 완료 시 총시간/세션수/마지막 연습일/주차 갱신 |
| 알림 | 구현만 있고 호출 없음 | 온보딩 동의 → 매일 20:00 + 22:30 스트릭 경고 스케줄, 성장기록 탭에서 토글 |

### 계획(Clauade Phase 1~4) 대비 구현 상태

| Phase | 항목 | 상태 |
|---|---|---|
| 1 | 빌드 가능화 6건 (glassCard 인자, ProgressView 충돌, nonisolated 분리, 딥카피, 샘플레이트 동적화, 스트릭 가드) | ✅ 전부 |
| 2 | @Observable 전환 / isListening 가드 / @Query / NavigationStack / **vDSP YIN** / 백프레셔 / 인터럽션 핸들링 | ✅ 전부 (+루트체인지 재시작) |
| 3 | 48팁 전수 재작성(기존 데이터 유지·검증) / relatedShorts 재매핑 / **카테고리 편중 해소** / 앱 내장 가이드 오디오 / 온보딩 **음역대 실측** | ✅ (애니메이션/일러스트: 이모지+텍스트 가이드로 대체, 별도 에셋 없음) |
| 4 | deinit/onDisappear 정리 / 세션 deactivate / DateFormatter 캐싱 / 동시성 위생 | ✅ (Swift 6 strict 모드 준수까지는 보증하지 않음 — 기본 Swift 5 모드 기준) |

### 추가로 발견·해결한 구 결함 (계획서에 없던 것)

- 유령 파일 `PitchTrackerLiveView` / `ScalePlayerView` (존재하지 않는 API 8종 호출) → **삭제**
- 고아 파일 `ChallengeView`, `ProgressView.swift`(typealias만), `Components/*`, `VocalRoutine`, `ShortsTip` → 삭제
- 가이드 톤↔마이크 피드백 루프: 목표음 청취 중 1.6초 피치 프레임 무시 + 루틴 중 파형은 재생 음표로 표시 전환
- 햅틱 스팸(프레임당 진동) → 상승 엣지 + 0.5초 스로틀
- 잔디 히트맵 열 정렬 불일치(요일 헤더와 실제 열이 어긋남) → 월요일 앵커 12주 그리드로 수정
- 파형 바의 절반이 sin 음수로 항상 최소높이 → 전 바 반응하는 프로파일로 수정
- Info.plist `armv7` → `arm64`
- README의 불필요한 Push Notifications capability 안내 제거 (로컬 알림은 불필요)
- 위젯 `@main` 파일을 앱 타깃에 넣으면 충돌하는 문제 → README에 명시적 경계 + 구조 불변량 검증

## 2. 검증 (증거: `evidence/20260903-rebuild/`)

정적 검증 7개 항목 전부 통과 — 상세는 `evidence/20260903-rebuild/EVIDENCE.md`:
유령 심볼 0, 괄호 균형 32/32 파일, @main 배치 정상, **인스턴스-멤버 참조 92개 전부 정의로 해석**,
커스텀 타입 44개 전부 정의, 핵심 API 시그니처 확인, tips JSON 48개 정합(중복 0, 연관 유효).

**한계 (솔직하게):** 이 머신은 Windows라 Xcode 빌드를 돌릴 수 없다.
최종 확인은 Mac에서 `Cmd+R` — 실패 시 콘솔의 컴파일 오류가 그대로 피드백이 된다.
`ios_simulator.html`(구버전 웹 목업)은 새 구현과 불일치하므로 참고용으로만 둠(삭제해도 무방).
