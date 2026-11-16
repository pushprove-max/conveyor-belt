// SPDX-License-Identifier: Apache-2.0
// Records the demo's Board beats (4 to 9 of the twelve in index.html), and the README's Belt 3D clip, from the real
// Board page (.claude/dashboard), served on localhost from the mock timeline (timeline.js) and driven in headless Chrome.
// Usage: node capture-board.js <out dir>   writes beat4.mp4 ... beat8.mp4, tests.mp4, and belt3d.mp4 with
// belt3d.json (the clip's seconds its card details open and close) there (ffmpeg on PATH). belt3d.mp4 is filmed frame
// by frame on the page's clock (frame-clock.js), 30 frames a second, cut to the Belt 3D panel.
// Nothing here reads a real Conveyor: the page's feed (/events), data.js and its control actions (POST /control) are
// all answered from timeline.js, and the server listens on 127.0.0.1 only.
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';
import { film, installClock } from './frame-clock.js';
import { BELT3D, createTimeline, TEST_ANSWERS } from './timeline.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const VIEW = path.resolve(HERE, '..', '..', '.claude', 'dashboard');
const OUT = path.resolve(process.argv[2] || path.join(HERE, 'build', 'captures'));
const W = 1280, H = 800;
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' };

// The story clock: t0 at the wall time wall0, running at speed story seconds a wall second. While filmed (the Belt 3D
// clip), the page is fed by the film alone, each frame's snapshot at that frame's story second.
const story = { tl: null, t0: 0, wall0: Date.now(), speed: 1, filmed: false };
const now = () => story.t0 + ((Date.now() - story.wall0) / 1000) * story.speed;
function setClock(t0, speed = 1) { story.t0 = t0; story.wall0 = Date.now(); story.speed = speed; }

const feeds = new Set();
function serve(req, res) {
  const url = new URL(req.url, 'http://127.0.0.1');
  if (req.method === 'POST' && url.pathname === '/control') {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      let m = {};
      try { m = JSON.parse(body); } catch (e) { m = {}; }
      const r = story.tl.act(m.action, m.args, now());
      const head = { 'Content-Type': 'text/plain', 'X-Answered-At': String(Math.ceil(Date.now() / 1000)) };
      if (r instanceof Error) { res.writeHead(409, head); res.end(r.message); return; }
      res.writeHead(200, head); res.end(typeof r === 'string' ? r : JSON.stringify(r));
      push();
    });
    return;
  }
  if (url.pathname === '/events') {
    res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store' });
    feeds.add(res);
    req.on('close', () => feeds.delete(res));
    res.write(`event: snapshot\ndata: ${JSON.stringify(story.tl.snapshot(now()))}\n\n`);
    return;
  }
  if (url.pathname === '/data.js') { res.writeHead(200, { 'Content-Type': 'text/javascript' }); res.end(`window.DASH = ${JSON.stringify(story.tl.snapshot(now()))};`); return; }
  if (url.pathname === '/alive.js') { res.writeHead(200, { 'Content-Type': 'text/javascript' }); res.end(`window.DASH_ALIVE = ${JSON.stringify({ at: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'), view: null })};`); return; }
  if (url.pathname === '/history') { res.writeHead(404); res.end(); return; }
  // The page's own files, and nothing outside its folder.
  const rel = url.pathname === '/' ? 'index.html' : decodeURIComponent(url.pathname.slice(1));
  const file = path.resolve(VIEW, rel);
  if (!file.startsWith(VIEW + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
  fs.createReadStream(file).pipe(res);
}
// The feed: the whole snapshot again, as the real feed's first message gives it, each time the clock moves on.
function push() {
  const msg = `event: snapshot\ndata: ${JSON.stringify(story.tl.snapshot(now()))}\n\n`;
  for (const res of feeds) res.write(msg);
}

const sleep = (ms) => new Promise((r) => { setTimeout(r, ms); });
const until = async (t) => { while (now() < t) await sleep(40); };

// A recording of the page: screenshots as fast as they come, each held for the wall time until the next, made into
// <name>.mp4 at 30 frames a second. (Puppeteer's screencast holds a stale first frame while the page is still.)
// With length, the shots' times are scaled so the clip lasts exactly length seconds: a beat's clicks take longer on a
// busy machine, and the composition cuts each beat at a fixed time, so a clip of any other length loses its end.
function record(page, name, length) {
  const dir = fs.mkdtempSync(path.join(OUT, `.${name}-`));
  const shots = [];
  let stopped = false;
  const loop = (async () => {
    while (!stopped) {
      const at = Date.now(), file = path.join(dir, `${String(shots.length).padStart(5, '0')}.png`);
      await page.screenshot({ path: file });
      shots.push({ file, at });
    }
  })();
  const marks = {};
  return {
    // A moment of the clip by name (mark(name) as it happens), written to <name>.json at stop as the clip's seconds.
    mark(m) { marks[m] = Date.now(); },
    async stop() {
      stopped = true;
      await loop;
      const end = Date.now();
      const k = length ? (length * 1000) / (end - shots[0].at) : 1;
      if (Object.keys(marks).length) {
        fs.writeFileSync(path.join(OUT, `${name}.json`), `${JSON.stringify(Object.fromEntries(Object.entries(marks).map(([m, at]) => [m, Math.round(((at - shots[0].at) * k) / 10) / 100])))}\n`);
      }
      const list = shots.map((s, i) => `file '${s.file}'\nduration ${((((shots[i + 1] ? shots[i + 1].at : end) - s.at) * k) / 1000).toFixed(3)}`);
      fs.writeFileSync(path.join(dir, 'list.txt'), `${list.join('\n')}\nfile '${shots[shots.length - 1].file}'\n`);
      const r = spawnSync('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', path.join(dir, 'list.txt'), '-vf', 'fps=30,format=yuv420p',
        '-c:v', 'libx264', '-crf', '16', path.join(OUT, `${name}.mp4`)], { stdio: 'inherit' });
      fs.rmSync(dir, { recursive: true, force: true });
      if (r.status !== 0) throw new Error(`ffmpeg could not make ${name}.mp4`);
    },
  };
}

