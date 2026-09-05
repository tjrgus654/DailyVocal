// Vibrato + dynamics UI E2E: drives the web prototype in headless Edge, walks
// both sustain-check flows (captions, synthetic analysis, result cards) using
// the same test-hook path as audio_e2e.mjs, and checks for console errors.
// Usage: node tools/vibrato_ui_e2e.mjs (serve :8766 first).
import { chromium } from "playwright-core";

const URL = "http://127.0.0.1:8766/preview/live.html";

const browser = await chromium.launch({ channel: "msedge", headless: true });
const context = await browser.newContext();
const page = await context.newPage();
const consoleErrors = [];
const notFound = [];
page.on("pageerror", (e) => consoleErrors.push("pageerror: " + e.message));
page.on("response", (r) => { if (r.status() === 404) notFound.push(r.url()); });
page.on("console", (m) => { if (m.type() === "error") consoleErrors.push("console: " + m.text()); });

await page.goto(URL);
await page.waitForLoadState("domcontentloaded");
await page.waitForTimeout(500);
await page.evaluate("finishOnboarding()");
await page.evaluate('go("tracker")');

const checks = [];
const ok = (name, cond, detail = "") => {
  checks.push(`${cond ? "PASS" : "FAIL"} ${name}${detail ? " — " + detail : ""}`);
  return cond;
};

// 1. Mode chip exists and switches.
const chipCount = await page.locator('.chip[onclick^="setTrMode"]').count();
ok("mode chips rendered", chipCount === 10, `count=${chipCount}`);
await page.click('span.chip[onclick="setTrMode(\'vibrato\')"]');
ok("vibrato mode selected", await page.evaluate("App.trMode") === "vibrato");
await page.waitForTimeout(200);
// Idle caption must NOT claim "측정 완료" before anything ran.
ok("idle caption", (await page.locator("text=시작하면 기준음이 울립니다").count()) >= 1);
ok("idle caption is not '측정 완료'", (await page.evaluate("VIBRATO_CHECK.phase")) === "idle");
// Guide caption (rendered via the real state machine path).
await page.evaluate('(() => { VIBRATO_CHECK.phase = "guide"; render(); })()');
ok("guide caption shown", (await page.locator("text=기준음이 먼저 울립니다").count()) >= 1);
await page.evaluate('(() => { VIBRATO_CHECK.phase = "recording"; render(); })()');
ok("recording caption shown", (await page.locator("text=지금 길게").count()) >= 1);
await page.evaluate('(() => { VIBRATO_CHECK.phase = "idle"; render(); })()');

// 2. Start the flow (mic not granted — the guide phase must still render;
//    then we short-circuit to the analysis with a synthetic trace).
await page.click("text=실시간 피치 측정 시작").catch(() => {});
// Mic permission prompt in headless denies; accept either path.
await page.waitForTimeout(800);
const phaseAfterStart = await page.evaluate("VIBRATO_CHECK.phase");
ok("phase advanced (guide/recording/idle-after-deny)", phaseAfterStart !== "done", `phase=${phaseAfterStart}`);

// 3. Synthetic end-to-end analysis through the REAL page functions.
const analysis = await page.evaluate(`(() => {
  const fps = 50, secs = 4, base = 220;
  const times = [], freqs = [];
  for (let i = 0; i < fps * secs; i++){
    if (i % 10 === 5) continue; // unvoiced dropouts
    const t = i / fps, c = 70 * Math.sin(2 * Math.PI * 5.5 * t);
    times.push(t); freqs.push(base * Math.pow(2, c / 1200));
  }
  const m = vibratoAnalyze(times, freqs);
  return { rate: m.rateHz, ext: m.extentCents, reg: m.regularity,
           has: vibratoHasVib(m), score: vibratoScore(m), tips: vibratoFeedback(m) };
})()`);
ok("analysis rate ~5.5", Math.abs(analysis.rate - 5.5) <= 0.3, analysis.rate.toFixed(3));
ok("analysis extent ~70", Math.abs(analysis.ext - 70) <= 8, analysis.ext.toFixed(1));
ok("analysis hasVibrato", analysis.has === true);
ok("analysis score 100", analysis.score === 100, String(analysis.score));
ok("coaching tip present", analysis.tips.length >= 1 && analysis.tips[0].includes("Hz"));

