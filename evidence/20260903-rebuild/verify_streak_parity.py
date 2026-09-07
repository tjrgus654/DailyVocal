#!/usr/bin/env python3
"""Streak / rest-flow parity gate: web prototype vs Swift app.

Extracts rules from preview/live.html and Core/Logic/VocalLogic.swift +
ViewModels/DailyRoutineViewModel.swift and asserts semantic agreement.
Run: python evidence/20260903-rebuild/verify_streak_parity.py
"""
import re
import subprocess
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



print("=== 6. Vowel game parity ===")
check("formant table", 'FORMANTS = {"아":[730,1090,2440]' in js and 'case .a: return (730, 1090, 2440)' in logic)
check("5 vowels", "[730,1090,2440]" in js and "[530,1840,2480]" in js and "[270,2290,3010]" in js)
check("direction feedback", 'function vowelDirectionFeedback' in js and 'func vowelDirectionFeedback' in logic)

print("=== 7. Interval game parity ===")
check("interval enum", '"같은음":0' in js and 'case unison = "같은음"' in logic)
check("scoring", 'd === 0 ? 100 : d === 1 ? 40 : 0' in js and 'if diff == 0 { return 100 }' in logic)
check("feedback", '너무 넓게' in js and '너무 넓게' in logic)

print("=== 8. Ear training parity ===")
check("3 choices", '"높아요"' in js and 'case higher = "높아요"' in logic)
check("level rule", 'cs >= 5 && level < 3' in js and 'correctStreak >= 5 && currentLevel < 3' in logic)
print("=== 9. Personalized difficulty parity ===")
check("recommendedLevel fn", "function recommendedLevel" in js and "func recommendedLevel" in logic)
check("80% promote rule", "avg >= 80" in js and ">= 80" in logic)
check("2x50% demote", "every(x => x < 50)" in js and "allSatisfy({ $0 < 50 })" in logic)
check("recommendNextGame", "function recommendNextGame" in js and "func recommendNextGame" in logic)
check("variety bias 15", "<= 15" in js and "<= 15" in logic)
# Technique modes are first-class recommendation inputs since 2026-09-06.
check("5 game types", '"비브라토 체크"' in js and 'return "비브라토 체크"' in logic)
check("dynamics label", '"다이내믹스 아치"' in js and 'return "다이내믹스 아치"' in logic)
check("game type cases", "case vibrato" in logic and "case dynamics" in logic)
check("latestAccuracies", "function latestAccuracies" in js and "func latestAccuracies" in logic)
check("11-entry score table", '["stretch", stretchAcc ?? 50]' in js and '(.stretch, stretchAccuracy ?? 50)' in logic)
check("stretch game label", 'stretch: "고음 확장"' in js and 'return "고음 확장"' in logic)
check("passaggio game label", 'passaggio: "파사지오 왕복"' in js and 'return "파사지오 왕복"' in logic)
check("song game label", 'song: "민요 따라부르기"' in js and 'return "민요 따라부르기"' in logic)
check("harmony game label", 'harmony: "화음 부르기"' in js and 'return "화음 부르기"' in logic)
check("scale game label", 'scale: "스케일 시퀀스"' in js and 'return "스케일 시퀀스"' in logic)