// One beat: a fresh timeline and page at story second t0, recorded while act(page) runs; with length, the clip is
// fitted to that many seconds (record), which is then its section's data-duration in index.html. height: the
// window's, H unless a beat needs more.
async function beat(browser, base, name, { t0, speed = 1, tab = 'overview', scroll = null, length = 0, height = H }, act) {
  story.tl = createTimeline();
  setClock(t0, speed);
  const ctx = await browser.createBrowserContext();
  const page = await ctx.newPage();
  await page.setViewport({ width: W, height, deviceScaleFactor: 1 });
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'dark' }]);
  await page.goto(`${base}/index.html?tab=${tab}`, { waitUntil: 'networkidle2' });
  await page.waitForSelector('#grid[aria-busy="false"]');
  if (scroll) await page.evaluate((sel) => { const el = document.querySelector(sel); if (el) window.scrollTo(0, el.getBoundingClientRect().top + window.scrollY - 12); }, scroll);
  await sleep(400);
  setClock(t0, speed);
  const rec = record(page, name, length);
  // A beat that fails stops its recording first, so its own error is the one reported, not the closed page's.
  try { await act(page, rec); } catch (e) { await rec.stop().catch(() => {}); throw e; }
  await rec.stop();
  await ctx.close();
}
// A pointer drawn on the page (headless Chrome records none) glides to the element, which is then clicked, picked
// from or given a key. The page may draw the element again at each feed message, so each of these finds it afresh
// by its selector and clicks where it is, never through a handle kept from before.
async function point(page, sel) {
  await page.waitForSelector(sel, { visible: true });
  await page.$eval(sel, (e) => e.scrollIntoView({ block: 'center' }));
  await sleep(150);
  const box = await page.$eval(sel, (e) => { const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height }; });
  return glide(page, box.x + box.width / 2, box.y + box.height / 2);
}
// The pointer, an arrow with its tip on the point x, y of the window, glides there. Not a ring: over a button's words
// OCR read a ring as an at sign inside a word, and make.sh's privacy check took that for an email and wrote nothing.
// pause: the wait for the glide (a filmed beat waits in frames).
async function glide(page, x, y, pause = () => sleep(450)) {
  await page.evaluate((x, y) => {
    let p = document.getElementById('demo-pointer');
    if (!p) {
      p = document.createElement('div');
      p.id = 'demo-pointer';
      p.innerHTML = '<svg width="20" height="28" viewBox="0 0 20 28"><path d="M1 1v22l6-5 4 9 4-2-4-9h8z" fill="#facc15" stroke="#111" stroke-width="1.5" stroke-linejoin="round"/></svg>';
      Object.assign(p.style, { position: 'fixed', zIndex: 99999, width: '20px', height: '28px', pointerEvents: 'none', transition: 'left 0.35s ease, top 0.35s ease',
        left: `${x}px`, top: `${y + 160}px` });
      document.body.append(p);
    }
    requestAnimationFrame(() => { p.style.left = `${x}px`; p.style.top = `${y}px`; });
  }, x, y);
  await pause();
  return { x, y };
}
const click = async (page, sel) => { const { x, y } = await point(page, sel); await page.mouse.click(x, y); await sleep(350); };
const key = async (page, sel, k) => { await point(page, sel); await page.focus(sel); await page.keyboard.press(k); await sleep(350); };
const pick = async (page, sel, value) => { await point(page, sel); await page.select(sel, value); await sleep(400); };

