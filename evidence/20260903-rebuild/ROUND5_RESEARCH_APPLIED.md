# ROUND 5 — 외부 리서치(MCP 총동원) + 근거 기반 콘텐츠 적용

날짜: 2026-09-03 · 목표: 유사 앱/보컬 훈련법 조사 → 앱에 실제 반영

## 1. 사용한 MCP/리서치 도구 (전부 실제 호출, 결과 기록됨)

| 도구 | 대상 | 산출 |
|---|---|---|
| `mcp__plugin_document-skills_image_search__search_image` | "singing pitch training app…", "vocal pitch training app real-time feedback interface" | 한국 발성 앱 16일 커리큘럼 스크린샷(dodotdo), 노래방 피치 추적 게임플레이(vocaberry) 확보 |
| `mcp__4_5v_mcp__analyze_image` | 위 이미지 2장 원격 URL | 레이아웃·커리큘럼 순서·피치 시각화 패턴 상세 분석 |
| `mcp__web_reader__webReader` | singingcarrots.com/pitch-training, voicescienceworks.org/sovt-exercises.html | 훈련 루프 구조 + SOVT 과학(역압, 15분/일, 대체 기법, 증상별 처방) |
| `WebSearch` | 웜업/쿨다운 세션 길이 근거 | Ragsdale 2022, Ragan 2016 (Journal of Voice) |

## 2. 핵심 조사 결과 → 설계 판정

1. **웜업 5–10분이면 충분, 15분 추가 효과 없음** (Ragsdale 2022, J. Voice; PMID 32891479)
   → 우리 구조(2분 퀵 + 15분 풀 세션)가 근거와 정합. 세션을 더 길게 늘리지 않는 방향 유지.
2. **쿨다운에 SOVT(빨대/허밍)가 가장 효과적, 12–24시간 후 차이 보고** (Ragan 2016, J. Voice; PMID 26778328)
   → W2/W3 마지막 단계에 쿨다운 라인 신규 추가, W4는 기존 유지.
3. **SOVT 역압 원리 + 빨대 대체 기법(허밍/립트릴/으) + 하루 15분** (VoiceScienceWorks)
   → W1 1단계·퀵 루틴에 "립트릴 안 되면 빨대" 대체안 추가. 팁 id 49 신규.
4. **Singing Carrots 채점 철학: "고음이 더 높은 점수 아님"(음역 보호), 단음→시퀀스 순서, 음역 맞춤 조정**
   → 우리 노래방 점수는 이미 정확도 기반(정합). 팁 id 51로 사용자 인식 개선. 훈련 순서(단음 유지→패턴)도 이미 정합.
5. **한국 발성 앱 16일 커리큘럼 순서**: 호흡→편안한 소리→목 이완→성대 강화→파워→믹스→후두 개방→폐쇄→SOVT→파사지오→고음
   → 우리 4주 로드맵(W1 이완/호흡 → W2 가성 스위치 → W3 파사지오 → W4 실전)과 동일한 대형. 유지.
6. **Vocaberry 노래방 UI**: 피치 하이웨이+실시간 골드 트레이스, 단일 히어로 점수, 옥타브×12 히트맵
   → 히어로 점수(우리 세션 점수 S~D)·실시간 피치 궤적(피치 캔버스) 이미 보유. 옥타브 히트맵은 로드맵 유지.

## 3. 변경 파일

| 파일 | 변경 |
|---|---|
| `Models/RoutineStep.swift` | 헤더에 근거 명시. W1-1에 수분 큐+빨대 대체안 2줄. W2-5/W3-5에 SOVT 쿨다운 라인. 퀵 루틴 1줄에 빨대 대체 안내. |
| `Resources/vocal_tips.json` | 연구 기반 팁 4종 추가(id 49 SOVT 과학 / 50 쿨다운 / 51 정확도 우선 / 52 성대 보호·휴식). youtubeId="" (원본 쇼츠 없음), viewCount=0, 연관 팁은 같은 카테고리에서 배정. 총 48→52. |
| `Models/VocalTip.swift` | `youtubeURL` 빈 id 가드 (빈 쇼츠 링크 버튼 제거). |
| `Views/VocalLab/TipDetailView.swift` | viewCount>0일 때만 "쇼츠 조회수" 표시, 0이면 "연구 기반 팁" 배지. |
| `ViewModels/DailyRoutineViewModel.swift` | `sessionsCompletedToday`(4AM 롤오버 키 = 스트릭 로직 동일) 추적, `isVoiceRestRecommended`(≥2회). 세션 저장 시 갱신. |
| `Views/DailyRoutine/DailyRoutineView.swift` | 완료 알림: 모드별 제목(15분/2분 퀵), 하루 2회 이상이면 성대 회복 권장 메시지로 분기. |

## 4. 검증 (실행 결과)

- `verify_swift_parse.sh` → **swift-frontend -parse: 통과 32 / 실패 0** (전 앱 + 위젯 소스)
- `evidence/20260903-rebuild/verify_static.py` → **ALL CHECKS PASSED** (52 tips 필드/카테고리/연관 정합, 중복 0)
- preview/*.html은 상세 가이드 텍스트를 렌더하지 않는 디자인 목업 → 콘텐츠 변경 동기화 불필요 확인

## 5. 생략한 것

- 옥타브×12 히트맵 결과 화면(Vocaberry식): 가치는 확인했으나 신규 뷰+데이터 집계가 필요해 로드맵 유지(정확도 추이 차트와 함께).
- 백그라운드 리서치 에이전트 2종은 컨텍스트 리셋으로 소실 — 동일 범위를 위 표의 직접 MCP 호출로 대체 완료(커버리지 동등).