print("=== 9b. recommendNextGame execution parity (JS on Swift test vectors) ===")
node_code = r"""
const fs = require('fs'), vm = require('vm');
const html = fs.readFileSync('preview/live.html', 'utf8');
const js = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const start = js.indexOf('const GAME_LABELS');
const endMarker = js.indexOf('nextGameRecommendation(){');
const endReason = js.indexOf('return { game, name: GAME_NAMES[game], reason };', endMarker);
const block = js.slice(start, js.indexOf('\n}', endReason) + 2);
const sandbox = { Math, Date, isFinite, console, Object, window: {} };
vm.createContext(sandbox);
vm.runInContext(block, sandbox);
const out = vm.runInContext(`(function(){
  const cases = [
    // [vowel, interval, ear, lastGame, vibrato, dynamics, scale, melody, harmony, song, passaggio, stretch, expected]
    [40, 80, 60, null, null, null, null, null, null, null, null, null, "vowel"],
    [90, 40, 65, "vowel", null, null, null, null, null, null, null, null, "interval"],
    [90, 85, 60, "interval", 55, 58, null, 62, 57, 54, 52, 51, "scale"],
    [80, 90, 85, null, 40, null, null, null, null, null, null, null, "vibrato"],
    [80, 90, 85, null, 70, 35, null, null, null, null, null, null, "dynamics"],
    [80, 90, 85, "vibrato", 40, 50, 55, 60, 66, 70, 72, 74, "dynamics"],
    [90, 75, 65, "ear", 72, 68, 70, 78, 82, 85, 88, 90, "dynamics"],
    [80, 90, 85, null, 75, 70, 40, null, 62, 65, 68, 71, "scale"],
    [80, 90, 85, null, 75, 70, 65, 33, 60, 58, 62, 65, "melody"],
    [80, 90, 85, null, 75, 70, 65, 60, 33, 58, 62, 65, "harmony"],
    [80, 90, 85, null, 75, 70, 65, 60, 58, 33, 62, 65, "song"],
    [80, 90, 85, null, 75, 70, 65, 60, 58, 62, 33, 65, "passaggio"],
    [80, 90, 85, null, 75, 70, 65, 60, 58, 62, 55, 33, "stretch"],
  ];
  const results = cases.map(([v, i, e, last, vb, dy, sc, me, ha, so, pa, st]) =>
    recommendNextGame(v, i, e, last, vb, dy, sc, me, ha, so, pa, st));
  const latest = latestAccuracies([
    {label: "모음 게임", accuracy: 60}, {label: "E4", accuracy: 90},
    {label: "비브라토 체크", accuracy: 40}, {label: "모음 게임", accuracy: 75},
    {label: "다이내믹스 아치", accuracy: 55}, {label: "스케일 시퀀스", accuracy: 68},
    {label: "멜로디 프레이즈", accuracy: 71}, {label: "화음 부르기", accuracy: 66},
    {label: "민요 따라부르기", accuracy: 69}, {label: "파사지오 왕복", accuracy: 61},
    {label: "고음 확장", accuracy: 59},
  ]);
  return { cases, results, latest };
})()`, sandbox);
console.log(JSON.stringify(out));
"""
proc = subprocess.run(["node", "--input-type=commonjs", "-e", node_code],
                      capture_output=True, text=True)
if proc.returncode != 0 or not proc.stdout.strip():
    check("node execution", False, (proc.stderr or proc.stdout)[-300:])
else:
    import json
    r = json.loads(proc.stdout)
    for idx, (case, got) in enumerate(zip(r["cases"], r["results"])):
        expected = case[12]
        check(f"vector {idx} -> {expected}", got == expected, f"got {got}")
    check("latest: vowel most-recent", r["latest"].get("vowel") == 75)
    check("latest: vibrato", r["latest"].get("vibrato") == 40)
    check("latest: dynamics", r["latest"].get("dynamics") == 55)
    check("latest: interval nil", r["latest"].get("interval") is None)

print("=== 10. dailySummaryLine execution parity (JS on Swift vectors) ===")
node_code2 = r"""
const fs = require('fs'), vm = require('vm');
const html = fs.readFileSync('preview/live.html', 'utf8');
const js = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const anchor = js.indexOf('function dailySummaryLine');
const nl = String.fromCharCode(10);
const end = js.indexOf(nl + '}', js.indexOf('bestScore != null', anchor));
const block = js.slice(anchor, end + 2);
const sandbox = { Math, Date, isFinite, console, Object, window: {} };
vm.createContext(sandbox);
vm.runInContext(block, sandbox);
const out = vm.runInContext(`(function(){
  const cases = [
    // [routineSessions, techniqueMeasures, bestScore, expected]
    [0, 3, 90, null],
    [1, 3, 90, null],
    [2, 3, 84, "오늘의 마무리: 루틴 2회 · 테크닉 측정 3회 · 최고 84점"],
    [2, 0, 70, "오늘의 마무리: 루틴 2회 · 최고 70점"],
    [3, 1, null, "오늘의 마무리: 루틴 3회 · 테크닉 측정 1회"],
  ];
  return cases.map(([rs, tm, bs]) => dailySummaryLine(rs, tm, bs));
})()`, sandbox);
console.log(JSON.stringify(out));
"""
proc2 = subprocess.run(["node", "--input-type=commonjs", "-e", node_code2],
                       capture_output=True, text=True)
if proc2.returncode != 0 or not proc2.stdout.strip():
    check("daily summary node execution", False, (proc2.stderr or proc2.stdout)[-200:])