// 4. Result card renders from state.
await page.evaluate(`(() => {
  VIBRATO_CHECK.phase = "done";
  VIBRATO_CHECK.result = { rateHz: 5.4, extentCents: 82, regularity: 0.91, voicedFrames: 180 };
  VIBRATO_CHECK.tips = vibratoFeedback(VIBRATO_CHECK.result);
  render();
})()`);
await page.waitForTimeout(200);
ok("result card title", (await page.locator("text=비브라토 분석").count()) >= 1);
ok("badge 감지", (await page.locator("text=비브라토 감지").count()) >= 1);
ok("metric 규칙성", (await page.locator("text=주기 일관성").count()) >= 1);
ok("coaching line rendered", (await page.locator("text=이상적인 비브라토 범위").count()) >= 1);

// 5. Dynamics (messa di voce) flow: chips, captions, analysis, result card.
await page.click('span.chip[onclick="setTrMode(\'dynamics\')"]');
ok("dynamics mode selected", await page.evaluate("App.trMode") === "dynamics");
await page.waitForTimeout(200);
ok("dynamics idle caption", (await page.locator("text=메사 디 보체").count()) >= 1);
await page.evaluate('(() => { DYNAMICS_CHECK.phase = "guide"; render(); })()');
ok("dynamics guide caption", (await page.locator("text=여리게 → 크게 → 여리게").count()) >= 1);
await page.evaluate('(() => { DYNAMICS_CHECK.phase = "recording"; render(); })()');
ok("dynamics recording caption", (await page.locator("text=숨을 아껴가며").count()) >= 1);
await page.evaluate('(() => { DYNAMICS_CHECK.phase = "idle"; render(); })()');
const dyn = await page.evaluate(`(() => {
  const amps = Array.from({length: 150}, (_, i) => {
    const t = i / 149;
    return Math.pow(10, (-20 + 14 * Math.sin(Math.PI * t)) / 20);
  });
  const m = dynamicsAnalyze(amps);
  return { range: m.rangeDb, has: dynHasArch(m), score: dynamicsScore(m),
           tips: dynamicsFeedback(m) };
})()`);
ok("dynamics analysis range ~14", Math.abs(dyn.range - 14) <= 2, dyn.range.toFixed(2));
ok("dynamics hasArch", dyn.has === true);
ok("dynamics score 100", dyn.score === 100, String(dyn.score));
await page.evaluate(`(() => {
  DYNAMICS_CHECK.phase = "done";
  DYNAMICS_CHECK.result = { rangeDb: 13.2, crescendoDb: 9.4, decrescendoDb: 9.1, peakPosition: 0.5, smoothness: 0.9, voicedFrames: 160 };
  DYNAMICS_CHECK.tips = dynamicsFeedback(DYNAMICS_CHECK.result);
  render();
})()`);
await page.waitForTimeout(200);
ok("dynamics card title", (await page.locator("text=다이내믹스 아치").count()) >= 1);
ok("dynamics badge 아치", (await page.locator("text=아치 완성").count()) >= 1);
ok("dynamics coaching line", (await page.locator("text=한 호흡에 잡혔습니다").count()) >= 1);

// 6. Growth dashboard: technique snapshot persists through Store.
await page.evaluate(`(() => {
  Store.data.lastVibratoRateHz = 5.4;
  Store.data.lastVibratoExtentCents = 82;
  Store.data.lastDynamicsRangeDb = 13.2;
  Store.save();
  go("progress");
})()`);
await page.waitForTimeout(200);
ok("growth snapshot card", (await page.locator("text=테크닉 스냅샷").count()) >= 1);
ok("growth snapshot vibrato value", (await page.locator("text=5.4Hz").count()) >= 1);
ok("growth snapshot dynamics value", (await page.locator("text=13.2dB").count()) >= 1);

