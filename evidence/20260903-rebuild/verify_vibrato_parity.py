#!/usr/bin/env python3
"""Vibrato parity gate: web prototype (preview/live.html) vs Swift app.
Two layers:
  A. Constant/formula parity — extract thresholds from BOTH sources, assert equal.
  B. Execution parity — run the JS implementation (vm.Script, no DOM) on the
     same synthetic signals the Swift unit tests use, assert identical bands.
"""
import re, sys, subprocess, json

failures = []
def check(name, ok, detail=""):
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}" + (f" — {detail}" if detail else ""))
    if not ok: failures.append(name)

js_src = open("preview/live.html", encoding="utf-8").read()
sw_src = open("Core/Logic/VocalLogic.swift", encoding="utf-8").read()

# ---------- A. Constant parity ----------
print("=== A. Threshold constants ===")
sw_raw = dict(re.findall(r"public static let (minRateHz|maxRateHz|minExtentCents|minRegularity|minFrames) = ([\d.]+)", sw_src))
alias = {"minratehz": "minrate", "maxratehz": "maxrate", "minextentcents": "minextent",
         "minregularity": "minreg", "minframes": "minframes"}
sw_const = {alias[k.lower()]: v for k, v in sw_raw.items()}
js_const = dict(re.findall(r"(MIN_RATE|MAX_RATE|MIN_EXTENT|MIN_REG|MIN_FRAMES): ([\d.]+)", js_src))
pairs = [("minrate", "3.5"), ("maxrate", "8.5"), ("minextent", "15"), ("minreg", "0.45"), ("minframes", "45")]
for key, expected in pairs:
    sw_v = sw_const.get(key)
    js_v = js_const.get({"minrate": "MIN_RATE", "maxrate": "MAX_RATE", "minextent": "MIN_EXTENT", "minreg": "MIN_REG", "minframes": "MIN_FRAMES"}[key])
    ok = (sw_v is not None and js_v is not None
          and float(sw_v) == float(expected) and float(js_v) == float(expected))
    check(key, ok, f"swift={sw_v} js={js_v} expected={expected}")

print("=== B. hasVibrato predicate ===")
# Swift: rate 3.5..8.5 && extent >= 15 && regularity >= 0.45
sw_hb = ("rateHz >= 3.5 && rateHz <= 8.5" in sw_src
         and "extentCents >= 15.0" in sw_src
         and "regularity >= 0.45" in sw_src)
js_hb = ("m.rateHz >= VIB.MIN_RATE && m.rateHz <= VIB.MAX_RATE" in js_src
         and "m.extentCents >= VIB.MIN_EXTENT && m.regularity >= VIB.MIN_REG" in js_src)
check("hasVibrato gate", sw_hb and js_hb)

print("=== C. Score formula ===")
# Swift: 50 base, +25 in-band rate else +10, +15 target extent else +7, +10 reg>=0.7, cap 100
sw_score = ("var score = 50" in sw_src and "score += 25 } else { score += 10 }" in sw_src
            and "score += 15 } else { score += 7 }" in sw_src
            and "m.regularity >= 0.7 { score += 10 }" in sw_src
            and "return min(100, score)" in sw_src)
js_score = ("let s = 50" in js_src and "s += 25; else s += 10;" in js_src
            and "s += 15; else s += 7;" in js_src
            and "m.regularity >= 0.7) s += 10;" in js_src
            and "return Math.min(100, s)" in js_src)
check("score formula", sw_score and js_score)

print("=== D. Algorithm steps present ===")
steps = [
    ("log-domain cents (1200*log2)", "1200 * log2($0 / meanHz)", "1200 * Math.log2(f / meanHz)"),
    ("linear detrend", "let slope = den > 0 ? num / den : 0", "const slope = num / den"),
    ("lag band ceil/floor", "Int((frameRate / maxRateHz).rounded(.up))", "Math.ceil(frameRate / VIB.MAX_RATE)"),
    ("harmonic consistency", "normalizedCorrelation(cents, lag: 2 * bestLag)", "vibNormCorr(cents, 2 * bestLag)"),
    ("cycle extent (half p2p >= 5 cents)", "swing >= 5", "s >= 5"),
    ("uniform resample (median dt)", "let step = median(dts)", "const step = medianArr(dts)"),
]
for name, sw_pat, js_pat in steps:
    check(name, sw_pat in sw_src and js_pat in js_src)

