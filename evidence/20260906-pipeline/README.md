# 2026-09-06 — 실기 오디오 확인 경로 리서치 + Swift 파이프라인 실측

## 리서치 결론 (2026-09-06 웹 검색)
- `xcrun simctl`에는 오디오 파일을 마이크 입력으로 주입하는 기능이 없다.
- 유일한 WAV→마이크 경로는 가상 오디오 드라이버(BlackHole 등) — GitHub Actions
  macOS 러너에서 설치가 취약(시스템 확장+재부팅 승인)하고 물리 입력 디바이스가
  없어 tap 자체가 안 열릴 수 있다. 상용(TestMu AI 등) 솔루션이 존재한다는 것 자체가
  이 갭이免费로 안 풀린다는 증거.
- **CI 표준 패턴 = 버퍼 레벨 주입**: WAV/합성 신호를 AVAudioPCMBuffer로 만들어
  마이크 tap과 동일한 프레임 처리 경로에 직접 흘리고, 마이크 입력만 얇은 어댑터로
  제외한다. UI 테스트에는 `simctl privacy grant microphone`으로 권한 게이트 제거.

## 구현
- `VocalLogic.SpectralAnalysis.magnitudeSpectrum` — Goertzel 512빈 스펙트럼을
  엔진에서 순수 로직 모듈로 이동(엔진은 위임). 앱·테스트가 동일 DSP 공유.
- `Tests/VocalLogicTests/AudioPipelineIntegrationTests.swift` (macOS 전용 6테스트):
  합성 음성(하모닉 스택 + 700Hz 포먼트 강조 + 비브라토/아치 옵션)을
  AVAudioPCMBuffer→2048/1024 프레임 분할→실측:
  1. 버퍼 디코드 왕복 (에너지·클리핑 게이트)
  2. YIN: voiced ≥90% · 중앙값 220±3Hz
  3. 비브라토 종단: 5.5Hz±70¢ → YIN → 자기상관 → rate 5.5±0.5 · extent 70±15¢
  4. 다이내믹스: 14dB 아치 → 프레임 RMS → hasArch · range 14±3dB
  5. 포먼트: Goertzel 스펙트럼 F1 밴드 피크 ≈ 700±130Hz
  6. 지속: 연속 voiced → longestRun ≈ 3.0±0.15s
- Windows swift test는 `#if canImport(AVFoundation) && os(macOS)` 블록 제외
  (113 테스트 동일 통과 확인). macOS CI typecheck 워크플로의 `swift test`에서
  6테스트 자동 실행.

## 무엇이 실측이고 무엇이 아닌가
- 실측: AVAudioPCMBuffer 디코드 → 프레임 분할 → YIN(vDSP) → RMS → Goertzel →
  전 분석기(피치·비브라토·다이내믹스·포먼트·지속). 마이크 tap의 나머지 전부.
- 미실측: 물리 마이크→inputNode 구간(하드웨어). 이는 실기 기기 + 사람만 가능.
- 웹 대응: 이미 Chromium 가짜 마이크 E2E(tools/audio_e2e.mjs)로 전 경로 실측 중.
