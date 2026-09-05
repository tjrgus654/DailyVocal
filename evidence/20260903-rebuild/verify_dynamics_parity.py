#!/usr/bin/env python3
"""Dynamics (messa di voce) parity gate: web prototype vs Swift app.
Layer A: threshold constants + hasArch predicate + score formula (both sources).
Layer B: run the JS implementation on the Swift unit-test vectors, assert
identical bands (execution parity).
"""
import re, sys, subprocess, json

failures = []
def check(name, ok, detail=""):
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}" + (f" — {detail}" if detail else ""))
    if not ok: failures.append(name)

js_src = open("preview/live.html", encoding="utf-8").read()
sw_src = open("Core/Logic/VocalLogic.swift", encoding="utf-8").read()

print("=== A. Threshold constants ===")
sw_raw = dict(re.findall(r"public static let (minFrames|minRangeDb|minDirectionDb) = ([\d.]+)", sw_src))
# Keep only the dynamics block (struct with hasArch + enum with constants);
# vibrato also declares minFrames, hence the section slice.
dyn_section = sw_src[sw_src.find("public struct DynamicsMeasurement"):]
sw_dyn = dict(re.findall(r"public static let (minFrames|minRangeDb|minDirectionDb) = ([\d.]+)", dyn_section))
pairs = [("minframes", "45"), ("minrangedb", "6.0"), ("mindirectiondb", "3.0")]
js_const = dict(re.findall(r"(MIN_FRAMES|MIN_RANGE_DB|MIN_DIR_DB): ([\d.]+)", js_src))
jmap = {"minframes": "MIN_FRAMES", "minrangedb": "MIN_RANGE_DB", "mindirectiondb": "MIN_DIR_DB"}
for key, expected in pairs:
    sw_v = sw_dyn.get({"minframes": "minFrames", "minrangedb": "minRangeDb", "mindirectiondb": "minDirectionDb"}[key])
    js_v = js_const.get(jmap[key])
    ok = (sw_v is not None and js_v is not None
          and float(sw_v) == float(expected) and float(js_v) == float(expected))
    check(key, ok, f"swift={sw_v} js={js_v} expected={expected}")

print("=== B. hasArch predicate ===")
sw_hb = ("rangeDb >= 6.0 && crescendoDb >= 3.0 && decrescendoDb >= 3.0" in dyn_section
         and "peakPosition >= 0.25 && peakPosition <= 0.75" in dyn_section)
js_hb = ("m.rangeDb >= DYN.MIN_RANGE_DB && m.crescendoDb >= DYN.MIN_DIR_DB" in js_src
         and "m.decrescendoDb >= DYN.MIN_DIR_DB" in js_src
         and "m.peakPosition >= 0.25 && m.peakPosition <= 0.75" in js_src)
check("hasArch gate", sw_hb and js_hb)

print("=== C. Score formula ===")
sw_score = ("var score = 40" in dyn_section
            and "score += 15" in dyn_section
            and "score += 10" in dyn_section
            and "score += 5" in dyn_section
            and "return min(100, score)" in dyn_section)
js_score = ("let s = 40" in js_src
            and "s += 15;" in js_src and "s += 10;" in js_src and "s += 5;" in js_src
            and "return Math.min(100, s)" in js_src)
check("score formula", sw_score and js_score)

print("=== D. Algorithm steps present ===")
steps = [
    ("dB conversion (20*log10)", "20 * log10($0)", "20 * Math.log10(a)"),
    ("centered moving average 5", "movingAverage(dbs, window: 5)", "dynMovingAvg(dbs, 5)"),
    ("head/tail quarters", "smoothed[0..<max(1, n / 4)]", "sm.slice(0, Math.max(1, Math.floor(n / 4)))"),
    ("jitter smoothness", "1 - jitter / (rangeDb / 4)", "1 - jitter / (rangeDb / 4)"),
]
for name, sw_pat, js_pat in steps:
    check(name, sw_pat in sw_src and js_pat in js_src)