// 7. Sustain (MPT): single-note run measurement + growth line.
const sus = await page.evaluate(`(() => {
  const times = [];
  for (let s = 0; s < 4; s += 0.04) times.push(s);
  for (let s = 4.4; s < 16.5; s += 0.04) times.push(s);
  return { run: sustainLongestRun(times), tip: sustainFeedback(16.4, null) };
})()`);
ok("sustain run ~12.1", Math.abs(sus.run - 12.06) <= 0.05, sus.run.toFixed(3));
ok("sustain tip below norm", sus.tip.includes("남았습니다"));
await page.evaluate(`(() => {
  Store.data.bestSustainSeconds = 16.4;
  Store.save();
  render();
})()`);
await page.waitForTimeout(200);
ok("growth sustain line", (await page.locator("text=16.4초 (한 호흡 최대 발성)").count()) >= 1);

// 8. Next-game recommendation card (records-driven, technique-aware).
await page.evaluate(`(() => {
  // Isolate from earlier runs: localStorage keeps fingerprints/records
  // across navigations, which would skew the recommendation vectors.
  Store.data.pitchRecords = [
    { t: 1, target: "모음 게임", acc: 78, lo: 0, hi: 0, dur: 60 },
    { t: 2, target: "음정 게임", acc: 82, lo: 0, hi: 0, dur: 30 },
    { t: 3, target: "귀훈련", acc: 85, lo: 0, hi: 0, dur: 30 },
    { t: 4, target: "스케일 시퀀스", acc: 72, lo: 0, hi: 0, dur: 35 },
    { t: 5, target: "다이내믹스 아치", acc: 62, lo: 0, hi: 0, dur: 40 },
  ];
  Store.data.lastVibratoRateHz = 0;
  Store.data.lastVibratoExtentCents = 0;
  Store.data.lastDynamicsRangeDb = 0;
  Store.save();
  render();
})()`);
await page.waitForTimeout(200);
await page.evaluate('go("progress")');
await page.waitForTimeout(200);
ok("recommendation card title", (await page.locator("text=오늘의 추천 훈련").count()) >= 1);
// vowel 78 / interval 82 / ear 85 / scale 72 / dynamics 62 measured; vibrato
// unmeasured (50) is the unique weakest -> vibrato, with the "시도하지 않은" reason.
const recGame = await page.evaluate("nextGameRecommendation().game");
ok("recommendation game is vibrato", recGame === "vibrato", recGame);
ok("recommendation reason is unmeasured", (await page.evaluate("nextGameRecommendation().reason")).includes("시도하지 않은"));
// With vibrato measured too, the weakest measured skill (dynamics 62) wins.
const recWeakest = await page.evaluate(`(() => {
  Store.data.pitchRecords.push({ t: 6, target: "비브라토 체크", acc: 74, lo: 0, hi: 0, dur: 45 });
  Store.save();
  render();
  return nextGameRecommendation();
})()`);
ok("recommendation weakest measured", recWeakest.game === "dynamics" && recWeakest.reason.includes("62점"), recWeakest.game);

// 9c. Measurement-based evidence: a weak vibrato score + a 3.8Hz stored
// fingerprint turns the reason into the wobble line.
const evidence = await page.evaluate(`(() => {
  Store.data.pitchRecords.push({ t: 7, target: "비브라토 체크", acc: 30, lo: 0, hi: 0, dur: 45 });
  Store.data.lastVibratoRateHz = 3.8;
  Store.data.lastVibratoExtentCents = 80;
  Store.save();
  render();
  return nextGameRecommendation();
})()`);
ok("evidence picks weakest vibrato", evidence.game === "vibrato", evidence.game);
ok("evidence cites measurement", evidence.reason.includes("3.8Hz") && evidence.reason.includes("워블"), evidence.reason);

// 9b. Recommendation deep link: tapping the card jumps to the tracker tab
// with the recommended mode pre-selected.
await page.locator('[onclick^="startRecommended"]').first().click();
await page.waitForTimeout(200);
ok("deep link switches to tracker tab", (await page.evaluate("App.tab")) === "tracker");
ok("deep link selects recommended mode", (await page.evaluate("App.trMode")) === "vibrato",
   await page.evaluate("App.trMode"));

