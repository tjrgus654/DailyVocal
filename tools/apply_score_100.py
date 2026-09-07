#!/usr/bin/env python3
"""Finish the 100-score update the moment a device audio report lands.

Runs the §6.1 report validator first and REFUSES to touch anything unless
it returns COMPLETE. Then applies the exact five changes documented in
docs/PROJECT_SCORE.md '100점 갱신 절차' and commits/pushes them.

Usage:
  python tools/apply_score_100.py evidence/<date>-device-audio/report.md [--dry-run]
    --dry-run: print the replacements, write nothing, no git.
"""

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from validate_device_report import validate  # noqa: E402

REPO = Path(__file__).resolve().parent.parent


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise SystemExit(f"ABORT: '{label}' — expected exactly 1 occurrence, found {text.count(old)}")
    return text.replace(old, new, 1)


def main() -> int:
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return 2
    report_path = Path(args[0])
    dry = "--dry-run" in args
    if not report_path.is_file():
        print(f"ABORT: report file not found: {report_path}")
        return 2
    text = report_path.read_text(encoding="utf-8")

    errors, warnings = validate(text)
    for w in warnings:
        print(f"WARNING: {w}")
    if errors:
        for e in errors:
            print(f"ERROR: {e}")
        print("ABORT: report is not COMPLETE — PROJECT_SCORE stays 89/100")
        return 1
    print("validator: COMPLETE")
    folder = report_path.parent.name  # e.g. 20260908-device-audio

    score = (REPO / "docs" / "PROJECT_SCORE.md").read_text(encoding="utf-8")
    guide = (REPO / "docs" / "MAC_BUILD_GUIDE.md").read_text(encoding="utf-8")

    score = replace_once(
        score, "| **피치 훈련 정확도** | 19/20 |",
        "| **피치 훈련 정확도** | 20/20 |", "score row 19->20")
    score = replace_once(
        score,
        "(§6.1 원탭 자가진단 화면 준비 — 기기 연결 즉시 측정·보고서 복사)",
        "(§6.1 원탭 자가진단 화면 준비 — 기기 연결 즉시 측정·보고서 복사) → "
        f"**실기 §6.1 A–H 판정 완료**({report_path.as_posix()})", "score row evidence")
    score = replace_once(
        score,
        "## 총점: **89 / 100** (초보자 셀프 트레이닝 앱 기준 — 6차 표기 88은 행 합계와 어긋난 기재 오류, 실측 정정)",
        "## 총점: **100 / 100** (실기 확인 완료 — §6.1 A–H 판정, 8차 갱신)", "score total")
    score = replace_once(
        score, "날짜: 2026-09-07(7차 갱신)", "날짜: 2026-09-07(8차 갱신)", "score date")
    score = replace_once(
        score,
        "| 실기 오디오 | 높음→중간 | 마이크 이후 전 경로는 macOS CI 통합 테스트로 실측 입증 — 물리 마이크→inputNode 구간만 실기 기기 확인 필요 |",
        f"| 실기 오디오 | ~~높음~~ 해결 | §6.1 A–H 실기 판정 완료({report_path.as_posix()}) — 물리 마이크 구간까지 입증 |",
        "score gap row")

    guide = replace_once(
        guide, "[ ] **실기 6.1 프로토콜**",
        f"[x] **실기 6.1 프로토콜**(§6.1 A–H 판정 완료 — {report_path.as_posix()})",
        "guide blocker checkbox")

    log = (REPO / "evidence" / "VERIFICATION_LOG.md").read_text(encoding="utf-8")
    last_no = int(re.findall(r"\| (\d+) \|", log)[-1])
    log += (
        f"\n\n## 실기 §6.1 완료 — PROJECT_SCORE 100 (자동 갱신)\n\n"
        f"| # | 검증 행위 | 결과 | 증거/비오 |\n|---|---|---|---|\n"
        f"| {last_no + 1} | 실기 보고서 인제스션({folder}) — 검증자 COMPLETE 확인 후 "
        f"PROJECT_SCORE 8차 갱신(피치 20/20·총점 100)·가이드 블로커 해제 자동 적용 | COMPLETE | {report_path.as_posix()} |\n")

    if dry:
        for name, t in [("PROJECT_SCORE", score), ("MAC_BUILD_GUIDE", guide)]:
            for line in t.splitlines():
                if ("20/20" in line and "피치" in line) or "100 / 100" in line \
                        or "8차" in line or "A–H 판정 완료" in line or "[x] **실기" in line:
                    print(f"[dry] {name}: {line[:110]}")
        print("[dry] VERIFICATION_LOG: entry", last_no + 1, "appended")
        print("DRY RUN OK — no files written")
        return 0

    (REPO / "docs" / "PROJECT_SCORE.md").write_text(score, encoding="utf-8")
    (REPO / "docs" / "MAC_BUILD_GUIDE.md").write_text(guide, encoding="utf-8")
    (REPO / "evidence" / "VERIFICATION_LOG.md").write_text(log, encoding="utf-8")
    print("WROTE: PROJECT_SCORE 100/100, guide checkbox, verification log")

    for cmd in (["git", "add", "-A"],
                ["git", "commit", "-q", "-m",
                 f"feat: 실기 §6.1 A–H 판정 완료 — PROJECT_SCORE 100/100 ({folder})"],
                ["git", "push", "-q"]):
        subprocess.run(cmd, cwd=REPO, check=True)
    print("COMMITTED + PUSHED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