print("=== E. Execution parity (JS on Swift test vectors) ----------")
node_code = r"""
const fs = require('fs'), vm = require('vm');
const html = fs.readFileSync('preview/live.html', 'utf8');
const js = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const start = js.indexOf('// ── 다이내믹스 아치');
const endMarker = js.indexOf('return Math.min(100, s);', js.indexOf('function dynamicsScore'));
const block = js.slice(start, js.indexOf('}', endMarker) + 1);
const sandbox = { Math, Date, isFinite, console };
vm.createContext(sandbox);
vm.runInContext(block, sandbox);
const run = vm.runInContext(`(function(){
  // dB envelope -> linear amplitudes, mirroring the Swift tests.
  const env = (frames, fn) => Array.from({length: frames}, (_, i) => Math.pow(10, fn(i / (frames - 1)) / 20));
  const results = {};
  // 1. ideal arch: -20dB floor + 14dB sine arch
  let m = dynamicsAnalyze(env(150, t => -20 + 14 * Math.sin(Math.PI * t)));
  results.ideal = { range: m.rangeDb, cres: m.crescendoDb, decres: m.decrescendoDb,
                    peak: m.peakPosition, smooth: m.smoothness, has: dynHasArch(m), score: dynamicsScore(m) };
  // 2. flat tone
  m = dynamicsAnalyze(new Array(150).fill(0.1));
  results.flat = { range: m.rangeDb, has: dynHasArch(m), score: dynamicsScore(m) };
  // 3. crescendo only (rises then stays loud)
  m = dynamicsAnalyze(env(150, t => -20 + 12 * Math.min(1, t * 2)));
  results.cresc = { range: m.rangeDb, has: dynHasArch(m) };
  // 4. early peak (fast rise by t=0.15, slow fade)
  m = dynamicsAnalyze(env(150, t => t < 0.15 ? -20 + 14 * (t / 0.15) : -6 - 14 * ((t - 0.15) / 0.85)));
  results.early = { has: dynHasArch(m), peak: m.peakPosition };
  // 5. short trace
  m = dynamicsAnalyze(new Array(30).fill(0.1));
  results.short = { none: JSON.stringify(m) === JSON.stringify(dynNone()), score: dynamicsScore(m) };
  // 6. feedback bands
  results.fb_flat = dynamicsFeedback({ rangeDb: 0.2, crescendoDb: 0.1, decrescendoDb: 0.1, peakPosition: 0.5, smoothness: 0, voicedFrames: 150 })[0];
  results.fb_cresc = dynamicsFeedback({ rangeDb: 12, crescendoDb: 11, decrescendoDb: 0.5, peakPosition: 0.5, smoothness: 0.9, voicedFrames: 150 })[0];
  results.fb_arch = dynamicsFeedback({ rangeDb: 14, crescendoDb: 10, decrescendoDb: 10, peakPosition: 0.5, smoothness: 0.9, voicedFrames: 150 });
  // 7. moving average symmetry
  const ma = dynMovingAvg([1,1,1,1,1,100,1,1,1,1,1], 5);
  results.ma = { sym: Math.abs(ma[3] - ma[7]) < 1e-9, centerHigher: ma[4] > ma[2], len: ma.length };
  return results;
})()`, sandbox);
console.log(JSON.stringify(run));
"""
proc = subprocess.run(["node", "--input-type=commonjs", "-e", node_code],
                      capture_output=True, text=True)
if proc.returncode != 0 or not proc.stdout.strip():
    check("node execution", False, (proc.stderr or proc.stdout)[-300:])
else:
    r = json.loads(proc.stdout)
    check("ideal: hasArch", r["ideal"]["has"] is True)
    check("ideal: range ~14", abs(r["ideal"]["range"] - 14) <= 2, f"{r['ideal']['range']:.2f}")
    check("ideal: crescendo >= 6", r["ideal"]["cres"] >= 6, f"{r['ideal']['cres']:.2f}")
    check("ideal: decrescendo >= 6", r["ideal"]["decres"] >= 6, f"{r['ideal']['decres']:.2f}")
    check("ideal: peak ~0.5", abs(r["ideal"]["peak"] - 0.5) <= 0.1, f"{r['ideal']['peak']:.3f}")
    check("ideal: score 100", r["ideal"]["score"] == 100, str(r["ideal"]["score"]))
    check("flat: rejected", r["flat"]["has"] is False)
    check("flat: range < 1", r["flat"]["range"] < 1, f"{r['flat']['range']:.3f}")
    check("flat: score 40", r["flat"]["score"] == 40, str(r["flat"]["score"]))
    check("crescendo-only: rejected", r["cresc"]["has"] is False)
    check("early-peak: rejected", r["early"]["has"] is False)
    check("short: none", r["short"]["none"] is True)
    check("fb: flat range", "레인지가" in r["fb_flat"])
    check("fb: crescendo-only -> decrescendo", "디크레셴도" in r["fb_cresc"])
    check("fb: arch complete + 12dB tip", any("아치 완성" in t for t in r["fb_arch"]) and any("12dB" in t for t in r["fb_arch"]))
    check("ma: symmetric", r["ma"]["sym"] is True and r["ma"]["centerHigher"] is True and r["ma"]["len"] == 11)

print()
if failures:
    print(f"DYNAMICS PARITY FAIL: {len(failures)} axis(s): {', '.join(failures)}")
    sys.exit(1)
print("DYNAMICS PARITY: ALL PASS (constants + formula + 16 execution axes)")
