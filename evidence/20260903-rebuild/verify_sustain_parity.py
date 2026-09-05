#!/usr/bin/env python3
"""Sustain (maximum phonation time) parity gate: web vs Swift.
Constants + execution parity on the Swift unit-test vectors.
"""
import re, sys, subprocess, json

failures = []
def check(name, ok, detail=""):
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}" + (f" — {detail}" if detail else ""))
    if not ok: failures.append(name)

js_src = open("preview/live.html", encoding="utf-8").read()
sw_src = open("Core/Logic/VocalLogic.swift", encoding="utf-8").read()
sw_section = sw_src[sw_src.find("public enum SustainStats"):]

print("=== A. Constants ===")
pairs = [
    ("gap tolerance", r"gapTolerance: Double = ([\d.]+)", r"GAP: ([\d.]+)", "0.25"),
    ("caution", r"cautionSeconds: Double = ([\d.]+)", r"CAUTION: ([\d.]+)", "15.0"),
    ("male norm", r"maleNormSeconds: Double = ([\d.]+)", r"MALE_NORM: ([\d.]+)", "20.8"),
    ("female norm", r"femaleNormSeconds: Double = ([\d.]+)", r"FEMALE_NORM: ([\d.]+)", "17.2"),
]
for name, sw_pat, js_pat, expected in pairs:
    sw_m = re.search(sw_pat, sw_section)
    js_m = re.search(js_pat, js_src)
    ok = (sw_m and js_m and float(sw_m.group(1)) == float(expected) and float(js_m.group(1)) == float(expected))
    check(name, ok, f"swift={sw_m.group(1) if sw_m else None} js={js_m.group(1) if js_m else None}")

print("=== B. Execution parity (JS on Swift test vectors) ----------")
node_code = r"""
const fs = require('fs'), vm = require('vm');
const html = fs.readFileSync('preview/live.html', 'utf8');
const js = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const start = js.indexOf('// ── 최장 지속');
const endMarker = js.indexOf('여유 있게 내쉬는 습관', js.indexOf('function sustainFeedback'));
const block = js.slice(start, js.indexOf('}', endMarker) + 1);
const sandbox = { Math, Date, isFinite, console };
vm.createContext(sandbox);
vm.runInContext(block, sandbox);
const run = vm.runInContext(`(function(){
  const out = {};
  // empty
  out.empty = sustainLongestRun([]);
  // continuous 10s @43fps
  const cont = [];
  for (let t = 0; t <= 10.0; t += 1/43) cont.push(t);
  out.cont = sustainLongestRun(cont);
  // detector drops bridged (1 frame in 50 dropped)
  const drops = [];
  for (let i = 0; i < 430; i++){ if (i % 50 !== 7) drops.push(i / 43); }
  out.drops = sustainLongestRun(drops);
  // multiple runs: 4s, 12s (micro-gaps), 6s
  const multi = [];
  let t = 0;
  for (let s = 0; s < 4; s += 0.025) multi.push(s);
  let i = 0;
  for (let s = 5; s < 17; s += 0.025){ if (i % 60 !== 3) multi.push(s); i++; }
  for (let s = 20; s < 26; s += 0.025) multi.push(s);
  out.multi = sustainLongestRun(multi);
  // 0.4s silence splits (3s run then 2s run @25fps)
  const split = [];
  for (let s = 0; s < 3.0; s += 0.04) split.push(s);
  for (let s = 3.4; s < 5.4; s += 0.04) split.push(s);
  out.split = sustainLongestRun(split);
  // feedback bands
  out.fb_caution = sustainFeedback(12, null);
  out.fb_below = sustainFeedback(18, false);
  out.fb_female = sustainFeedback(18.5, true);
  out.fb_none = sustainFeedback(0, null);
  return out;
})()`, sandbox);
console.log(JSON.stringify(run));
"""
proc = subprocess.run(["node", "--input-type=commonjs", "-e", node_code],
                      capture_output=True, text=True)
if proc.returncode != 0 or not proc.stdout.strip():
    check("node execution", False, (proc.stderr or proc.stdout)[-300:])
else:
    r = json.loads(proc.stdout)
    check("empty -> 0", r["empty"] == 0)
    check("continuous ~10s", abs(r["cont"] - 10.0) <= 0.03, f"{r['cont']:.3f}")
    check("drops bridged ~9.98", abs(r["drops"] - 9.98) <= 0.05, f"{r['drops']:.3f}")
    check("longest of runs ~12", abs(r["multi"] - 12.0) <= 0.06, f"{r['multi']:.3f}")
    check("silence splits ~2.96", abs(r["split"] - 2.96) <= 0.03, f"{r['split']:.3f}")
    check("fb: caution", "15초 미만" in r["fb_caution"])
    check("fb: below male norm", "2.8초" in r["fb_below"])
    check("fb: female above", "평균 이상" in r["fb_female"])
    check("fb: none", "잡히지 않았어요" in r["fb_none"])

print()
if failures:
    print(f"SUSTAIN PARITY FAIL: {len(failures)} axis(s): {', '.join(failures)}")
    sys.exit(1)
print("SUSTAIN PARITY: ALL PASS (constants + 9 execution axes)")
