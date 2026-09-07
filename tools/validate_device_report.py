#!/usr/bin/env python3
"""Validate a pasted on-device audio diagnostics report (MAC_BUILD_GUIDE 6.1).

The report comes from the app's `--audio-diag` screen ("클립보드로 복사").
This script proves the pasted artifact is COMPLETE before anyone updates
PROJECT_SCORE to 100:

  ERROR (exit 1) — not acceptable evidence:
    - not a 하루보컬 diagnostics report (wrong header)
    - any A-H step still 대기 (protocol unfinished)
    - 마이크 권한 not 허용
    - 피치 콜백 0회 (no acoustic energy reached the pipeline)
  WARNING (exit 0) — complete, but the verdict needs a human read:
    - any step judged 실패 (the measurement itself worked)

Usage:
  python tools/validate_device_report.py report.txt [--write]
    --write: copy the report into evidence/<YYYYMMDD>-device-audio/report.md
"""

import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

STEP_RE = re.compile(r"^([A-H]) .+: (통과|실패|대기)$")
HEADER_RE = re.compile(r"^하루보컬 실기 오디오 진단 — (\d{4}-\d{2}-\d{2}) \d{2}:\d{2}$")


def validate(text: str) -> tuple[list[str], list[str]]:
    """Return (errors, warnings) for a report body."""
    errors: list[str] = []
    warnings: list[str] = []
    lines = [line.rstrip("\n") for line in text.strip().splitlines()]

    if not lines or not HEADER_RE.match(lines[0]):
        errors.append("헤더 불일치: '하루보컬 실기 오디오 진단 — YYYY-MM-DD HH:mm' 가 아님")
        return errors, warnings

    permission = next((l for l in lines if l.startswith("마이크 권한:")), "")
    if "허용" not in permission:
        errors.append(f"마이크 권한이 허용 아님: {permission or '(줄 없음)'}")

    if not any(l.startswith("입력 ") and "kHz" in l for l in lines):
        errors.append("입력 포맷 줄 없음 (kHz)")
    if not any(l.startswith("피치 콜백") for l in lines):
        errors.append("피치 콜백 줄 없음")
    if "피치 콜백 0회" in text:
        errors.append("피치 콜백 0회 — 실제 음향 에너지가 파이프라인에 도달하지 않음")

    steps = {}
    for line in lines:
        m = STEP_RE.match(line)
        if m:
            steps[m.group(1)] = m.group(2)
    expected = list("ABCDEFGH")
    if sorted(steps) != expected:
        errors.append(f"단계 라인 불완전: 있음={sorted(steps)} 기대={expected}")
    else:
        for code in expected:
            if steps[code] == "대기":
                errors.append(f"단계 {code} 아직 대기 — 프로토콜 미완료")
            elif steps[code] == "실패":
                warnings.append(f"단계 {code} 실패 판정 — 측정 자체는 완료, 내용 확인 필요")

    summary = next((l for l in lines if l.startswith("요약:")), "")
    if not summary:
        errors.append("요약 줄 없음")
    else:
        m = re.match(r"^요약: 통과 (\d+)/8 · 실패 (\d+) · 대기 (\d+)$", summary)
        if not m:
            errors.append(f"요약 형식 불일치: {summary}")
        else:
            got = (sum(1 for v in steps.values() if v == "통과"),
                   sum(1 for v in steps.values() if v == "실패"),
                   sum(1 for v in steps.values() if v == "대기"))
            if got != (int(m.group(1)), int(m.group(2)), int(m.group(3))):
                errors.append(f"요약 수치가 단계 판정과 불일치: 요약={summary} 실측={got}")
    return errors, warnings


def main() -> int:
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return 2
    source = Path(args[0])
    write = "--write" in args
    text = source.read_text(encoding="utf-8")
    errors, warnings = validate(text)

    for warning in warnings:
        print(f"WARNING: {warning}")
    for error in errors:
        print(f"ERROR: {error}")
    if errors:
        print("RESULT: INCOMPLETE — PROJECT_SCORE 갱신 근거로 부적격")
        return 1
    print("RESULT: COMPLETE — 8단계 판정 완료, 물리 마이크 실측 근거 성립 (PROJECT_SCORE 100 갱신 가능)")
    if write:
        stamp = HEADER_RE.match(text.strip().splitlines()[0]).group(1).replace("-", "")
        dest = Path("evidence") / f"{stamp}-device-audio"
        dest.mkdir(parents=True, exist_ok=True)
        target = dest / "report.md"
        shutil.copyfile(source, target)
        print(f"WROTE: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