else:
    import json as _json
    vals = _json.loads(proc2.stdout)
    check("summary hidden before 2nd", vals[0] is None and vals[1] is None)
    check("summary full form", vals[2] == "오늘의 마무리: 루틴 2회 · 테크닉 측정 3회 · 최고 84점")
    check("summary omits empty measures", vals[3] == "오늘의 마무리: 루틴 2회 · 최고 70점")
    check("summary omits missing score", vals[4] == "오늘의 마무리: 루틴 3회 · 테크닉 측정 1회")

print("=== 11. recommendedTip execution parity (JS on Swift vectors) ===")
node_code3 = r"""
const fs = require('fs'), vm = require('vm');
const html = fs.readFileSync('preview/live.html', 'utf8');
const js = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const anchor2 = js.indexOf('function recommendedTip');
const tail = js.indexOf('bestSustain > 0 && bestSustain < 15', anchor2);
const nl = String.fromCharCode(10);
// The function closes with the final fallback return; find its closing brace.
const nextFn = js.indexOf('function dailySummaryLine', anchor2);
const seg = js.slice(anchor2, js.lastIndexOf('}', nextFn) + 1);
const sandbox3 = { Math, Date, isFinite, console, Object, window: {} };
vm.createContext(sandbox3);
vm.runInContext(seg, sandbox3);
const out = vm.runInContext(`(function(){
  const cases = [
    [3.8, 4.0, 9, true],    // breath wall -> tip 60
    [7.2, 4.0, 16, false],  // vibrato out of band -> 55
    [5.5, 4.2, 16, false],  // dynamics short -> 56
    [5.5, 8, 16, true],     // healthy male -> 58
    [0, 0, 0, false],       // no data -> 57
  ];
  return cases.map(([v, d, s, m]) => recommendedTip(v, d, s, m).id);
})()`, sandbox3);
console.log(JSON.stringify(out));
"""
proc3 = subprocess.run(["node", "--input-type=commonjs", "-e", node_code3],
                       capture_output=True, text=True)
if proc3.returncode != 0 or not proc3.stdout.strip():
    check("tip recommender node execution", False, (proc3.stderr or proc3.stdout)[-200:])
else:
    import json as _json3
    ids = _json3.loads(proc3.stdout)
    check("tip breath wall -> 60", ids[0] == 60)
    check("tip vibrato -> 55", ids[1] == 55)
    check("tip dynamics -> 56", ids[2] == 56)
    check("tip male fallback -> 58", ids[3] == 58)
    check("tip no-data fallback -> 57", ids[4] == 57)
    check("latest: scale 68", r["latest"].get("scale") == 68)
    check("latest: melody 71", r["latest"].get("melody") == 71)
    check("latest: harmony 66", r["latest"].get("harmony") == 66)
    check("latest: song 69", r["latest"].get("song") == 69)
    check("latest: passaggio 61", r["latest"].get("passaggio") == 61)
    check("latest: stretch 59", r["latest"].get("stretch") == 59)

check("daily summary fn", "function dailySummaryLine" in js and "func dailySummaryLine" in logic)
check("daily summary 2-session gate", "routineSessions < 2" in js and "routineSessions >= 2" in logic)
check("tip recommender fn", "function recommendedTip" in js and "func recommendedTip" in logic)
# Session alert deep link: app exposes a dedicated alert button routing through
# AppRouter.pendingTipID; web makes the toast tip line clickable.
tracker = open("Views/PitchTracker/PitchTrackerView.swift", encoding="utf-8").read()
check("session alert tip button", 'Button("📖 팁 읽기")' in tracker and "pendingTipID = tipID" in tracker)
check("toast tip clickable", 'onclick="openRecommendedTip(' in js and "function openRecommendedTip" in js)
check("tip weakness-first gates", "bestSustain > 0 && bestSustain < 15" in js and "bestSustainSeconds > 0 && bestSustainSeconds < 15" in logic)
check("gap pools", '[0,4,5,7,-4,-5,-7]' in js and '[0, 4, 5, 7, -4, -5, -7]' in logic)

print()
if failures:
    print(f"PARITY FAIL: {failures}")
    sys.exit(1)
print("PARITY OK: 스트릭/쉬는 날 플로우가 5축(4AM 롤오버·프리즈 규칙·주간 창·쉬는 날 전이·기록 가드)에서 일치합니다.")
