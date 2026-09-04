// Real-audio pipeline E2E: feeds a WAV through Chromium's fake capture
// device (mic emulation) and verifies the prototype detects its content.
// Usage: node tools/audio_e2e.mjs  (needs `npm i playwright-core` + system Edge;
// serve repo root on 127.0.0.1:8766 first). See VERIFICATION_LOG #113-115.
import { chromium } from "playwright-core";
import path from "node:path";

const WAV = path.join("C:", "Users", "vibe", "Desktop", "5VocalMaster", "preview", "qa", "test_melody.wav");
const URL = "http://127.0.0.1:8766/preview/live.html";

const browser = await chromium.launch({
  channel: "msedge",
  headless: true,
  args: [
    "--use-fake-device-for-media-stream",
    "--use-file-for-fake-audio-capture=" + WAV,
    "--autoplay-policy=no-user-gesture-required",
  ],
});
const context = await browser.newContext({ permissions: ["microphone"] });
const page = await context.newPage();
await page.goto(URL);
await page.waitForLoadState("domcontentloaded");
await page.waitForTimeout(600);

await page.evaluate("finishOnboarding()");
await page.evaluate('go("tracker")');
const micGranted = await page.evaluate("Audio5.startMic()");
await page.evaluate("startTracking()");
await page.waitForTimeout(6000);

const result = await page.evaluate("(() => {" +
"  const hist = App.history;" +
"  const voiced = hist.filter(p => p.f > 0);" +
"  const seg = [];" +
"  for (let w = 0; w < 22; w++){" +
"    const part = voiced.slice(w*4, (w+1)*4).map(p => p.f).sort((a,b)=>a-b);" +
"    seg.push(part.length ? +(part[Math.floor(part.length/2)].toFixed(1)) : 0);" +
"  }" +
"  return { totalFrames: App.history.length, voicedFrames: voiced.length," +
"    detectedNote: (document.getElementById('liveNote')||{}).innerText || ''," +
"    segments: seg, accuracy: App.voiced > 0 ? Math.round(App.hits/App.voiced*100) : 0 };" +
"})()");
console.log(JSON.stringify(result, null, 2));
await browser.close();
