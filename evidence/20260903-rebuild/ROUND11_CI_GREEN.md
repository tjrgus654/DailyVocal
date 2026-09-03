# ROUND 11 — GitHub 공개 + CI 타입체크 초록 (Mac 이전 최종 게이트)

날짜: 2026-09-03 · 저장소: https://github.com/tjrgus654/5VocalMaster (public, main)

## 무엇을 했나

Windows에서 불가능했던 **실제 swiftc -typecheck(macOS iphonesimulator SDK)** 를
GitHub Actions로 실행해 앱 32파일 + 위젯 익스텐션 전체를 타입 수준까지 검증,
6라운드 반복으로 초록을 만들었다. `-parse`(구문)가 잡지 못하는 오류군만 나왔다.

## CI 라운드 로그 (전체 이력 위 gh run list 참조)

| 라운드 | 오류 | 수정 |
|---|---|---|
| 1 | deinit(비격리)에서 MainActor 저장 프로퍼티 접근 ×2 (DailyRoutineViewModel) | 관찰자/타이머 토큰을 `nonisolated(unsafe)`로 선언 (VocalAudioEngine·PitchTrackerViewModel 동일 패턴 선제 수정) |
| 2 | internal @Model 타입을 public 메서드 파라미터로 사용 + 인스턴스 컨텍스트의 정적 멤버 접근 | @Model 3종(PracticeSession·UserProfile·PitchRecord) public 승격, `Self.dayFormatter` |
| 3 | `ZeroFormattingBehavior.padUnits` 미존재 | `.pad` (LiveActivityManager) |
| 4 | 격리 컨텍스트의 `lazy var` 제약 | toneFormat을 계산 프로퍼티로 전환 |
| 5 | `private(set) restNotice`를 뷰 바인딩에서 직접 할당 | `clearRestNotice()` 공개 메서드 우회 |
| 6 | Int 표현식 → Double 파라미터 (PianoStrip) | `Double(48 + degree)` (전역 유사 패턴 스캔→없음 확인) |

**최종: `iOS typecheck` success — Typecheck app sources ✓ / Typecheck widget extension ✓**

## 로컬 최종 검증 (푸시 직전)

- `verify_swift_parse.sh` 32/32 · `verify_static.py` ALL PASS · live.html JS vm.Script OK
- 시크릿 스캔 무(공개 전제) · `.gitignore` 신규 작성

## 커밋 구성

1. `feat: 5분 보컬 iOS 앱 전체 구현` — 초기 임포트 129파일
2~6. `fix: ... (CI 라운드 N)` — 각 라운드 수정 (논리적 변경 = 커밋 1개 원칙)

## 공개(public)로 선택한 근거

macOS 러너는 무료 한도가 10배 배율로 소모되지만 public이면 무제한 무료.
초록까지 반복 푸시가 필요했고 저장소에 시크릿이 없음을 스캔으로 확인.
이후 private 전환은 Settings에서 가능(전환 시 남은 러너 사용량 과금 주의).

## Mac에서의 남은 작업 (이제 정말 실행 단계만)

1. 저장소 클론 → `README_XCODE.md` 따라 Xcode 프로젝트 생성(파일 추가만)
2. 시뮬레이터 빌드·구동 — 온보딩/루틴/트래커/연구소/기록 전 플로우
3. 실기: 마이크 권한, AVAudioSession 실동작, Live Activity, 햅틱
4. App Icon 등 에셋
