# Evidence — 라운드 3: 디자인 오버홀 + 기능 3종 + 아이폰 프레임 프리뷰 (2026-09-03)

## 사용자 피드백 반영

"폰트·전체적으로 아쉽다 / 노치도 있을 거고 / 계획처럼 깔쌈한 느낌 아니다 / 기능도 더 추가해서 완벽하게"

## 1. 디자인 오버홀 (앱 + 프리뷰 동시 적용)

| 항목 | 변경 |
|---|---|
| 타이포그래피 | SF Pro **Rounded** 디스플레이 스택 전면 채택(timer 60pt/screenTitle 24pt Heavy/note 52pt Black/eyebrow 토큰 신설), 숫자 tabular, 트래킹 타이트화 |
| 배경 | 평면 그라디언트 → **AppBackground**(딥네이비 수직 + 인디고 오로라 방사 + 시안 하단 글로우), 6개 화면 전부 교체 |
| 글래스 카드 | 상단 0.8pt **광택 스트로크**(cardSheen) + 재질 농도 조정 + 그림자 정제(0.30/16/8) |
| 타이머 링 | 16pt→13pt 슬림화 + **브랜드 글로우 섀도우** + 258px |
| 헤더 | eyebrow/타이틀 이중 위계 정돈 |

## 2. 신규 기능 (경쟁앱 리서치 기반 S-size)

1. **2분 퀵 루틴** — 모드 세그먼트(15분 풀코스/2분 퀵), `RoutinePresets.quickRoutine()`
   (립트릴→허밍→사이렌 40초씩), 세션 저장에 "2분 퀵" 기록. 근거: 동기 저하일 짧은
   세션 패턴(Riyaz/Vanido), 스트릭 유지.
2. **주간 목표 5일** — ProgressViewModel 주간 실천일 계산(월~일), 스트릭 배너 내
   그라디언트 프로그레스 바. 근거: Duolingo 7일 마일스톤 프레이밍.
3. **팁 즐겨찾기** — 별 토글(목록 행 + 상세 시트), ⭐즐겨찾기 칩 필터,
   UserDefaults `favoriteTipIds`(단일 소스: `Self.favoritesKey`).

## 3. 프리뷰 v3 — 실제 아이폰 프레임

- **다이내믹 아일랜드 블랙 필 + 9:41 상태바 + 세이프에어리어(54px)** 포함 프레임.
- 신규 디자인 언어 전부 반영, 신규 기능 상태 포함 9화면:
  intro / rangetest / routine / **quick** / tracker / lab / **lab_fav** / tipdetail / progress
- 촬영: `preview/shots/v3_*.png` (1.6배, 고해상도)

## 4. 비전 검증 결과 (analyze_image, 시니어 디자이너 프롬프트)

| 화면 | 판정 |
|---|---|
| routine(신디자인) | **9/10** — 오로라 배경·링 글로우·글래스 광택 "프리미엄 인디 상위권". 아일랜드 프레임 "실제 아이폰 스크린샷처럼 보임" |
| quick(2분 모드) | 퀵 상태 구분 명확(세그먼트+배지), 싱글스텝 레이아웃 균형 통과 |
| progress | 배너 4정보 스캔 가능 통과, 주간 목표 바 배치 통과, 히트맵 정렬 통과 |
| lab | 즐겨찾기 칩 별도 컨트롤 인식 통과, 별 토글 균형 통과 |

OCR 한글 오판은 이전 라운드와 동일하게 DOM innerText로 반박 완료(스크립트 app=7266자 정상 렌더).

## 5. 최종 정적 검증

`verify_static.py`: **ALL CHECKS PASSED** + 신규 심볼 스팟체크
(AppBackground 6화면, quickRoutine 정의+2호출, weeklyPracticeDays 6, toggleFavorite 3,
isMicPermissionDenied 7, pausedRemainingText 8, favoritesKey 단일소스 3).

## 남은 한계 (기존과 동일)

- Windows 폰트 대체(Segoe UI/맑은 고딕) — 실기기는 SF Pro Rounded로 렌더되므로 앱은 더 좋아짐.
- 최종 판정은 Mac Xcode 빌드.
