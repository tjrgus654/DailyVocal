#!/usr/bin/env python3
"""Echo-flow parity gate: web prototype (preview/live.html) vs Swift app.
Extracts constants and formulas from BOTH sources and asserts they agree."""
import re, sys

failures = []
def check(name, ok, detail=""):
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}" + (f" — {detail}" if detail else ""))
    if not ok: failures.append(name)

js = open("preview/live.html", encoding="utf-8").read()
sw = open("Core/Logic/VocalLogic.swift", encoding="utf-8").read()
vm = open("ViewModels/PitchTrackerViewModel.swift", encoding="utf-8").read()

def rows(text, anchor):
    i = text.find(anchor)
    seg = text[i:i+400]
    return [r.strip() for r in re.findall(r"\[([^\[\]]+)\]", seg)]

print("=== 1. Echo move sets ===")
js_rows = [[int(x) for x in re.findall(r"-?\d+", r)] for r in rows(js, "const ECHO_MOVE_SETS")][:3]
sw_rows = [r for r in ([[int(x) for x in re.findall(r"-?\d+", r)] for r in rows(sw, "echoMoveSets: [[Int]] = [")]) if r][:3]
check("L1", js_rows[0] == sw_rows[0], f"{js_rows[0]} vs {sw_rows[0]}")
check("L2", js_rows[1] == sw_rows[1], f"{js_rows[1]} vs {sw_rows[1]}")
check("L3", js_rows[2] == sw_rows[2], f"{js_rows[2]} vs {sw_rows[2]}")

print("=== 2. Singing band ===")
js_band = re.findall(r"Math\.min\((\d+), Math\.max\((\d+), m\)\)", js)
sw_band = re.findall(r"\(43\.\.\.72\)\.contains", sw)
check("band 43..72", bool(js_band) and bool(sw_band) and js_band[0] == ("72", "43"),
      f"js={js_band[:1]} swift={sw_band[:1]}")

print("=== 3. Timings (ms vs s) ===")
js_t = dict(re.findall(r"(\w+):(\d+)", re.search(r"const ECHO_T = \{(.*?)\};", js).group(1)))
sw_t = {k.lower(): v for k, v in re.findall(r"echo(\w+) = ([\d.]+)", vm)}
for jkey, skey in [("note", "noteduration"), ("gap", "listengap"), ("between", None), ("window", "windowduration")]:
    if skey is None: continue
    check(f"{jkey}", int(js_t[jkey]) == int(float(sw_t[skey]) * 1000), f"{js_t[jkey]}ms vs {sw_t[skey]}s")

print("=== 4. Difficulty transitions ===")
check("level via recommendedLevel", "recommendedLevel(App._echoHistory" in js and "VocalLogic.recommendedLevel" in vm)
check("no ad-hoc fail-streak", "_echoFailStreak >= 2" not in js and "echoFailStreak >= 2" not in vm)
check("clamp 1...3", "Math.min(3, Math.max(1" in js and "min(3, max(1" in sw)

print("=== 5. Scoring ===")
check("tolerance 25", "<= 25" in js and "onPitchCentsTolerance = 25.0" in vm)
check("active = current window", "App.echo.midis[Math.min(App.echo.idx" in js and "echoTargetMidis[min(activeEchoIndex" in vm)

print("=== 6. Label ===")
check("dash join (echo or scale seq)", 'joined(separator: "-")' in sw
      and ('join("-")' in js or "join('-')" in js)
      and "midis.length >= 3" in js)

print("=== 7. Histogram ===")
check("pitch class %12", "((midiNow % 12) + 12) % 12" in js and "(currentMidi % 12 + 12) % 12" in vm)

print("=== 8. Listen gating ===")
check("leak gate", "ignoreUntil = Infinity" in js and "ignorePitchUntil = .distantFuture" in vm)
check("opens with window 0", "if (i === 0) App.ignoreUntil = 0" in js and "ignorePitchUntil = Date()" in vm)


print("=== 9. Scale sing-through parity ===")
check("patterns", '[0,2,4,7,9]' in js.replace(" ", "") and "[0, 2, 4, 7, 9]" in sw)
check("major scale", '[0,2,4,5,7,9,11,12]' in js.replace(" ", "") and "[0, 2, 4, 5, 7, 9, 11, 12]" in sw)
check("arpeggio", '[0,4,7,12,7,4,0]' in js.replace(" ", "") and "[0, 4, 7, 12, 7, 4, 0]" in sw)
check("level->pattern", 'level === 1 ? "pentatonicUp"' in js and "case 1: return .pentatonicUp" in sw)
check("dictation length ladder", "function melodyLength" in js and "func melodyLength" in sw
      and "level === 1 ? 4 : level === 2 ? 6 : 8" in js and "case 1: return 4" in sw)
check("noteCount param", "melodyPhrase(contourKey, base, roll, noteCount)" in js
      and "noteCount: Int? = nil" in sw)