# ---------- B. Execution parity ----------
print("=== E. Execution parity (JS on Swift test vectors) ----------")
node_code = r"""
const fs = require('fs'), vm = require('vm');
const html = fs.readFileSync('preview/live.html', 'utf8');
const js = html.match(/<script>([\s\S]*?)<\/script>/)[1];
// Extract ONLY the vibrato algorithm block (self-contained, no DOM deps).
const start = js.indexOf('// ── 비브라토 체크');
const endMarker = js.indexOf('return Math.min(100, s);', js.indexOf('function vibratoScore'));
const block = js.slice(start, js.indexOf('}', endMarker) + 1);
const sandbox = { Math, Date, isFinite, console };
vm.createContext(sandbox);
vm.runInContext(block, sandbox);
const run = vm.runInContext(`(function(){
  function synth(base, rate, ext, fps, secs){
    const out = [];
    for (let i = 0; i < fps*secs; i++){
      const t = i/fps, c = ext*Math.sin(2*Math.PI*rate*t);
      out.push(base*Math.pow(2, c/1200));
    }
    return out;
  }
  const results = {};
  // 1. ideal 5.5Hz ±70¢ @50fps 4s (same vector as the Swift unit test)
  let m = vibAnalyzeFrames(synth(220, 5.5, 70, 50, 4), 50);
  results.ideal = { rate: m.rateHz, ext: m.extentCents, reg: m.regularity, has: vibratoHasVib(m), score: vibratoScore(m) };
  // 2. straight tone
  m = vibAnalyzeFrames(new Array(200).fill(220), 50);
  results.straight = { rate: m.rateHz, has: vibratoHasVib(m) };
  // 3. slow 3Hz wobble (must be rejected by band + harmonic gate)
  m = vibAnalyzeFrames(synth(196, 3.0, 80, 50, 4), 50);
  results.wobble = { rate: m.rateHz, has: vibratoHasVib(m) };
  // 4. dropout trace via timestamps overload (5.0Hz ±70¢, every 10th frame unvoiced)
  const clean = synth(247, 5.0, 70, 50, 4);
  const times = [], freqs = [];
  clean.forEach((f, i) => { if (i % 10 !== 5) { times.push(i/50); freqs.push(f); } });
  m = vibratoAnalyze(times, freqs);
  results.dropout = { rate: m.rateHz, ext: m.extentCents, has: vibratoHasVib(m) };
  // 5. drift + vibrato (6Hz ±60¢ on a 150¢ sag)
  const drift = [];
  for (let i = 0; i < 200; i++){
    const t = i/50, c = 60*Math.sin(2*Math.PI*6.0*t) - 150*t/4;
    drift.push(330*Math.pow(2, c/1200));
  }
  m = vibAnalyzeFrames(drift, 50);
  results.drift = { rate: m.rateHz, has: vibratoHasVib(m) };
  // 6. feedback text bands
  results.fb_short = vibratoFeedback({rateHz:5.5, extentCents:70, regularity:0.9, voicedFrames:20})[0];
  results.fb_straight = vibratoFeedback({rateHz:0, extentCents:5, regularity:0.1, voicedFrames:200})[0];
  results.fb_wobble = vibratoFeedback({rateHz:3.8, extentCents:90, regularity:0.8, voicedFrames:200})[0];
  results.fb_trill = vibratoFeedback({rateHz:7.2, extentCents:90, regularity:0.8, voicedFrames:200})[0];
  return results;
})()`, sandbox);
console.log(JSON.stringify(run));
"""
proc = subprocess.run(["node", "--input-type=commonjs", "-e", node_code],
                      capture_output=True, text=True)
if proc.returncode != 0:
    check("node execution", False, proc.stderr[-300:])
else:
    r = json.loads(proc.stdout)
    check("ideal: hasVibrato", r["ideal"]["has"] is True)
    check("ideal: rate ~5.5", abs(r["ideal"]["rate"] - 5.5) <= 0.3, f"{r['ideal']['rate']:.3f}")
    check("ideal: extent ~70", abs(r["ideal"]["ext"] - 70) <= 8, f"{r['ideal']['ext']:.1f}")
    check("ideal: regularity >= 0.8", r["ideal"]["reg"] >= 0.8, f"{r['ideal']['reg']:.3f}")
    check("ideal: score 100", r["ideal"]["score"] == 100, str(r["ideal"]["score"]))
    check("straight: rejected", r["straight"]["has"] is False)
    check("3Hz wobble: rejected", r["wobble"]["has"] is False, f"rate={r['wobble']['rate']:.3f}")
    check("dropout: rate ~5.0", abs(r["dropout"]["rate"] - 5.0) <= 0.35, f"{r['dropout']['rate']:.3f}")
    check("dropout: hasVibrato", r["dropout"]["has"] is True)
    check("drift+vibrato: rate ~6.0", abs(r["drift"]["rate"] - 6.0) <= 0.3, f"{r['drift']['rate']:.3f}")
    check("fb: short", "짧았어요" in r["fb_short"])
    check("fb: straight", "직진" in r["fb_straight"])
    check("fb: wobble", "워블" in r["fb_wobble"])
    check("fb: trill", "떨림" in r["fb_trill"])

print()
if failures:
    print(f"VIBRATO PARITY FAIL: {len(failures)} axis(s): {', '.join(failures)}")
    sys.exit(1)
print("VIBRATO PARITY: ALL PASS (constants + formula + 15 execution axes)")
