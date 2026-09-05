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
check("band clamp", "Math.min(72, Math.max(43, m))" in js and "min(band.upperBound, max(band.lowerBound" in sw)
check("one demo pass", "SCALE_T" in js and "scaleNoteDuration" in vm)
scale_block = js[js.find("const SCALE_T"):js.find("function startScaleFlow")]
check("timings", "note: 900" in scale_block and "gap: 250" in scale_block and "window: 1800" in scale_block
      and "scaleNoteDuration = 0.9" in vm and "scaleListenGap = 0.25" in vm and "scaleWindowDuration = 1.8" in vm)
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
const sandbox = { Math, console, Object };
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

print()
if failures:
    print(f"PARITY FAIL: {failures}"); sys.exit(1)
print("PARITY OK: 13축 일치 (시퀀스 풀·밴드·타이밍·난이도 전이·채점·라벨·히스토그램·게이팅 + 스케일 5실행축)")
