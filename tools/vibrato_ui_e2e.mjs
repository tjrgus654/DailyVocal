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
ok("mode chips rendered", chipCount === 14, `count=${chipCount}`);
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
  Store.data.harmonyAboveCents = 22;
  Store.data.harmonyBelowCents = -30;
  Store.save();
  render();
})()`);
await page.waitForTimeout(200);
ok("growth sustain line", (await page.locator("text=16.4초 (한 호흡 최대 발성)").count()) >= 1);
ok("growth harmony bias line", (await page.locator("text=위 성부 +22¢ / 아래 성부 −30¢").count()) >= 1);

// 7b. Technique trend sparkline: >=2 same-kind measures render bars.
const trend = await page.evaluate(`(() => {
  Store.data.vibratoTrend = [4.2, 4.8, 5.1, 5.4];
  Store.data.dynamicsTrend = [];
  Store.save();
  render();
  const card = techniqueTrendCard();
  return {
    title: card && card.title === "비브라토 속도(Hz)",
    count: card && card.values.length === 4,
    lastGreen: (card && card.bars || "").includes("vocal-success"),
  };
})()`);
ok("trend card vibrato series", trend.title && trend.count, JSON.stringify(trend));
ok("trend highlights recent best", trend.lastGreen);
await page.waitForTimeout(200);
ok("trend card rendered", (await page.locator("text=비브라토 속도(Hz) 추이").count()) >= 1);
// Cleanup so later phases see no trend — then check the sustain kind.
const susTrend = await page.evaluate(`(() => {
  Store.data.vibratoTrend = [];
  Store.data.dynamicsTrend = [];
  Store.data.sustainTrend = [8.2, 10.5, 12.1];
  Store.save();
  render();
  const card = techniqueTrendCard();
  return { title: card && card.title === "최장 지속(초)", n: card && card.values.length === 3 };
})()`);
ok("trend sustain kind", susTrend.title && susTrend.n, JSON.stringify(susTrend));
ok("trend sustain rendered", (await page.locator("text=최장 지속(초) 추이").count()) >= 1);
// Step-error trend: lower is better — the LOWEST bar goes green.
const errTrend = await page.evaluate(`(() => {
  Store.data.sustainTrend = [];
  Store.data.scaleErrTrend = [1.8, 1.2, 0.6];
  Store.save(); render();
  const card = techniqueTrendCard();
  const bars = (card.bars.match(/vocal-success/g) || []).length;
  // The bars render in series order; the green one must be the LAST bar
  // (0.6 is the best = lowest). Find its offset vs the first bar's start.
  // The green fill sits inside the LAST bar — after the middle bar's label.
  const greenPos = card.bars.lastIndexOf("vocal-success");
  const middleLabelPos = card.bars.lastIndexOf("1.2");
  Store.data.scaleErrTrend = [];
  Store.save(); render();
  return { title: card.title === "스케일 오차(반음)", bars, greenAfterLastValue: greenPos > middleLabelPos };
})()`);
ok("step-error trend kind", errTrend.title, JSON.stringify(errTrend));
ok("step-error trend inverts highlight", errTrend.bars === 1 && errTrend.greenAfterLastValue,
   JSON.stringify(errTrend));
await page.evaluate(`(() => {
  Store.data.sustainTrend = [];
  Store.save();
  render();
})()`);

// 8. Next-game recommendation card (records-driven, technique-aware).
await page.evaluate(`(() => {
  // Isolate from earlier runs: localStorage keeps fingerprints/records
  // across navigations, which would skew the recommendation vectors.
  Store.data.pitchRecords = [
    { t: 1, target: "모음 게임", acc: 78, lo: 0, hi: 0, dur: 60 },
    { t: 2, target: "음정 게임", acc: 82, lo: 0, hi: 0, dur: 30 },
    { t: 3, target: "귀훈련", acc: 85, lo: 0, hi: 0, dur: 30 },
    { t: 4, target: "스케일 시퀀스", acc: 72, lo: 0, hi: 0, dur: 35 },
    { t: 5, target: "멜로디 프레이즈", acc: 76, lo: 0, hi: 0, dur: 30 },
    { t: 6, target: "화음 부르기", acc: 73, lo: 0, hi: 0, dur: 30 },
    { t: 7, target: "민요 따라부르기", acc: 74, lo: 0, hi: 0, dur: 45 },
    { t: 8, target: "파사지오 왕복", acc: 76, lo: 0, hi: 0, dur: 30 },
    { t: 9, target: "고음 확장", acc: 75, lo: 0, hi: 0, dur: 30 },
    { t: 10, target: "다이내믹스 아치", acc: 62, lo: 0, hi: 0, dur: 40 },
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
// vowel 78 / interval 82 / ear 85 / scale 72 / melody 76 / harmony 73 / dynamics 62
// measured; vibrato unmeasured (50) is the unique weakest -> vibrato, "시도하지 않은" reason.
const recGame = await page.evaluate("nextGameRecommendation().game");
ok("recommendation game is vibrato", recGame === "vibrato", recGame);
ok("recommendation reason is unmeasured", (await page.evaluate("nextGameRecommendation().reason")).includes("시도하지 않은"));
// With vibrato measured too, the weakest measured skill (dynamics 62) wins.
const recWeakest = await page.evaluate(`(() => {
  // t must exceed the seed's max (7): with a tie at t:6 the chronological
  // last stays dynamics, lastGame == weakest, and the variety rule (gap
  // 72-62 <= 15) correctly returns the runner-up scale instead.
  Store.data.pitchRecords.push({ t: 11, target: "비브라토 체크", acc: 74, lo: 0, hi: 0, dur: 45 });
  Store.save();
  render();
  return nextGameRecommendation();
})()`);
ok("recommendation weakest measured", recWeakest.game === "dynamics" && recWeakest.reason.includes("62점"), recWeakest.game);

// 9c. Measurement-based evidence: a weak vibrato score + a 3.8Hz stored
// fingerprint turns the reason into the wobble line.
const evidence = await page.evaluate(`(() => {
  // t:9 keeps this the LATEST vibrato record (the recWeakest push used
  // t:8; latestAccuracies takes the last match in chronological order).
  Store.data.pitchRecords.push({ t: 12, target: "비브라토 체크", acc: 30, lo: 0, hi: 0, dur: 45 });
  Store.data.lastVibratoRateHz = 3.8;
  Store.data.lastVibratoExtentCents = 80;
  Store.save();
  render();
  return nextGameRecommendation();
})()`);
ok("evidence picks weakest vibrato", evidence.game === "vibrato", evidence.game);
ok("evidence cites measurement", evidence.reason.includes("3.8Hz") && evidence.reason.includes("워블"), evidence.reason);

// 9d. Harmony direction bias in the evidence line.
const harmEv = await page.evaluate(`(() => {
  Store.data.harmonyAboveCents = 22;
  Store.data.harmonyBelowCents = -5;
  Store.save();
  render();
  return recommendationEvidence("harmony", 40, 0, 0, 0, 22, -5);
})()`);
ok("harmony evidence names weaker direction",
   harmEv.includes("위") && harmEv.includes("+22센트") && harmEv.includes("내려서"), harmEv);
const harmEv2 = await page.evaluate(`(() => {
  Store.data.harmonyAboveCents = 8;
  Store.data.harmonyBelowCents = -30;
  Store.save();
  render();
  return recommendationEvidence("harmony", 40, 0, 0, 0, 8, -30);
})()`);
ok("harmony evidence flips to below when flatter",
   harmEv2.includes("아래") && harmEv2.includes("−30센트") && harmEv2.includes("올려서"), harmEv2);

// 9d-2. Stretch ladder reach-rate evidence decodes the ladder score band.
const stretchEv = await page.evaluate(`(() => {
  const full = recommendationEvidence("stretch", 100, 0, 0, 0, 0, 0, 0);
  const two = recommendationEvidence("stretch", 67, 0, 0, 0, 0, 0, 0);
  const one = recommendationEvidence("stretch", 33, 0, 0, 0, 0, 0, 0);
  const none = recommendationEvidence("stretch", 0, 0, 0, 0, 0, 0, 0);
  return [full, two, one, none];
})()`);
ok("stretch evidence bands reach rate",
   stretchEv[0].includes("3라운드 모두 도달") && stretchEv[1].includes("2/3 도달")
   && stretchEv[2].includes("1/3 도달") && stretchEv[3].includes("0/3"),
   stretchEv.join(" | "));

// 9e. Step-error evidence for scale/melody recommendations.
const stepEv = await page.evaluate(`(() => {
  Store.data.scaleStepError = 1.4;
  Store.data.melodyStepError = 0.6;
  Store.save(); render();
  const scale = recommendationEvidence("scale", 40, 0, 0, 0, 0, 0, 0, 1.4);
  const melody = recommendationEvidence("melody", 40, 0, 0, 0, 0, 0, 0, 0.6);
  return { scale, melody };
})()`);
ok("scale evidence cites step error",
   stepEv.scale.includes("1.4반음") && stepEv.scale.includes("5 BPM"), stepEv.scale);
ok("melody evidence cites tight phrase",
   stepEv.melody.includes("0.6반음") && stepEv.melody.includes("늘려볼 차례"), stepEv.melody);
await page.evaluate(`(() => {
  Store.data.scaleStepError = 0;
  Store.data.melodyStepError = 0;
  Store.save(); render();
})()`);
// Reset so later phases start clean.
await page.evaluate(`(() => {
  Store.data.harmonyAboveCents = 0;
  Store.data.harmonyBelowCents = 0;
  Store.save();
  render();
})()`)

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
  const lengthLadder = melodyLength(1) === 4 && melodyLength(2) === 6
    && melodyLength(3) === 8 && melodyLength(9) === 8;
  const arch8 = melodyPhrase("arch", 60, () => 0, 8);
  const wave8 = melodyPhrase("wave", 60, () => 0, 8);
  return {
    asc: JSON.stringify(asc) === JSON.stringify([60, 61, 62, 63]),
    desc: JSON.stringify(desc) === JSON.stringify([67, 66, 65, 64]),
    arch: JSON.stringify(arch) === JSON.stringify([60, 61, 62, 63, 62, 61]),
    wave: JSON.stringify(wave) === JSON.stringify([60, 61, 60, 59, 60, 61]),
    clamp: clamped.every(m => m >= 43 && m <= 72),
    ladder,
    lengthLadder,
    arch8: JSON.stringify(arch8) === JSON.stringify([60, 61, 62, 63, 64, 63, 62, 61]),
    wave8: JSON.stringify(wave8) === JSON.stringify([60, 61, 60, 59, 60, 61, 60, 59]),
  };
})()`);
ok("melody ascending", melody.asc);
ok("melody descending", melody.desc);
ok("melody symmetric arch", melody.arch);
ok("melody wave alternates", melody.wave);
ok("melody band clamp", melody.clamp);
ok("melody level ladder", melody.ladder);
ok("melody length ladder 4/6/8", melody.lengthLadder);
ok("melody L3 arch 8 notes", melody.arch8);
ok("melody L3 wave 8 notes", melody.wave8);
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

// 12. Drill tempo (BPM): timings derive from one beat, clamp 40-80,
// and the tempo bar renders only in scale/melody modes.
const tempo = await page.evaluate(`(() => {
  const t50 = drillTimings(50), t40 = drillTimings(40), t80 = drillTimings(80), t10 = drillTimings(10);
  return {
    t50: t50.note === 1020 && t50.gap === 180 && t50.window === 1800,
    monotonic: t80.note < t40.note && t80.window < t40.window,
    clamp: t10.note === t40.note && drillTimings(500).note === t80.note,
    beat: Math.abs((t50.note + t50.gap) - 1200) <= 1,
  };
})()`);
ok("tempo timings at 50 BPM", tempo.t50);
ok("tempo monotonic 40<80", tempo.monotonic);
ok("tempo clamp 40-80", tempo.clamp);
ok("tempo note+gap = one beat", tempo.beat);
// The bar only renders in the sequence-drill modes — check hidden from
// single mode first, then visible after switching to scale.
await page.click('span.chip[onclick="setTrMode(\'single\')"]');
await page.waitForTimeout(200);
ok("tempo bar hidden in single mode", (await page.locator("text=프레이즈 템포").count()) === 0);
await page.click('span.chip[onclick="setTrMode(\'scale\')"]');
await page.waitForTimeout(200);
ok("tempo bar visible in scale mode", (await page.locator("text=프레이즈 템포").count()) >= 1);
const bpmAfter = await page.evaluate(`(() => { setDrillBpm(5); return drillBpm(); })()`);
ok("tempo stepper raises BPM", bpmAfter === 55, String(bpmAfter));

// 13. Harmony sing-along: part offsets, ladder, target clamp, feedback
// bands, and the drone->record flow gating.
const harmony = await page.evaluate(`(() => {
  const ladder = harmonyPart(1, () => 0) === "thirdAbove"
    && harmonyPart(2, () => 0) === "fifthAbove"
    && harmonyPart(9, () => 3) === "fifthBelow";
  return {
    offsets: HARMONY_PARTS.thirdAbove.offset === 4 && HARMONY_PARTS.fifthBelow.offset === -7,
    ladder,
    target: harmonyTarget(60, "thirdAbove") === 64 && harmonyTarget(60, "fifthBelow") === 53
      && harmonyTarget(70, "fifthAbove") === 72 && harmonyTarget(45, "thirdBelow") === 43,
    fbHit: harmonyFeedback("thirdAbove", 8).includes("맞았습니다"),
    fbNear: harmonyFeedback("fifthAbove", -30).includes("센트 차이"),
    fbHigh: harmonyFeedback("thirdBelow", 90).includes("아래로"),
    fbLow: harmonyFeedback("fifthBelow", -90).includes("위로"),
  };
})()`);
ok("harmony part offsets", harmony.offsets);
ok("harmony level ladder", harmony.ladder);
ok("harmony target + clamp", harmony.target);
ok("harmony feedback hit band", harmony.fbHit);
ok("harmony feedback near band", harmony.fbNear);
ok("harmony feedback direction high", harmony.fbHigh);
ok("harmony feedback direction low", harmony.fbLow);
const harmonyFlow = await page.evaluate(`(() => {
  App.echo.gen++;
  startHarmonyCheck();
  const okGated = App.ignoreUntil === Infinity && HARMONY_CHECK.targetMidi > 0
    && HARMONY_CHECK.phase === "guide";
  HARMONY_CHECK.timers.forEach(clearTimeout);
  HARMONY_CHECK.phase = "idle"; HARMONY_CHECK.cents = []; HARMONY_CHECK.targetMidi = 0;
  App.echo.gen++; App.ignoreUntil = 0; App.listening = false;
  return okGated;
})()`);
ok("harmony flow gates + target", harmonyFlow);

// 13b. Drone length: clamp 1.0-5.0, default 2.0, stepper + bar visibility.
const drone = await page.evaluate(`(() => ({
  clampLow: clampedDroneSeconds(0.2) === 1.0 && clampedDroneSeconds(9) === 5.0,
  def: droneSeconds() >= 1.0 && droneSeconds() <= 5.0,
}))()`);
ok("drone clamp 1-5s", drone.clampLow);
ok("drone default bounded", drone.def);
ok("drone bar hidden in scale mode", (await page.locator("text=드론 길이").count()) === 0);
await page.click('span.chip[onclick="setTrMode(\'harmony\')"]');
await page.waitForTimeout(200);
ok("drone bar visible in harmony mode", (await page.locator("text=드론 길이").count()) >= 1);
const droneAfter = await page.evaluate(`(() => {
  const before = droneSeconds();
  setDroneSeconds(0.5);
  return { before, after: droneSeconds() };
})()`);
ok("drone stepper raises length", droneAfter.after > droneAfter.before
  && droneAfter.after <= 5.0, JSON.stringify(droneAfter));

// 14. Folk songs: three PD originals, pentatonic notes, rhythm-preserving
// durations, sequence clamp, rotation, and the flow gating.
const folk = await page.evaluate(`(() => {
  const seq = songSequence(FOLK_SONGS[0], 55);
  const clamped = songSequence(FOLK_SONGS[2], 69);
  const at60 = songNoteDurations(FOLK_SONGS[1], 60);
  const at80 = songNoteDurations(FOLK_SONGS[1], 80);
  return {
    three: FOLK_SONGS.length === 22 && FOLK_SONGS.map(s => s.title).join(",") === "아리랑,강강술래,한오백년,정선아리랑,둥당기타령,도라지타령,난봉가,매화타령,신고산타령,오죽령,닐리리야,새타령,변강쇠타령,쾌지나칭칭나네,진도아리랑,오돌또기,베틀가,칭칭야,어랑타령,돈돌라,범피중류,쑥대머리",
    origins: FOLK_SONGS.every(s => s.origin.includes("전통")),
    seq: seq[0] === 55 + 7 && seq[seq.length - 1] === 55 + 3,
    clamp: clamped.every(m => m >= 43 && m <= 72) && Math.max(...clamped) === 72,
    rhythm: at60[0] === 1000 && at80[0] === 750,
    ends: FOLK_SONGS.every(s => s.notes[s.notes.length - 1][1] >= 3),
  };
})()`);
ok("folk library ships 22 songs", folk.three);
ok("folk origins cite tradition", folk.origins);
ok("folk arirang sequence", folk.seq);
ok("folk band clamp", folk.clamp);
ok("folk rhythm at 60/80 BPM", folk.rhythm);
ok("folk phrases resolve long", folk.ends);
const folkFlow = await page.evaluate(`(() => {
  App.echo.gen++;
  startSongFlow();
  const okGated = App.ignoreUntil === Infinity
    && (App._melodyLabel || "").length > 0
    && FOLK_SONGS.some(s => s.title === App._melodyLabel);
  App.echo.timers.forEach(clearTimeout);
  App.echo.gen++; App.echo.midis = []; App.ignoreUntil = 0; App.listening = false;
  return okGated;
})()`);
ok("folk flow gates + song label", folkFlow);

// 14b. Song picker: chips pin a specific song (label + flow use it).
const pickerOk = await page.evaluate(`(() => {
  selectSong(5);
  return { label: currentSong().title, rolled: SONG_STATE.rolled };
})()`);
ok("song picker pins 도라지타령", pickerOk.label === "도라지타령" && pickerOk.rolled,
   JSON.stringify(pickerOk));

// 14e. Region tags + next-song preview in the toast line.
const regionOk = await page.evaluate(`(() => ({
  gangwon: songRegion(FOLK_SONGS.find(s => s.title === "정선아리랑")) === "강원",
  jeolla: songRegion(FOLK_SONGS.find(s => s.title === "한오백년")) === "전라",
  gyeonggi: FOLK_SONGS.filter(s => songRegion(s) === "경기").length >= 4,
}))()`);
ok("region tags derive from origin", regionOk.gangwon && regionOk.jeolla && regionOk.gyeonggi,
   JSON.stringify(regionOk));

// 14f. Region filter UI narrows the picker.
await page.evaluate('go("tracker")');
await page.click('span.chip[onclick="setTrMode(\'song\')"]');
await page.waitForTimeout(200);
ok("region filter row rendered", (await page.locator("text=지역").count()) >= 1);
const filtered = await page.evaluate(`(() => {
  setSongRegionFilter("강원");
  const chips = [...document.querySelectorAll('.chip[onclick^="selectSong"]')];
  const titles = chips.map(c => c.textContent.replace("강원", "").trim());
  setSongRegionFilter("");
  return { titles, all: chips.length };
})()`);
ok("filter narrows to 강원 songs",
   filtered.titles.join(",") === "정선아리랑,어랑타령",
   JSON.stringify(filtered.titles));
const previewNext = await page.evaluate(`(() => {
  // Song preview appears in the completion toast: simulate a scored stop in song mode.
  App.trMode = "song";
  App.listening = true;  // stopTracking early-returns without this
  App.voiced = 20; App.hits = 16;
  App.lastScore = null;
  const before = FOLK_SONGS[(SONG_STATE.index + 1) % FOLK_SONGS.length].title;
  // stopTracking pushes a record and toasts; capture the toast text via the
  // DOM after the call.
  App.trMode = "song";
  window.__toastText = "";
  const origToast = window.toast;
  window.toast = (html) => { window.__toastText = html; };
  stopTracking();
  window.toast = origToast;
  return { before, text: window.__toastText || "" };
})()`);
ok("song completion toasts next song",
   previewNext.text.includes("다음 곡") && previewNext.text.includes(previewNext.before),
   previewNext.before);

// 14i. Session completion toast carries the tip line.
const tipToast = await page.evaluate(`(() => {
  App.trMode = "single"; App.listening = true;
  App.voiced = 20; App.hits = 16;
  Store.data.bestSustainSeconds = 9;  // breath wall -> tip 60
  Store.save();
  window.__toastText = "";
  const orig = window.toast;
  window.toast = (html) => { window.__toastText = String(html); };
  stopTracking();
  window.toast = orig;
  Store.data.bestSustainSeconds = 0; Store.save();
  return window.__toastText;
})()`);
ok("session toast carries tip line",
   tipToast.includes("팁 #60") && tipToast.includes("호흡 지지"), tipToast.slice(-80));

// 14k. Toast tip line deep links to the lab (same path as growth).
const toastTipNav = await page.evaluate(`(() => {
  App.trMode = "single"; App.listening = true;
  App.voiced = 20; App.hits = 16;
  Store.data.bestSustainSeconds = 9;
  Store.save();
  const origToast = window.toast;
  let captured = "";
  window.toast = (html) => {
   captured = String(html);
   // Execute any onclick handlers attached in the captured HTML (simulate).
 if (captured.includes('onclick="openRecommendedTip(60)"')) window.__tipId = "60";
  };
  stopTracking();
  window.toast = origToast;
  Store.data.bestSustainSeconds = 0; Store.save(); render();
  return { tipId: window.__tipId, hadClick: captured.includes("openRecommendedTip") };
})()`);
ok("session toast tip deep-linkable",
   toastTipNav.hadClick && toastTipNav.tipId === "60", JSON.stringify(toastTipNav));

// 14g. Daily summary line: hidden on 1st session, shown from the 2nd.
const daySum = await page.evaluate(`(() => {
  const hidden = dailySummaryLine(1, 3, 90);
  const shown = dailySummaryLine(2, 3, 84);
  const partial = dailySummaryLine(2, 0, 70);
  const noScore = dailySummaryLine(3, 1, null);
  return {
    hidden: hidden === null,
    shown: shown === "오늘의 마무리: 루틴 2회 · 테크닉 측정 3회 · 최고 84점",
    partial: partial === "오늘의 마무리: 루틴 2회 · 최고 70점",
    noScore: noScore === "오늘의 마무리: 루틴 3회 · 테크닉 측정 1회",
  };
})()`);
ok("daily summary hidden on 1st", daySum.hidden);
ok("daily summary full form", daySum.shown, JSON.stringify(daySum));
ok("daily summary omits empty", daySum.partial && daySum.noScore);

// 14h. Data-driven tip recommendation.
const tipRec = await page.evaluate(`(() => {
  const breath = recommendedTip(3.8, 4.0, 9, true);
  const vib = recommendedTip(7.2, 4.0, 16, false);
  const male = recommendedTip(5.5, 8, 16, true);
  const general = recommendedTip(0, 0, 0, false);
  return { breath: breath.id === 60 && breath.reason.includes("호흡 지지"),
           vib: vib.id === 55, male: male.id === 58, general: general.id === 57 };
})()`);
ok("tip rec weakness-first", tipRec.breath && tipRec.vib, JSON.stringify(tipRec));
ok("tip rec fallbacks", tipRec.male && tipRec.general);

// 14j. Tip deep link: the growth line opens the lab tip.
await page.evaluate('go("progress")');
await page.evaluate(`(() => {
  Store.data.lastVibratoRateHz = 0;
  Store.data.lastDynamicsRangeDb = 0;
  Store.data.bestSustainSeconds = 9;  // -> tip 60
  Store.save(); render();
})()`);
await page.waitForTimeout(200);
ok("growth tip line clickable", (await page.locator('[onclick^="openRecommendedTip(60)"]').count()) >= 1);
const tipNav = await page.evaluate(`(() => {
  window.__toastText = "";
  const orig = window.toast;
  window.toast = (html) => { window.__toastText = String(html); };
  openRecommendedTip(60);
  window.toast = orig;
  return { tab: App.tab, text: window.__toastText.slice(0, 120) };
})()`);
ok("tip deep link opens lab tip",
   tipNav.tab === "lab" && tipNav.text.includes("민요로 배우는"), JSON.stringify(tipNav).slice(0, 100));
await page.evaluate(`(() => {
  Store.data.bestSustainSeconds = 0; Store.save(); render();
})()`);

// 14d. Passaggio round-trip: zone-crossing arch per male voice type.
const pass = await page.evaluate(`(() => {
  const bar = passaggioSequence("baritone");
  const tenor = passaggioSequence("tenor");
  const undet = passaggioSequence("미확정");
  const sop = passaggioSequence("soprano");
  return {
    bar: JSON.stringify(bar) === JSON.stringify([62,64,65,67,68,67,65,64]),
    tenorCross: bar.includes(64) && bar.includes(67) && tenor.includes(66) && tenor.includes(69),
    fallback: JSON.stringify(undet) === JSON.stringify(bar),
    clamp: sop.every(m => m >= 43 && m <= 72),
    zoneLabel: Array.isArray(passaggioZoneOf("baritone")),
  };
})()`);
ok("passaggio baritone arch", pass.bar);
ok("passaggio tenor crosses its zone", pass.tenorCross);
ok("passaggio undetermined falls back", pass.fallback);
ok("passaggio soprano clamps into band", pass.clamp);
const passFlow = await page.evaluate(`(() => {
  App.echo.gen++;
  startPassaggioDrill();
  const okGated = App.ignoreUntil === Infinity && App.echo.midis.length >= 5
    && (App._passaggioLabel || "").includes("파사지오");
  App.echo.timers.forEach(clearTimeout);
  App.echo.gen++; App.echo.midis = []; App.ignoreUntil = 0; App.listening = false;
  return okGated;
})()`);
ok("passaggio flow gates + zone label", passFlow);

// 15. Range-extension stretch ladder.
const stretch = await page.evaluate(`(() => {
  const targets = stretchTargets(65);
  const base = stretchBaseMidi(65);
  const clamped = stretchTargets(71);
  const labels = [0, 1, 2].map(stretchRoundLabel);
  const reach = [
    stretchReached(7, 65, 58),
    stretchReached(6, 65, 58),
    stretchReached(5, 65, 58),
    stretchReached(null, 65, 58),
  ];
  const fb = stretchFeedback(true, 65, 58, 7).includes("F4");
  const fbShort = stretchFeedback(false, 65, 58, 5).includes("2\uBC18\uC74C \uC544\uB798");
  const name = midiNoteName(60) === "C4" && midiNoteName(71) === "B4";
  const perf = performedSemitones([60, 60.3, 61], 58);
  return { targets, base, clamped, labels, reach, fb, fbShort, name, perf };
})()`);
ok("stretch targets 65->65,66,67", JSON.stringify(stretch.targets) === "[65,66,67]", JSON.stringify(stretch.targets));
ok("stretch base fifth below", stretch.base === 58);
ok("stretch clamp at band top", JSON.stringify(stretch.clamped) === "[71,72,72]", JSON.stringify(stretch.clamped));
ok("stretch round labels", stretch.labels[0].includes("\uC7AC\uD655\uC778") && stretch.labels[2].includes("\uB450 \uC74C \uC704"));
ok("stretch reached tolerance", stretch.reach[0] && stretch.reach[1] && !stretch.reach[2] && !stretch.reach[3]);
ok("stretch feedback hit/short", stretch.fb && stretch.fbShort);
ok("stretch note names", stretch.name);
ok("stretch performed semitones", stretch.perf === 2);
const stretchFlow = await page.evaluate(`(() => {
  App.echo.gen++;
  startStretchLadder();
  const gated = App.ignoreUntil === Infinity && STRETCH.timers.length >= 2;
  STRETCH.timers.forEach(clearTimeout); STRETCH.timers = [];
  App.echo.gen++; App.ignoreUntil = 0; App.listening = false;
  return gated;
})()`);
ok("stretch flow gates demos", stretchFlow);

// 14c. Suggested base note: measured range wins, manual pick locks it.
const sug = await page.evaluate(`(() => {
  Store.data.prefs.userPickedTarget = false;
  Store.data.range = { lo: 110, hi: 330 };  // ~A2..E4 male-typical
  applySuggestedBaseNoteIfNeeded();
  const suggested = App.target.midi;
  // Manual pick locks: setTarget sets the flag, suggestion no longer applies.
  setTarget("C4");
  const afterPick = App.target.midi;
  Store.data.range = { lo: 220, hi: 660 };
  applySuggestedBaseNoteIfNeeded();
  return { suggested, afterPick, locked: App.target.midi === afterPick };
})()`);
ok("suggested base uses measured range", sug.suggested === 49, "midi " + sug.suggested);
ok("manual pick locks suggestion", sug.locked && sug.afterPick === 60, JSON.stringify(sug));

await browser.close();

console.log(checks.join("\n"));
const fails = checks.filter(c => c.startsWith("FAIL")).length;
console.log(`\nVIBRATO UI E2E: ${checks.length - fails}/${checks.length} passed`);
if (notFound.length) { console.log("404 RESOURCES:\n" + [...new Set(notFound)].join("\n")); }
if (consoleErrors.length) { console.log("CONSOLE ERRORS:\n" + consoleErrors.join("\n")); }
process.exit(fails ? 1 : 0);