// 9. Scale sing-through: chips, caption, sequence synthesis, scoring wiring.
await page.evaluate('go("tracker")');
await page.click('span.chip[onclick="setTrMode(\'scale\')"]');
ok("scale mode selected", await page.evaluate("App.trMode") === "scale");
await page.waitForTimeout(200);
ok("scale caption", (await page.locator("text=데모 후 노트마다 따라 부르세요").count()) >= 1);
const scale = await page.evaluate(`(() => {
  const l1 = scaleSequence(60, scalePattern(1));
  const l2 = scaleSequence(60, scalePattern(2));
  const l3 = scaleSequence(55, scalePattern(3));
  const clamped = scaleSequence(69, scalePattern(2));
  return {
    l1: JSON.stringify(l1) === JSON.stringify([60, 62, 64, 67, 69]),
    l2: JSON.stringify(l2) === JSON.stringify([60, 62, 64, 65, 67, 69, 71, 72]),
    l3: JSON.stringify(l3) === JSON.stringify([55, 59, 62, 67, 62, 59, 55]),
    clamp: clamped.every(m => m >= 43 && m <= 72) && clamped[clamped.length - 1] === 72,
    levelClamp: scalePattern(9) === "arpeggioSweep",
  };
})()`);
ok("scale L1 pentatonic", scale.l1);
ok("scale L2 major", scale.l2);
ok("scale L3 arpeggio", scale.l3);
ok("scale band clamp", scale.clamp);
ok("scale level clamp", scale.levelClamp);
// Flow wiring: startScaleFlow must exist and gate scoring during the demo.
const flowOk = await page.evaluate(`(() => {
  App.echo.gen++;
  const gen = App.echo.gen;
  startScaleFlow();
  const gated = App.ignoreUntil === Infinity && App.echo.midis.length >= 5;
  App.echo.timers.forEach(clearTimeout);
  App.echo.gen++; App.echo.midis = []; App.ignoreUntil = 0; App.listening = false;
  return gated;
})()`);
ok("scale flow gates + sequence", flowOk);

// 11. Melody call-and-response: contour phrases, deterministic vectors,
// and the shared drill flow.
const melody = await page.evaluate(`(() => {
  const r0 = () => 0;
  const asc = melodyPhrase("ascending", 60, r0);
  const desc = melodyPhrase("descending", 67, r0);
  const arch = melodyPhrase("arch", 60, r0);
  const wave = melodyPhrase("wave", 60, r0);
  const r7 = () => 7;
  const clamped = melodyPhrase("arch", 69, r7);
  const ladder = melodyContour(1, () => 0) === "ascending"
    && melodyContour(2, () => 0) === "arch"
    && melodyContour(9, () => 1) === "descending";
  return {
    asc: JSON.stringify(asc) === JSON.stringify([60, 61, 62, 63]),
    desc: JSON.stringify(desc) === JSON.stringify([67, 66, 65, 64]),
    arch: JSON.stringify(arch) === JSON.stringify([60, 61, 62, 63, 62, 61]),
    wave: JSON.stringify(wave) === JSON.stringify([60, 61, 60, 59, 60, 61]),
    clamp: clamped.every(m => m >= 43 && m <= 72),
    ladder,
  };
})()`);
ok("melody ascending", melody.asc);
ok("melody descending", melody.desc);
ok("melody symmetric arch", melody.arch);
ok("melody wave alternates", melody.wave);
ok("melody band clamp", melody.clamp);
ok("melody level ladder", melody.ladder);
const melodyFlow = await page.evaluate(`(() => {
  App.echo.gen++;
  startMelodyFlow();
  const ok = App.ignoreUntil === Infinity && App.echo.midis.length >= 4
    && (App._melodyLabel || "").startsWith("멜로디 ");
  App.echo.timers.forEach(clearTimeout);
  App.echo.gen++; App.echo.midis = []; App.ignoreUntil = 0; App.listening = false;
  return ok;
})()`);
ok("melody flow gates + label", melodyFlow);

await browser.close();

console.log(checks.join("\n"));
const fails = checks.filter(c => c.startsWith("FAIL")).length;
console.log(`\nVIBRATO UI E2E: ${checks.length - fails}/${checks.length} passed`);
if (notFound.length) { console.log("404 RESOURCES:\n" + [...new Set(notFound)].join("\n")); }
if (consoleErrors.length) { console.log("CONSOLE ERRORS:\n" + consoleErrors.join("\n")); }
process.exit(fails ? 1 : 0);