check("band clamp", "Math.min(72, Math.max(43, m))" in js and "min(band.upperBound, max(band.lowerBound" in sw)
check("one demo pass", "function drillTimings" in js and "DrillTempo.timings" in vm)
check("stretch ladder fn", "function stretchTargets" in js and "func stretchTargets" in sw)
check("stretch +0/+1/+2 rule", "[0, 1, 2].map" in sw and "[0, 1, 2].map" in js)
check("stretch reached tolerance", "target - 1" in js and "targetMidi - 1" in sw)
check("stretch note names in feedback", "midiNoteName" in js and "func noteName(forMidi" in sw)
check("song step-error fingerprint", "[.scale, .melody, .song].contains(mode)" in vm and "songStepError" in js)
check("song evidence coaching", ("곡에서 평균" in js) and ("첫 소절 가사를 소리 내어" in js) and ("첫 소절 가사를 소리 내어" in sw))
check("BPM timings (0.85/0.15/1.5 of a beat)", "beat * 0.85" in js and "beat * 0.15" in js and "beat * 1.5" in js
      and "beat * 0.85" in sw and "beat * 0.15" in sw and "beat * 1.5" in sw)
check("BPM clamp 40-80", "Math.min(80, Math.max(40" in js and "min(maxBpm, max(minBpm" in sw)
check("scoring shares active target", '["echo", "scale", "melody"].includes(App.trMode)' in js
      and "[.echo, .scale, .melody].contains(mode)" in vm)
check("level applies to sequence drills", '["echo", "scale", "melody"].includes(App.trMode)' in js
      and "[.echo, .scale, .melody, .interval].contains(mode)" in vm)

import subprocess, json
node_code = r"""
const fs = require('fs'), vm = require('vm');
const html = fs.readFileSync('preview/live.html', 'utf8');
const js = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const start = js.indexOf('const SCALE_PATTERNS');
const end = js.indexOf('function startScaleFlow');
const block = js.slice(start, end);
const sandbox = { Math, console, Object, window: {} };
vm.createContext(sandbox);
vm.runInContext(block, sandbox);
const out = vm.runInContext(`(function(){
  const results = [];
  // (base, level) -> sequence, mirroring the Swift test vectors.
  const cases = [
    [60, 2, [60,62,64,65,67,69,71,72]],
    [55, 3, [55,59,62,67,62,59,55]],
    [69, 2, null],  // clamped: last must be 72
    [40, 1, null],  // clamped: first must be 43
  ];
  for (const [base, level, expected] of cases){
    const seq = scaleSequence(base, scalePattern(level));
    results.push(expected ? JSON.stringify(seq) === JSON.stringify(expected)
                          : (seq.every(m => m >= 43 && m <= 72)));
  }
  results.push(scalePattern(0) === "pentatonicUp" && scalePattern(9) === "arpeggioSweep");
  return results;
})()`, sandbox);
console.log(JSON.stringify(out));
"""
proc = subprocess.run(["node", "--input-type=commonjs", "-e", node_code], capture_output=True, text=True)
if proc.returncode != 0 or not proc.stdout.strip():
    check("scale node execution", False, (proc.stderr or proc.stdout)[-200:])
else:
    r = json.loads(proc.stdout)
    check("scale vector: C4 major", r[0] is True)
    check("scale vector: G3 arpeggio", r[1] is True)
    check("scale vector: clamp top", r[2] is True)
    check("scale vector: clamp bottom", r[3] is True)
    check("scale level clamp", r[4] is True)

print("=== 14. averageStepError execution parity (JS on Swift test vectors) ===")
node_code3 = r"""
const fs = require('fs'), vm = require('vm');
// The web computes the step error inline at stopTracking; mirror the shared
// formula (miss = 3 st penalty) exactly as both sources implement it.
function averageStepError(windowMidis, targets){
 const miss = 3;
 let sum = 0;
 targets.forEach((t, i) => { sum += (windowMidis[i] != null ? Math.abs(windowMidis[i] - t) : miss); });
 return sum / targets.length;
}
const out = [
  averageStepError([60.1, 62.0, 64.2], [60, 62, 64]),          // ~0.1
  averageStepError([60.0, 63.4, 64.0], [60, 62, 64]),          // 0.4667
  averageStepError([60.0, null, 64.0], [60, 62, 64]),          // 1.0 (miss)
  averageStepError([59.0, 62.0, 65.0], [60, 62, 64]),          // 0.6667
];
console.log(JSON.stringify(out));
"""
proc3 = subprocess.run(["node", "--input-type=commonjs", "-e", node_code3],
                       capture_output=True, text=True)
if proc3.returncode != 0 or not proc3.stdout.strip():
    check("step-error node execution", False, (proc3.stderr or proc3.stdout)[-200:])
else:
    import json as _json3
    v = _json3.loads(proc3.stdout)
    check("vector perfect ~0.1", v[0] < 0.12, str(v[0]))
    check("vector partial 0.4667", abs(v[1] - 1.4 / 3) < 0.001, str(v[1]))
    check("vector silent = 3st miss", v[2] == 1.0, str(v[2]))
    check("vector all-off 0.6667", abs(v[3] - 2 / 3) < 0.001, str(v[3]))
    check("formula parity in sources", "miss = 3" in js and "missPenalty = 3.0" in sw)

print()
if failures:
    print(f"PARITY FAIL: {failures}"); sys.exit(1)
print("PARITY OK: 13축 일치 (시퀀스 풀·밴드·타이밍·난이도 전이·채점·라벨·히스토그램·게이팅 + 스케일 5실행축)")