// The README's Belt 3D clip, filmed frame by frame on the page's clock (frame-clock.js): each frame is 1/FPS s of the
// floor's motion whatever the machine's load, as a screencast, which drops frames when the machine is busy, was not.
// Each frame is a PNG of the Belt 3D panel alone, piped to ffmpeg.
const FPS = 30;
async function belt3d(browser, base) {
  const { from, to, speed: pace, click: aim } = BELT3D;
  story.tl = createTimeline();
  story.filmed = true;
  setClock(from, 0);
  const ctx = await browser.createBrowserContext();
  const page = await ctx.newPage();
  // Nothing is scrolled into view here: a scroll would jump in the GIF. The window is taller than the other beats',
  // so the details, which end at the floor's foot, show the card's cost under its review rounds.
  const height = 960;
  await page.setViewport({ width: W, height, deviceScaleFactor: 1 });
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'dark' }]);
  const start = Date.now();
  await page.evaluateOnNewDocument(installClock, start);
  await page.goto(`${base}/index.html?tab=belt3d`, { waitUntil: 'networkidle2' });
  // Each frame's snapshot, its times read from the page's clock (timeline.js counts them back from Date.now).
  const snapshot = (t, at) => {
    const wall = Date.now;
    Date.now = () => at;
    try { return JSON.stringify(story.tl.snapshot(t)); } finally { Date.now = wall; }
  };
  let pipe = null, clip = null;
  const shoot = async () => {
    const png = await page.screenshot({ type: 'png', clip });
    if (!pipe.stdin.write(png)) await new Promise((r) => { pipe.stdin.once('drain', r); });
  };
  const f = film(page, { fps: FPS, start, t0: from, speed: pace, snapshot, shoot });
  // The page loads its floor (three.js) on the wall's time; it is stepped until the floor is drawn, then a second more.
  for (let i = 0; !(await page.$('#grid[aria-busy="false"] #panel-belt3d canvas')); i += 1) {
    if (i > 200) throw new Error('belt3d: the floor was not drawn');
    await f.warm(1 / FPS);
    await sleep(50);
  }
  await f.warm(1);
  // The panel's box, in even pixels (the clip's video wants them), within the window.
  clip = await page.$eval('#panel-belt3d', (e, h) => {
    const r = e.getBoundingClientRect(), y = Math.max(0, Math.floor(r.y)), x = Math.max(0, Math.floor(r.x));
    return { x, y, width: Math.floor(r.width / 2) * 2, height: Math.floor((Math.min(h, r.bottom) - y) / 2) * 2 };
  }, height);
  pipe = spawn('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'png', '-i', '-',
    '-vf', 'format=yuv420p', '-c:v', 'libx264', '-crf', '10', path.join(OUT, 'belt3d.mp4')], { stdio: ['pipe', 'inherit', 'inherit'] });
  const done = new Promise((r) => { pipe.on('close', r); });
  const wait = (sec) => () => f.wait(sec);
  try {
    await f.until(aim.at - 0.6 * pace);
    // A lane's labels are its name, its status, then one mark a pad (Build, Review, Fix, ...), each over its pad.
    const pad = await page.evaluate((n) => {
      let el = document.querySelector(`#panel-belt3d .b3-nm[data-issue="${n}"]`);
      for (let i = 0; el && i < 4; i += 1) el = el.nextElementSibling;
      const r = el && el.classList.contains('b3-mk') ? el.getBoundingClientRect() : null;
      return r && (r.x || r.y) ? { x: r.x + r.width / 2, y: r.y + r.height / 2 } : null;
    }, aim.issue);
    if (!pad) throw new Error(`belt3d: no Fix pad of #${aim.issue} on the floor at story second ${f.story().toFixed(1)}`);
    await glide(page, pad.x, pad.y, wait(0.45));
    await page.mouse.click(pad.x, pad.y);
    await f.wait(2 / FPS);
    if (!(await page.$('#panel-belt3d .b3-detail.open'))) throw new Error('belt3d: the click opened no details');
    // A lane that moved as the click came (a card landing) opens another card's details.
    const shown = await page.$eval('#panel-belt3d .b3-detail h2', (e) => e.textContent);
    if (!shown.includes(`#${aim.issue}`)) throw new Error(`belt3d: the click opened ${shown}, not #${aim.issue}`);
    f.mark('open');
    await f.wait(aim.openSec);
    const x = await page.$eval('#panel-belt3d .b3-detail .b3-close', (e) => { const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
    await glide(page, x.x, x.y, wait(0.45));
    // Marked as the × is clicked, the last moment the details are surely open.
    f.mark('close');
    await page.mouse.click(x.x, x.y);
    await f.wait(2 / FPS);
    if (await page.$('#panel-belt3d .b3-detail.open')) throw new Error('belt3d: the × did not close the details');
    await glide(page, x.x, x.y + 200, wait(0.45));
    await f.until(to);
  } finally {
    pipe.stdin.end();
    await done;
    story.filmed = false;
  }
  if (pipe.exitCode !== 0) throw new Error('ffmpeg could not make belt3d.mp4');
  fs.writeFileSync(path.join(OUT, 'belt3d.json'), `${JSON.stringify(f.marks)}\n`);
  await ctx.close();
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const server = http.createServer(serve);
  await new Promise((r) => { server.listen(0, '127.0.0.1', r); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const ticker = setInterval(() => { if (story.tl && !story.filmed) push(); }, 250);
  // --password-store=basic: Chrome never asks the desktop's keyring, which can hang a headless start. --no-sandbox:
  // Linux hosts that refuse unprivileged user namespaces (Ubuntu 23.10 and later) give Chrome no sandbox; it opens
  // only this script's own page on 127.0.0.1, as the hyperframes render does.
  const browser = await puppeteer.launch({ headless: true, args: ['--password-store=basic', '--no-first-run', '--no-sandbox', `--window-size=${W},${H}`] });
  try {
    if (process.env.DEMO_SHOT) {
      // A still of one tab at one story second, to check the timeline: DEMO_SHOT=<tab>:<t> node capture-board.js <dir>
      const [tab, t] = process.env.DEMO_SHOT.split(':');
      story.tl = createTimeline(); setClock(Number(t), 0);
      const page = await browser.newPage();
      await page.setViewport({ width: W, height: H });
      await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: 'dark' }]);
      await page.goto(`${base}/index.html?tab=${tab}`, { waitUntil: 'networkidle2' });
      await sleep(1500);
      await page.screenshot({ path: path.join(OUT, `shot-${tab}-${t}.png`), fullPage: true });
      return;
    }
    // 4. Overview: the cards move along the belt, the counters tick, #42 lands and its commit appears.
    await beat(browser, base, 'beat4', { t0: -1, speed: 1, scroll: '#panel-belt' }, async () => { await until(8.5); });
    // 5. #41's detail: review 1 finds a P1, the fix round runs, review 2 is clean, it lands. The page can trail the
    // story clock on a busy machine, so the clip ends only once the page shows #41 landed.
    await beat(browser, base, 'beat5', { t0: 0, speed: 2, scroll: '#panel-belt', length: 8.5 }, async (page) => {
      await page.evaluate(() => {
        const row = Array.from(document.querySelectorAll('#panel-belt .rows > li')).find((li) => li.textContent.includes('#41'));
        const d = row && row.querySelector('details.track-detail');
        if (d) d.open = true;
      });
      await until(16.5);
      await page.waitForFunction(() => (document.querySelector('#panel-landed') || {}).textContent?.includes('#41'), { timeout: 20000 });
      await sleep(500);
    });
    // 6. Needs you: #44 is blocked with its work kept; Retry (two clicks) and it is back on the belt.
    await beat(browser, base, 'beat6', { t0: 2, speed: 0.6, length: 6 }, async (page) => {
      await sleep(1200);
      await click(page, '#panel-needs [data-act="retry"]');
      await click(page, '#panel-needs [data-act="retry"]');
      await sleep(1500);
      await point(page, '#panel-belt .panel-title');
      await sleep(1800);
    });
    // 7. The controls: the cards-at-once setting changed, here to 6 (three clicks up), and the builder model
    // switched (both are on the Rules tab in this Board), then on the Control tab an issue held, then released (the
    // arrow keys on its card).
    await beat(browser, base, 'beat7', { t0: 3, speed: 0.3, tab: 'rules', length: 9.5 }, async (page) => {
      await sleep(300);
      for (let i = 0; i < 3; i += 1) await click(page, '[data-act="cards at once-up"]');
      await pick(page, '[data-act="builder-model"]', 'claude-opus-5-5');
      await click(page, '[data-act="builder-save"]');
      await sleep(300);
      await click(page, '#tab-control');
      await sleep(500);
      await key(page, '.bcard[data-issue="45"]', 'ArrowLeft');
      await sleep(900);
      await key(page, '.bcard[data-issue="45"]', 'ArrowRight');
      await sleep(900);
    });
    // 8. Rules: P2 off (two clicks: it would skip queued issues) and on again, follow-ups on.
    await beat(browser, base, 'beat8', { t0: 3, speed: 0.3, tab: 'rules', length: 6 }, async (page) => {
      await sleep(300);
      await click(page, '[data-act="rule-P2"]');
      await click(page, '[data-act="rule-P2"]');
      await sleep(900);
      await click(page, '[data-act="rule-P2"]');
      await sleep(600);
      await click(page, '[data-act="rule-followups"]');
      await sleep(1000);
    });
    // 9. Tests: each file's CPU s, median, last runs and status. The file over its budget opens to its runs and budget,
    // and Explain the slowdown runs and shows its answer; then Judge this test runs on a second file and shows its
    // verdict (timeline.js TEST_ANSWERS).
    const row = (f) => `tr.tests-row[data-file="${f}"] [data-act="open"]`;
    const opened = (f, sel) => `tr.tests-open[data-file="${f}"] ${sel}`;
    await beat(browser, base, 'tests', { t0: 3, speed: 1, tab: 'tests', length: 11 }, async (page) => {
      await sleep(1500);
      for (const [how, file] of Object.entries(TEST_ANSWERS).map(([how, a]) => [how, a.file])) {
        await click(page, row(file));
        await sleep(600);
        // Explain the slowdown is in the row's More menu; Judge is on the row.
        if (how === 'explain') { await click(page, opened(file, '[data-act="more"]')); await sleep(400); }
        await click(page, opened(file, `[data-act="${how}"]`));
        await page.waitForSelector(opened(file, '.tests-box .tests-result'), { timeout: 20000 });
        await point(page, opened(file, '.tests-out'));
        await sleep(1500);
      }
    });
    // The README's Belt 3D GIF (timeline.js BELT3D): the floor from story second from to to. At click the pointer
    // clicks #41's lane on its Fix pad, after review 1's finding; its details (six steps and times, review rounds,
    // cost) stay open openSec seconds, then close by their × and the belt goes on. The clip's seconds the details were
    // open (open, close) go to belt3d.json, where make.sh (belt3d-gif.sh) reads those frames.
    await belt3d(browser, base);
  } finally {
    clearInterval(ticker);
    for (const res of feeds) res.end();
    await browser.close();
    server.close();
  }
}
main().catch((e) => { console.error(e); process.exit(1); });
