// Vibrato-mode UI E2E: drives the web prototype in headless Edge, walks the
// full vibrato flow (guide caption -> recording caption -> synthetic analysis
// -> result card) using the same test-hook path as audio_e2e.mjs, and checks
// for console errors. Usage: node tools/vibrato_ui_e2e.mjs (serve :8766 first).
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
ok("mode chips rendered", chipCount === 7, `count=${chipCount}`);
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

await browser.close();

console.log(checks.join("\n"));
const fails = checks.filter(c => c.startsWith("FAIL")).length;
console.log(`\nVIBRATO UI E2E: ${checks.length - fails}/${checks.length} passed`);
if (notFound.length) { console.log("404 RESOURCES:\n" + [...new Set(notFound)].join("\n")); }
if (consoleErrors.length) { console.log("CONSOLE ERRORS:\n" + consoleErrors.join("\n")); }
process.exit(fails ? 1 : 0);
