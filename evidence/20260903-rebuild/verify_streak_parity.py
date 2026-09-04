#!/usr/bin/env python3
"""Streak / rest-flow parity gate: web prototype vs Swift app.

Extracts rules from preview/live.html and Core/Logic/VocalLogic.swift +
ViewModels/DailyRoutineViewModel.swift and asserts semantic agreement.
Run: python evidence/20260903-rebuild/verify_streak_parity.py
"""
import re
import sys

failures = []


def check(name, ok, detail=""):
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}" + (f" — {detail}" if detail else ""))
    if not ok:
        failures.append(name)


js = open("preview/live.html", encoding="utf-8").read()
logic = open("Core/Logic/VocalLogic.swift", encoding="utf-8").read()
presets = open("Core/Logic/RoutineStep.swift", encoding="utf-8").read()
pvm = open("ViewModels/ProgressViewModel.swift", encoding="utf-8").read()
rvm = open("ViewModels/DailyRoutineViewModel.swift", encoding="utf-8").read()
rvm = open("ViewModels/DailyRoutineViewModel.swift", encoding="utf-8").read()

print("=== 1. 4 AM rollover ===")
check("shift -4h", "date.getTime() - 4*3600*1000" in js and "addingTimeInterval(-4 * 3600)" in logic)
check("cursor anchors at rollover day", "Date.now() - 4*3600*1000" in js and "now.addingTimeInterval(-4 * 3600)" in logic)
# Exactly ONE -4h shift per side: JS practiceDayKey shifts & rawKey formats
# plainly; Swift practiceDayKey shifts & formats. No second shift anywhere.
js_body = js.split("function practiceDayKey")[1][:200]
sw_body = logic.split("public static func practiceDayKey")[1][:300]
check("exactly one -4h shift per side",
      "4*3600*1000" in js_body and "-4 * 3600" in sw_body
      and js_body.count("4*3600*1000") == 1 and sw_body.count("-4 * 3600") == 1)

print("=== 2. Freeze consumption rule ===")
check("bridge only with token", "tokens > 0" in js and "tokens > 0" in logic)
check("bridge requires prev day practiced/frozen",
      "(days.has(key(prev)) || frozen.has(key(prev)))" in js
      and "practiceDays.contains(dayFormatter.string(from: previousDay))" in logic
      and "frozenDays.contains(dayFormatter.string(from: previousDay))" in logic)
check("two consecutive gaps end the walk (else break)", "} else break;" in js.replace("else if", "elseif").replace("} else\n break;", "} else break;") or "else break" in js and "} else {\n                break" in logic)
check("iteration cap 366", "i < 366" in js and "iterations < 366" in logic)
check("usedFrozenCount includes fresh consumption", "frozenUsed + (consumed ? 1 : 0)" in js and "usedFrozenCount + consumedDays.count" in logic)
# P2-4: consumption moved out of the read path on BOTH sides.
check("read path is pure (calcStreak does not mutate store)",
      "Store.data.freezeTokens = Math.max(0, Store.data.freezeTokens - 1)" not in js.split("function weeklyDays")[0].split("function settleFreezeTokens")[0],
      "JS calcStreak must not spend tokens")
check("single write-point at session completion",
      "settleFreezeTokens();" in js and "settleFreezeTokensIfNeeded(profile: profile, context: context)" in rvm)

print("=== 3. Weekly window anchored to Monday ===")
check("Monday anchor", "(ws.getDay() + 6) % 7" in js and "firstWeekday = 2" in logic)
check("7-day window", "i < 7" in js and "(0..<7)" in pvm)

print("=== 4. Rest-day flow ===")
check("sore forces rest on start", '=== 2 && App.mode !== "rest"' in js and "vocalCondition == .sore && mode != .rest" in rvm)
check("rest routine is its own preset", "STEPS_REST" in js and "RoutinePresets.restRoutine()" in rvm)
check("whisper warning present", "속삭" in js and "속삭" in presets)
check("recovery leaves rest mode", 'v !== 2 && App.mode === "rest"' in js and "vocalCondition != .sore" in rvm and "mode == .rest" in rvm)

print("=== 5. Session recording guards ===")
check("skip-through rejected", "totalElapsed < 60 || App.completed.size === 0" in js
      and "elapsed >= 60, !steps.isEmpty" in rvm)
check("quick/rest not full completion", 'full = App.completed.size === App.steps.length' in js
      and "completedStepIndices.count == routineSteps.count" in rvm)

print()
if failures:
    print(f"PARITY FAIL: {failures}")
    sys.exit(1)
print("PARITY OK: 스트릭/쉬는 날 플로우가 5축(4AM 롤오버·프리즈 규칙·주간 창·쉬는 날 전이·기록 가드)에서 일치합니다.")
