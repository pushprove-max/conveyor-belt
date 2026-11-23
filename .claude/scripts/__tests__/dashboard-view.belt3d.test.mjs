// SPDX-License-Identifier: Apache-2.0
// The dashboard page's Belt 3D panel: the factory floor. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { VIEW, T0, STORE, iso, clone, css, BELT3D_IDS, OVERVIEW, boot, panel, state, order, settle, deliver, next, tick, full, tabBtn, trackOf, fig, cases } from './dashboard-view.helpers.mjs';

// A page of the repository (a name with no folder is a page of docs/), its bold marks taken out and its lines joined. Defined in
// this file, not in the helpers: the bug check puts only the card's test files on main's code, where a new helper is missing.
const guide = (name) => fs.readFileSync(new URL(`../../../${name.includes('/') ? name : `docs/${name}`}`, import.meta.url), 'utf8').replace(/\*\*/g, '').replace(/\s+/g, ' ');
const test = cases(import.meta.url);

// ---- the floor is three.js's, which jsdom cannot run; a stand-in takes each frame the panel hands it ----
// `webgl`: the browser gives a WebGL context. The stand-in keeps every frame, as plain data, in w.scene3d.frames.
const SCENE3D = (webgl = true) => `HTMLCanvasElement.prototype.getContext = function (k) { return ${webgl} && /webgl/.test(k) ? {} : null; };
  window.DASH_BELT3D_SCENE = { createScene(o) { const s = { o, frames: [], frame(st) { s.frames.push({ motion: st.motion, open: st.open,
    rows: st.rows.map((r) => ({ key: r.key, stuck: r.stuck, live: r.live, hot: r.hot, at: r.at, steps: r.steps.slice(), back: r.back,
      label: [r.label.textContent, r.label.className] })),
    cards: st.cards.map((c) => ({ key: c.key, kind: c.kind, row: c.row, at: c.at, bay: c.bay, slot: c.slot, badge: [c.badge.textContent, c.badge.className] })) }); return s.still === true; },
    resized: [], resize() { s.resized.push(document.fullscreenElement ? 'full screen' : document.querySelector('.panel.b3-fill') ? 'window' : 'in its place'); } };
    window.scene3d = s; return s; } };`;
// The browser's Fullscreen API: w.fsAsked keeps each element asked for full screen (null: asked to leave it), and
// w.fsEl is the element full screen. Without it jsdom has none, as a browser that offers no full screen.
const FULLSCREEN = `{ document.fullscreenEnabled = true; window.fsEl = null; window.fsAsked = [];
  Object.defineProperty(document, 'fullscreenElement', { configurable: true, get: () => window.fsEl });
  const to = (el) => { window.fsEl = el; document.dispatchEvent(new Event('fullscreenchange')); return Promise.resolve(); };
  Element.prototype.requestFullscreen = function () { window.fsAsked.push(this); return to(this); };
  document.exitFullscreen = function () { window.fsAsked.push(null); return to(null); }; }`;
// Runs the frames the page asked for, `n` times, `ms` apart.
function frames(w, n = 1, ms = 16) { for (let i = 0; i < n; i += 1) { w.clock += ms; for (const f of w.frames.splice(0)) f(); } }
const last3d = (w) => JSON.parse(JSON.stringify(w.scene3d.frames[w.scene3d.frames.length - 1]));
const b3 = (w) => panel(w, 'belt3d');
const lanes = (w) => Array.from(b3(w).querySelectorAll('.b3-nm'), (el) => [Number(el.dataset.issue), el.classList.contains('bad')]);
const lane = (w, n) => {
  const i = Array.from(b3(w).querySelectorAll('.b3-nm')).findIndex((el) => el.dataset.issue === String(n));
  return i < 0 ? null : { name: b3(w).querySelectorAll('.b3-nm')[i], now: b3(w).querySelectorAll('.b3-st')[i] };
};
const shownTags = (w) => Array.from(b3(w).querySelectorAll('.b3-bc:not(.off)'), (el) => Number(el.dataset.issue));
const count = (w, k) => Number(b3(w).querySelector(`.b3-k-${k} b`).textContent);
const stepCounts = (w) => Array.from(b3(w).querySelectorAll('.b3-step'), (s) => [s.firstChild.textContent, Number(s.lastChild.textContent), s.classList.contains('z')]);
const bayHead = (w, kind) => b3(w).querySelector(`.b3-bh-${kind}`);
const BAY_KINDS = ['queued', 'waiting', 'held', 'landed'];
const runCard = (card, issue, step, over = {}) => ({ repo: 'sample', card, issue, title: `Card ${issue}`, url: null, step, stepAt: iso(T0 - 120000), landed: false, waitsOn: null, usd: null, turns: null,
  reviews: [], track: null, ...over });
function floor(over = {}) {
  const data = full();
  Object.assign(data.panels.belt3d.data, over);
  return data;
}
async function open3d(data, opt = {}) {
  const w = boot({ tab: opt.query ? null : 'belt3d', extra: SCENE3D(opt.webgl !== false) + (opt.extra || ''), reducedMotion: Boolean(opt.reducedMotion), query: opt.query || '' });
  deliver(w, data);
  await settle();
  frames(w);
  return w;
}

// Done when: with running, blocked, queued, waiting, held and landed cards in the snapshot, each shows in its lane or
// bay with its number, and the counts in the header strip match. Bug it catches: a card of one kind missing from the
// floor, in the wrong lane or bay, or counted in the header but not shown (or shown and not counted).
test('belt3d: each card is in its lane or bay with its number, and the header strip counts what the floor shows', async () => {
  const w = await open3d(full());
  assert.deepEqual(lanes(w), [[63, false], [5, false], [9, false], [12, true], [13, true]], 'a lane a running card, then a red lane a stuck card');
  const f = last3d(w);
  assert.deepEqual(f.rows.map((r) => [r.key, r.stuck, r.live]), [['sample:c3-63', false, true], ['widgetshop:c4-5', false, true], ['sample:c7-9', false, true], ['sample:c1-12', true, false], ['sample:c2-13', true, false]]);
  assert.deepEqual(f.rows.map((r) => r.at), [1, 0, 3, 0, 3], 'each crate on the step it is in; a blocked card on the step that failed');
  assert.deepEqual(f.rows[0].steps, ['done', 'now', 'done', 'todo', 'todo', 'todo'], 'each pad as the track says');
  const where = (k) => { const c = f.cards.find((x) => x.key === k); return c.row !== null ? ['lane', c.row] : c.bay !== null ? ['bay', c.bay, c.slot] : null; };
  assert.deepEqual(['sample#20', 'sample#21', 'sample#24', 'sample#76', 'sample:c5-7', 'sample:c6-8'].map(where),
    [['bay', 0, 0], ['bay', 0, 1], ['bay', 1, 0], ['bay', 2, 0], ['bay', 3, 0], ['bay', 3, 1]], 'queued, waiting, held and just landed, each in its own bay, in order');
  assert.deepEqual(shownTags(w).sort((a, b) => a - b), [7, 8, 20, 21, 24, 76], 'every bay card has its number beside its crate; no lane card has a bay tag');
  for (const [n, title] of [[20, 'Next up'], [24, 'Second half'], [76, 'Split the PROD stack'], [7, 'Landed one']]) {
    const tag = b3(w).querySelector(`.b3-bc[data-issue="${n}"]`);
    assert.deepEqual([tag.querySelector('b').textContent, tag.querySelector('.b3-t span').textContent], [`#${n}`, title]);
  }
  assert.equal(b3(w).querySelector('.b3-bc[data-issue="24"] .b3-s').textContent, 'waits on #20, queued', 'a waiting card says what it waits on and where that is');
  // The header strip: every state's count is the number of its lanes or bay cards.
  assert.deepEqual(['run', 'blocked', 'queued', 'waiting', 'held', 'landed'].map((k) => count(w, k)), [3, 2, 2, 1, 1, 2]);
  assert.equal(count(w, 'run'), lanes(w).filter((l) => !l[1]).length);
  assert.equal(count(w, 'blocked'), lanes(w).filter((l) => l[1]).length);
  BAY_KINDS.forEach((k, j) => assert.equal(count(w, k), f.cards.filter((c) => c.bay === j).length, `${k}: the count is its bay's cards`));
  BAY_KINDS.forEach((k) => assert.equal(Number(bayHead(w, k).querySelector('b').textContent), count(w, k), `${k}: the bay's head says the same`));
  assert.deepEqual(stepCounts(w), [['Build', 1, false], ['Review', 1, false], ['Fix', 0, true], ['Test', 1, false], ['Land', 0, true], ['Push', 0, true]], 'all six steps, zeros dimmed');
});

// Bug it catches: a held issue with a Depends on line read as queued: it left the Held bay for "Waiting on a card", or sat in
// Held with nothing saying what it waits on (dashboard.sh gives it in held, with its waitsFor).
test('belt3d: a held issue that waits on another stays in the Held bay and says "waits on #N"', async () => {
  const data = full();
  data.panels.belt3d.data.queue.held = [{ repo: 'sample', issue: 77, title: 'Held and waits', url: null, waitsFor: [20] }];
  const w = await open3d(data);
  const c = last3d(w).cards.find((x) => x.key === 'sample#77');
  assert.equal(c.bay, BAY_KINDS.indexOf('held'), 'in the Held bay');
  assert.deepEqual([count(w, 'held'), count(w, 'waiting')], [1, 1], 'counted as held; Waiting keeps only its own card');
  assert.equal(b3(w).querySelector('.b3-bc[data-issue="77"] .b3-s').textContent, 'held on the Board, waits on #20', 'it says what it waits on');
  // Bug it catches: its details promised "It starts when someone releases it.", false while #20 is open (or a rule
  // skips it): releasing it is needed, not enough.
  w.scene3d.o.pick('sample#77');
  const ps = Array.from(b3(w).querySelectorAll('.b3-detail p'), (p) => p.textContent);
  assert.ok(ps.includes('Held on the Board. Conveyor does not pick it until someone releases it.'), ps.join(' | '));
  assert.ok(ps.some((t) => t.startsWith('Waits on #20')), ps.join(' | '));
  assert.ok(!ps.some((t) => /starts when/.test(t)), 'no promise that releasing it starts it');
});

// Bug it catches: a long queue spilling crates past its bay, or a bay that shows three and hides that there are more.
test('belt3d: a bay shows its first three cards and says how many there are', async () => {
  const data = full();
  data.panels.belt3d.data.queue.next = [20, 21, 22, 23].map((n) => ({ repo: 'sample', issue: n, title: `Issue ${n}`, url: null }));
  const w = await open3d(data);
  assert.equal(bayHead(w, 'queued').textContent, 'Queued43 shown');
  assert.deepEqual(last3d(w).cards.filter((c) => c.bay === 0).map((c) => [c.key, c.slot]), [['sample#20', 0], ['sample#21', 1], ['sample#22', 2]]);
  assert.ok(b3(w).querySelector('.b3-bc[data-issue="23"]').classList.contains('off'), 'the fourth is not drawn');
  assert.deepEqual(Array.from(b3(w).querySelectorAll('.b3-bc[data-issue="20"] .b3-s, .b3-bc[data-issue="22"] .b3-s'), (s) => s.textContent), ['next up', '3rd in line']);
});

// Bug it catches: a queue whose issues were not listed (dashboard.sh gives `queue: null`, or a list of it null) counted
// as 0 queued, 0 waiting and 0 held, or a floor with nothing else on it called empty.
test('belt3d: an unread queue is counted as unknown, never as zero', async () => {
  const w = await open3d(floor({ queue: null }));
  for (const k of ['queued', 'waiting', 'held']) {
    assert.equal(b3(w).querySelector(`.b3-k-${k} b`).textContent, '—', `${k}: the header says the count is unknown`);
    assert.equal(bayHead(w, k).querySelector('b').textContent, '—', `${k}: so does its bay`);
  }
  assert.deepEqual(['run', 'blocked', 'landed'].map((k) => count(w, k)), [3, 2, 2], 'the counts that were read stay');
  const part = await open3d(floor({ queue: { next: null, held: [], waiting: [] } }));
  assert.deepEqual(['queued', 'waiting', 'held'].map((k) => b3(part).querySelector(`.b3-k-${k} b`).textContent), ['—', '0', '0'], 'only the list not read is unknown');
  const bare = await open3d(floor({ belt: [], needs: [], landed: [], queue: null }));
  assert.notEqual(state(bare, 'belt3d'), 'empty', 'a floor whose queue was not read is not called empty');
  assert.equal(count(bare, 'run'), 0);
  assert.equal(b3(bare).querySelector('.b3-k-queued b').textContent, '—');
});

// Done when: a running card in Test with track.tests shows "<done>/<of>" and its bar; a blocked card shows its reason.
// Bug it catches: the test run's progress or the reason a card is stuck missing from its lane.
test('belt3d: a card in Test shows its cases run and their bar, else its files, else its time; a stuck card its reason', async () => {
  const w = await open3d(full());
  const t = lane(w, 9).now;
  assert.equal(t.querySelector('.b3-l1').textContent, 'Test 142/205');
  assert.ok(t.classList.contains('tests') && !t.classList.contains('fail'), 'the bar is shown');
  assert.equal(t.querySelector('.b3-pbar i').style.transform, 'scaleX(0.693)', '142 of 205');
  const stuck = lane(w, 13).now;
  assert.ok(stuck.classList.contains('bad'));
  assert.deepEqual([stuck.querySelector('.b3-l1').textContent, stuck.querySelector('.b3-why').textContent], ['Stuck at Test', 'tests failed twice']);
  assert.deepEqual([lane(w, 12).now.querySelector('.b3-l1').textContent, lane(w, 12).now.querySelector('.b3-why').textContent], ['Waiting for your yes', 'Visible change: Staff see a new button.']);
  assert.equal(lane(w, 63).now.querySelector('.b3-why').textContent, '', 'a running card has no reason');
  // Failed cases turn the bar red; with no case count the files fill it; with neither, the time in the step.
  const track = (tests, files) => ({ steps: trackOf('++->..', 'tests').steps, at: 3, since: iso(T0 - 120000), tests, files });
  next(w, floor({ belt: [runCard('c1-1', 1, 'tests', { track: track({ done: 50, of: 200, failed: 2 }, null) }), runCard('c2-2', 2, 'tests', { track: track(null, { run: 1, of: 4 }) }),
    runCard('c3-3', 3, 'tests', { track: track(null, null) })] }));
  assert.equal(lane(w, 1).now.querySelector('.b3-l1').textContent, 'Test 50/200, 2 failed');
  assert.ok(lane(w, 1).now.classList.contains('fail'));
  assert.deepEqual([lane(w, 2).now.querySelector('.b3-l1').textContent, lane(w, 2).now.querySelector('.b3-pbar i').style.transform], ['Test files 1/4', 'scaleX(0.25)']);
  assert.equal(lane(w, 3).now.querySelector('.b3-l1').textContent, 'Test · 2 min');
  assert.ok(!lane(w, 3).now.classList.contains('tests'), 'no bar with nothing counted');
  tick(w, 60000);
  assert.equal(lane(w, 3).now.querySelector('.b3-l1').textContent, 'Test · 3 min', 'the time moves on each second, in place');
});

// Issue 433. Bug it catches: a card running its test files one at a time read "Test 25/25, 3 failed" with a full bar
// (the cases of the files that had ended, taken as the whole) and named no file, so a slow file and a hung run looked
// the same; and the Test step's time was all its runs' added up. Its third run, given 3 files, 2 min into the second:
// the lane says "file 2 of 3: <name>, 2 min", the failed count, its bar at 1/3, no "Test n/n"; its details give this
// run's time and, apart, all three runs' time (an hour before it, and these 2 min).
test('belt3d: a card running its test files one at a time shows the file that runs, which of how many and its time; its third run apart from all', async () => {
  const w = await open3d(full());
  const steps = trackOf('++->..', 'tests').steps.map((s, i) => (i === 3 ? { ...s, n: 3, sec: 3600 } : s));
  const files = { run: 1, of: 3, now: { file: 'conveyor/tests/b.test.sh', at: iso(T0 - 120000) } };
  next(w, floor({ belt: [runCard('c1-1', 1, 'tests', { track: { steps, at: 3, since: iso(T0 - 120000), tests: { done: 25, of: 25, failed: 3 }, files } })] }));
  const t = lane(w, 1).now;
  assert.deepEqual([t.querySelector('.b3-l1').textContent, t.querySelector('.b3-pbar i').style.transform], ['file 2 of 3: b.test.sh, 2 min, 3 failed', 'scaleX(0.333)']);
  assert.ok(t.classList.contains('fail'), 'failed cases turn the bar red');
  // Issue 1430: the phone's list showed the step and its time alone, not the file that runs.
  assert.equal(b3(w).querySelector('.b3-row .b3-row-step').textContent, 'Test · file 2 of 3: b.test.sh, 2 min, 3 failed');
  // Issue 1362: the lane has the file's name only (the whole path ran past the slab); the tooltip and the details keep the path.
  w.scene3d.o.hover('sample:c1-1', 200, 120);
  assert.ok(b3(w).querySelector('.b3-tip').textContent.includes('file 2 of 3: conveyor/tests/b.test.sh, 2 min'), 'the tooltip holds the whole path');
  w.scene3d.o.pick('sample:c1-1');
  const box = b3(w).querySelector('.b3-detail');
  assert.equal(box.querySelectorAll('.b3-six li')[3].querySelector('em').textContent, '2 min so far · 3rd run, 1 h 02 min in all');
  assert.ok(box.textContent.includes('file 2 of 3: conveyor/tests/b.test.sh, 2 min, 3 failed') && !/\b25 of 25\b|Test 25\/25/.test(box.textContent), box.textContent);
  // Bug (#1436): the Belt 3D guide said nothing of the short name in the lane and the whole path in the tooltip and the details, as above.
  assert.ok(guide('conveyor/README.md').includes('its lane names the file by its short name: hover over the card or click it to see the full path'), 'the guide names the short name and where the path shows');
});

// Issue 1362. Bug it catches: the details of an issue that waits on a card in its test run showing that card's file by
// name only (the short text is for the lane alone).
test('belt3d: the details of a held issue give the whole test file path of the card it waits on', async () => {
  const file = '.claude/scripts/__tests__/dashboard-view.health.test.mjs';
  const files = { run: 4, of: 6, now: { file, at: iso(T0 - 120000) } };
  const w = await open3d(floor({
    belt: [runCard('c20-1', 20, 'tests', { track: { steps: trackOf('++->..', 'tests').steps, at: 3, since: iso(T0 - 120000), tests: null, files } })],
    queue: { next: null, waiting: [], held: [{ repo: 'sample', issue: 77, title: 'Held and waits', url: null, waitsFor: [20] }] },
  }));
  w.scene3d.o.pick('sample#77');
  const ps = Array.from(b3(w).querySelectorAll('.b3-detail p'), (p) => p.textContent);
  assert.ok(ps.some((t) => t.includes(`file 5 of 6: ${file}, 2 min`)), ps.join(' | '));
});
// Issue 1362: a long status line, or the "went back" line, ran past the slab, and the tests bar was drawn over the
// middle of the status text. jsdom does no layout: the rules that cut the text and place the bar are read from the
// computed styles of app.css, loaded into the page. Bug it catches: any of the three rules missing.
test('belt3d: the status text and the "went back" line end in "…" inside the slab, and the tests bar is a line under the text', async () => {
  const w = await open3d(full());
  const st = w.document.createElement('style'); st.textContent = css; w.document.head.append(st);
  const files = { run: 4, of: 6, now: { file: 'dashboard-view.health.test.mjs', at: iso(T0 - 120000) } };
  next(w, floor({ belt: [runCard('c1-1', 1, 'tests', { track: { steps: trackOf('++->..', 'tests').steps, at: 3, since: iso(T0 - 120000), tests: null, files } })] }));
  // jsdom spells a zero minimum "0" or "0px".
  const now = lane(w, 1).now, cut = (el) => { const c = w.getComputedStyle(el); return [c.overflow, c.textOverflow, /^0(px)?$/.test(c.minWidth) ? '0' : c.minWidth]; };
  assert.deepEqual(cut(now.querySelector('.b3-l1 span')), ['hidden', 'ellipsis', '0'], 'the status text');
  assert.deepEqual(cut(now.querySelector('.b3-ret')), ['hidden', 'ellipsis', '0'], 'the "went back" line');
  const bar = now.querySelector('.b3-pbar'), kids = Array.from(now.children);
  assert.notEqual(w.getComputedStyle(bar).position, 'absolute', 'the bar is in the flow, not drawn over the text');
  assert.ok(kids.indexOf(bar) > kids.indexOf(now.querySelector('.b3-l1')), 'the bar comes after the status text');
});

// Issue 423: a card that went back a step is amber between the two steps. What its lane shows: the way back the scene
// draws (amber from the step it went back to to the one it left, the ghost on the one it left), "← back to <step>", its
// crate's round badge, and its status's second line with the time in ET.
const backOn = (w, n, key) => {
  const f = last3d(w), r = f.rows.find((x) => x.key === key), c = f.cards.find((x) => x.key === key), now = lane(w, n).now;
  return { way: r.back, label: r.label, badge: c.badge, status: [now.querySelector('.b3-l1').textContent, now.querySelector('.b3-ret').textContent] };
};
// Records (name and at, as dashboard.sh cuts them) at the minutes before T0 (12:00 ET) given.
const recs = (...r) => r.map(([name, min]) => ({ name, at: min === null ? null : iso(T0 - min * 60000) }));
// Bug it catches: a card back in Review after its fix only jumped back, "Review 2" in its status the one hint.
test('belt3d: a card gone Review 1, Fix 1, Review 2 is amber from Review to Fix, "← back to Review", its badge 2 and when it went back', async () => {
  const w = await open3d(full());
  assert.deepEqual(backOn(w, 63, 'sample:c3-63'), { way: { from: 2, to: 1 }, label: ['← back to Review', 'b3-lb b3-bk'], badge: ['2', 'b3-lb b3-rd'],
    status: ['Review 2 · 5 min', '← went back from Fix at 11:55 AM ET'] });
  // A card that has not gone back has none of it.
  assert.deepEqual(backOn(w, 9, 'sample:c7-9'), { way: null, label: ['', 'b3-lb b3-bk off'], badge: ['', 'b3-lb b3-rd off'], status: ['Test 142/205', ''] });
});
// Bug it catches: failed tests sent back to a fix shown as a plain Fix.
test('belt3d: a card whose tests failed and is in Fix 2 is amber from Fix to Test, "← back to Fix", its badge 2 and when it went back', async () => {
  const steps = trackOf('++>+..', 'fix after failed tests').steps;
  steps[1].n = 2; steps[2].n = 2; steps[3].state = 'todo'; steps[3].sec = 40;
  const track = { steps, at: 2, since: iso(T0 - 120000), tests: null, files: null,
    records: recs(['building', 50], ['review 1 (NO-GO)', 40], ['fix 1', 30], ['review 2 (GO)', 20], ['tests failed', 2], ['fix after failed tests', null]) };
  const w = await open3d(floor({ belt: [runCard('c8-8', 8, 'fix', { track })] }));
  assert.deepEqual(backOn(w, 8, 'sample:c8-8'), { way: { from: 3, to: 2 }, label: ['← back to Fix', 'b3-lb b3-bk'], badge: ['2', 'b3-lb b3-rd'],
    status: ['Fix 2 · 2 min', '← went back from Test at 11:58 AM ET'] });
});
// Issue 650: a fix the Done-when check on the build's reply started (replyCheck) is Build's. Bug it catches: the review
// after it read as a step back from Fix ("← went back from Fix"), and its lane said Fix while it ran.
test('belt3d: a reply-check fix after the build is drawn on Build, and the review after it is no step back', async () => {
  const running = trackOf('>.....', 'fix after review 0').steps;
  running[0].replyFix = 'now';
  const reviewing = trackOf('+>....', 'review 1 of 3').steps;
  reviewing[0].replyFix = 'done';
  const fixRec = { name: 'fix 1', at: iso(T0 - 5 * 60000), replyCheck: true };
  const w = await open3d(floor({ belt: [
    runCard('c8-8', 8, 'fix', { track: { steps: running, at: 0, since: iso(T0 - 120000), tests: null, files: null, records: recs(['building', 10], ['fix after review 0', null]) } }),
    runCard('c9-9', 9, 'review', { track: { steps: reviewing, at: 1, since: iso(T0 - 120000), tests: null, files: null, records: [...recs(['building', 10]), fixRec, ...recs(['review 1 of 3', null])] } })] }));
  assert.deepEqual(backOn(w, 8, 'sample:c8-8').status, ['Build · reply check fix · 2 min', '']);
  assert.deepEqual(backOn(w, 9, 'sample:c9-9'), { way: null, label: ['', 'b3-lb b3-bk off'], badge: ['', 'b3-lb b3-rd off'], status: ['Review 1 · 2 min', ''] });
  w.scene3d.o.pick('sample:c9-9');
  assert.deepEqual(Array.from(b3(w).querySelectorAll('.b3-detail .b3-six li'), (li) => [li.className, li.childNodes[1].textContent]),
    [['s-done', 'Build · reply check fixed'], ['s-now', 'Review 1'], ['s-todo', 'Fix'], ['s-todo', 'Test'], ['s-todo', 'Land'], ['s-todo', 'Push']]);
});
// Issue 261 (track.jq lintFix). Bug it catches: the 3D belt named the review gate's lint fix "Build" or a Fix round,
// and the landing gate's a bare "Fix 2", unlike the flat Board.
test('belt3d: a lint fix is named "Build · lint fix" at the review gate and "Fix N: lint findings" at the landing gate', async () => {
  const review = trackOf('>.....', 'fix after review 0').steps;
  review[0].lintFix = 'now';
  const land = trackOf('++>...', 'fix after review 1').steps;
  Object.assign(land[2], { n: 2, lintFix: 'now' });
  // The review gate's lint fix after a rebuild is Land's: it read as a plain "Land".
  const rebuilt = trackOf('++-+>.', 'rebuilding after a conflict').steps;
  rebuilt[4].lintFix = 'now';
  const w = await open3d(floor({ belt: [
    runCard('c7-7', 7, 'fix', { track: { steps: rebuilt, at: 4, since: iso(T0 - 120000), tests: null, files: null, records: recs(['building', 10], ['rebuild', 10], ['fix after review 1', null]) } }),
    runCard('c8-8', 8, 'fix', { track: { steps: review, at: 0, since: iso(T0 - 120000), tests: null, files: null, records: recs(['building', 10], ['fix after review 0', null]) } }),
    runCard('c9-9', 9, 'fix', { track: { steps: land, at: 2, since: iso(T0 - 120000), tests: null, files: null, records: recs(['building', 10], ['review 1 (GO)', 10], ['fix after review 1', null]) } })] }));
  assert.equal(backOn(w, 8, 'sample:c8-8').status[0], 'Build · lint fix · 2 min');
  assert.equal(backOn(w, 9, 'sample:c9-9').status[0], 'Fix 2: lint findings · 2 min');
  assert.equal(backOn(w, 7, 'sample:c7-7').status[0], 'Land · lint fix · 2 min');
});
// Bug it catches: the amber marks left on a card that has moved on, past the step it went back from; and the marks
// gone when it is only back at that step (Review 2 a NO-GO, the card in Fix 2), not past it.
test('belt3d: once the card moves on past the step it went back from, its amber marks are gone', async () => {
  const w = await open3d(full());
  const fix = full(), f = fix.panels.belt3d.data.belt[0], six = trackOf('++>...', 'fix 2').steps;
  six[1].n = 2; six[2].n = 2;
  f.step = 'fix';
  f.track = { ...f.track, steps: six, at: 2, records: recs(['building', 30], ['review 1 (NO-GO)', 15], ['fix 1', 5], ['review 2 (NO-GO)', 1], ['fix 2', null]) };
  next(w, fix);
  frames(w);
  assert.deepEqual(backOn(w, 63, 'sample:c3-63'), { way: { from: 2, to: 1 }, label: ['← back to Review', 'b3-lb b3-bk'], badge: ['2', 'b3-lb b3-rd'],
    status: ['Fix 2 · 5 min', '← went back from Fix at 11:55 AM ET'] }, 'back in Fix, not past it: the marks hold');
  const on = full(), c = on.panels.belt3d.data.belt[0];
  c.step = 'tests';
  c.track = { ...c.track, steps: trackOf('+++>..', 'tests').steps, at: 3, records: recs(['building', 30], ['review 1 (NO-GO)', 15], ['fix 1', 5], ['review 2 (GO)', 1], ['tests', null]) };
  next(w, on);
  frames(w);
  assert.deepEqual(backOn(w, 63, 'sample:c3-63'), { way: null, label: ['', 'b3-lb b3-bk off'], badge: ['', 'b3-lb b3-rd off'], status: ['Test · 5 min', ''] });
});

// Done when: a refresh with the same cards changes no element's size or the page's scroll position. Bug it catches:
// the panel built again on each refresh, or a label sized by its text, so the floor and the page jump as words change.
test('belt3d: a refresh with the same cards keeps every element, its size and the scroll; the stage grows only with a lane', async () => {
  let scrolls = 0;
  const w = await open3d(full());
  w.scrollTo = () => { scrolls += 1; };
  w.Element.prototype.scrollIntoView = () => { scrolls += 1; };
  const els = () => Array.from(b3(w).querySelectorAll('*'));
  const look = () => els().map((el) => `${el.tagName}.${el.className}|${el.getAttribute('style') || ''}`);
  const before = els(), seen = look(), depth = b3(w).querySelector('.b3-stage').style.getPropertyValue('--b3-depth');
  assert.equal(depth, String(2.6 * 5 + 12.4), 'five lanes deep');
  // The same cards: a later snapshot, one card's cost changed, and the clock on.
  const again = full();
  again.updatedAt = iso(T0);
  again.panels.belt3d.data.belt[0].usd = 1.5;
  next(w, again);
  tick(w, 1000);
  frames(w, 3);
  assert.equal(b3(w).dataset.renders, '2', 'the panel was drawn again');
  assert.deepEqual(els(), before, 'every element is the one it was');
  assert.deepEqual(look(), seen, 'with the same classes and sizes');
  assert.equal(scrolls, 0, 'nothing scrolled the page');
  assert.equal(w.scrollY, 0);
  // Every label on the floor, the header strip and the details have a fixed size, whatever their text.
  for (const sel of ['.b3-nm', '.b3-st', '.b3-bc', '.b3-sum', '.b3-detail']) {
    const rule = new RegExp(`(^|\\n|\\} )${sel.replace('.', '\\.')} \\{[^}]*\\}`).exec(css);
    assert.ok(rule && (/(^|[ ;{])height:/.test(rule[0]) || /[ ;{]bottom:/.test(rule[0])) && (/(^|[ ;{])width:/.test(rule[0]) || /inset: 0 0 auto 0/.test(rule[0])), `${sel} has a fixed size: ${rule && rule[0]}`);
  }
  assert.match(css, /\.b3-nm span \{[^}]*text-overflow: ellipsis/, 'a long title ends in "…" inside its fixed box');
  // One more running card: one more lane, and only then a deeper stage.
  const more = full();
  more.panels.belt3d.data.belt.push(runCard('c9-90', 90, 'build'));
  next(w, more);
  assert.deepEqual(lanes(w).map((l) => l[0]), [63, 5, 9, 90, 12, 13], 'a new card takes a lane after the running ones, the stuck ones still last');
  assert.equal(b3(w).querySelector('.b3-stage').style.getPropertyValue('--b3-depth'), String(2.6 * 6 + 12.4));
  // A card keeps its lane: one that leaves takes its lane with it and the others keep their order.
  const fewer = full();
  fewer.panels.belt3d.data.belt = fewer.panels.belt3d.data.belt.filter((c) => c.issue !== 5).concat([runCard('c9-90', 90, 'review')]);
  next(w, fewer);
  assert.deepEqual(lanes(w).map((l) => l[0]), [63, 9, 90, 12, 13]);
});

// Done when: hover shows the tooltip with the full title; click opens the details panel with the six steps. Bug it
// catches: a title cut short with no way to read it, or details that leave out the steps.
test('belt3d: hover shows the full title in the tooltip; a click opens the details with the six steps, beside the floor', async () => {
  const data = full(), long = `${'A long title that runs past its lane '.repeat(5)}<b>end</b>`;
  data.panels.belt3d.data.belt[0].title = long;
  const w = await open3d(data);
  const tip = b3(w).querySelector('.b3-tip');
  assert.equal(tip.hidden, true);
  assert.equal(lane(w, 63).name.querySelector('span').textContent, long, 'the lane holds the whole title; its box ends it in "…"');
  w.scene3d.o.hover('sample:c3-63', 200, 120);
  assert.equal(tip.hidden, false);
  assert.ok(tip.textContent.includes(`sample #63${long}`), tip.textContent);
  assert.ok(tip.textContent.includes('Running: Review 2 · 5 min. Click for details.'), tip.textContent);
  assert.equal(tip.querySelectorAll('b').length, 1, 'a title is text, never markup: the issue number is the one bold element');
  assert.ok(lane(w, 63).name.classList.contains('hot'), 'the hovered lane is lit');
  frames(w);
  assert.equal(last3d(w).rows[0].hot, true);
  w.scene3d.o.hover('sample#20', 10, 10);
  assert.ok(tip.textContent.includes('sample #20Next up') && b3(w).querySelector('.b3-bc[data-issue="20"]').classList.contains('hot'), 'a bay card has its tooltip too');
  w.scene3d.o.hover(null, 0, 0);
  assert.equal(tip.hidden, true);
  const box = b3(w).querySelector('.b3-detail');
  assert.ok(!box.classList.contains('open') && box.hasAttribute('inert'), 'closed, nothing in it takes the focus');
  w.scene3d.o.pick('sample:c2-13');
  assert.ok(box.classList.contains('open') && !box.hasAttribute('inert'));
  assert.deepEqual(Array.from(box.querySelectorAll('.b3-six li'), (li) => [li.className, li.childNodes[1].textContent]),
    [['s-done', 'Build'], ['s-done', 'Review'], ['s-skipped', 'Fix'], ['s-failed', 'Test'], ['s-todo', 'Land'], ['s-todo', 'Push']]);
  for (const s of ['Stuck', '#13', 'Broken build', 'Stuck at Test', '40 of 40 run, 3 failed', 'Round 1: GO', 'Stuck because', 'tests failed twice', 'Stuck for 15 min.', 'Cost so far $0.75']) {
    assert.ok(box.textContent.includes(s), `the details show "${s}": ${box.textContent}`);
  }
  frames(w);
  assert.equal(last3d(w).open, true, 'the floor makes room for the details, so they never cover the card');
  // Bug it catches: on a phone the stage is narrower than the 320px details, so beside the floor they covered it; there
  // they open below the stage (outside it, so its clipping cannot hide them) and the floor gives up no width.
  assert.ok(!b3(w).querySelector('.b3-stage').contains(box), 'the details are not inside the stage');
  assert.match(css, /\.b3-stage \{[^}]*--b3-aside: 328px;/, 'a wide panel: the floor gives the details their 320px and a gap');
  assert.match(css, /@container \(max-width: 719px\) \{\s*\.b3-stage \{ --b3-aside: 0px; \}\s*\.b3-detail \{ position: relative;[^}]*width: auto;[^}]*display: none; \}\s*\.b3-detail\.open \{ display: block; \}/,
    'a narrow panel: the details open below the floor at its width, and the floor keeps the whole stage');
  w.scene3d.o.pick('sample:c7-9');
  assert.deepEqual(Array.from(box.querySelectorAll('.b3-six em'), (e) => e.textContent), ['30 s', '31 s', 'skipped', '2 min so far', '', '']);
  for (const s of ['142 of 205 run, 0 failed', 'Round 1: GO (no findings)', 'Cost so far $0.50 · 0 turns in this step']) assert.ok(box.textContent.includes(s), `"${s}": ${box.textContent}`);
  assert.equal(box.querySelector('.b3-pb i').style.transform, 'scaleX(0.693)');
  w.scene3d.o.pick('sample:c3-63');
  assert.ok(box.textContent.includes('Round 1: NO-GO (1 P1, 2 P2)') && box.textContent.includes('Review 2'), box.textContent);
  w.scene3d.o.pick('sample#24');
  assert.ok(box.textContent.includes('Waiting on#20 Next up (Queued)'), box.textContent);
  box.querySelector('.b3-close').click();
  assert.ok(!box.classList.contains('open'));
  frames(w);
  assert.equal(last3d(w).open, false);
  // A click on nothing closes them too; a pinned card that leaves the snapshot closes them.
  w.scene3d.o.pick('sample:c2-13');
  w.scene3d.o.pick(null);
  assert.ok(!box.classList.contains('open'));
  w.scene3d.o.pick('sample:c2-13');
  next(w, floor({ needs: [] }));
  assert.ok(!box.classList.contains('open'));
});

// Bug it catches (#652): the details were drawn anew, × too, each time the card's running time changed; a × replaced
// between its press and its release lost the click (the browser gives it to the element pressed, then gone), so the
// details stayed open. The × pressed is the one still there after the redraw, and its click closes them.
test('belt3d: the details\' × pressed while the card\'s time runs on is never redrawn, and its click closes them', async () => {
  const w = await open3d(full());
  w.scene3d.o.pick('sample:c7-9');
  const box = b3(w).querySelector('.b3-detail'), x = box.querySelector('.b3-close'), was = box.textContent;
  const gone = [];
  new w.MutationObserver((ms) => ms.forEach((m) => gone.push(...m.removedNodes))).observe(box, { childList: true });
  x.dispatchEvent(new w.MouseEvent('mousedown', { bubbles: true }));
  // A minute on, the next snapshot: the card ran a turn more.
  w.clock += 60000;
  const later = full();
  later.panels.belt3d.data.belt.find((c) => c.card === 'c7-9').turns = 1;
  next(w, later);
  await settle();
  assert.notEqual(box.textContent, was, 'the running time in the details changed');
  assert.ok(!gone.includes(x) && box.querySelector('.b3-close') === x, 'the × pressed is still in the details');
  x.dispatchEvent(new w.MouseEvent('mouseup', { bubbles: true }));
  x.click();
  assert.ok(!box.classList.contains('open'));
});

// Bug it catches: cards known by their issue alone, so two branch cards (both issue 0), or a card that landed today and
// a new card of the same issue, merged into one: a lane, a landed entry and a count lost.
test('belt3d: two cards of one issue are two cards, each in its lane or bay and counted', async () => {
  const w = await open3d(floor({
    belt: [runCard('b1-0', 0, 'build'), runCard('b2-0', 0, 'review'), runCard('c9-7', 7, 'build')],
    needs: [{ repo: 'sample', card: 'b3-0', issue: 0, title: 'Branch stuck', url: null, kind: 'blocked', reason: 'tests failed', since: iso(T0 - 60000), reviews: [], usd: null, track: null }],
  }));
  assert.deepEqual(lanes(w), [[0, false], [0, false], [7, false], [0, true]]);
  assert.deepEqual([count(w, 'run'), count(w, 'blocked'), count(w, 'landed')], [3, 1, 2]);
  const f = last3d(w);
  assert.deepEqual(['sample:c9-7', 'sample:c5-7'].map((k) => { const c = f.cards.find((x) => x.key === k); return [c.row, c.bay]; }), [[2, null], [null, 3]],
    'the new card of #7 has its lane and the one landed today stays in its bay');
});

// Bug it catches: a landed card's details showing six steps done with no times, whatever its track said.
test('belt3d: a landed card\'s details show its track: a skipped step skipped, a push still to go not done, and the steps\' times', async () => {
  const data = full();
  data.panels.belt3d.data.landed[0].track = { steps: trackOf('++-++.', null).steps, at: null, since: null, tests: null, files: null };
  const w = await open3d(data);
  w.scene3d.o.pick('sample:c5-7');
  const box = b3(w).querySelector('.b3-detail');
  assert.deepEqual(Array.from(box.querySelectorAll('.b3-six li'), (li) => [li.className, li.querySelector('em').textContent]),
    [['s-done', '30 s'], ['s-done', '31 s'], ['s-skipped', 'skipped'], ['s-done', '33 s'], ['s-done', '34 s'], ['s-todo', '']]);
});

// Bug it catches: crates gliding and belts running for an owner who turned motion off.
test('belt3d: with motion off the scene is told so, and draws nothing that glides', async () => {
  const w = await open3d(full(), { reducedMotion: true });
  assert.equal(last3d(w).motion, false);
  const on = await open3d(full());
  assert.equal(last3d(on).motion, true);
});

test('belt3d: with no WebGL the panel says so in one line, keeps its counts, and the rest of the Board draws', async () => {
  const w = await open3d(full(), { webgl: false });
  assert.equal(w.scene3d, undefined, 'no scene is made');
  const note = b3(w).querySelector('.b3-note');
  assert.equal(note.hidden, false);
  assert.match(note.textContent, /^This browser gives no WebGL, so the Board cannot draw the floor\. Every other panel works as before\.$/);
  assert.equal(count(w, 'run'), 3, 'the header strip still counts');
  tabBtn(w, 'overview').click();
  for (const id of OVERVIEW) assert.equal(state(w, id), 'ready', `${id} draws`);
});

// Bug it catches: the floor's error ran its cause into the colon ("floor:boom"), as a rewrite of the text once did.
test('belt3d: when the scene fails, the panel says so with its cause after a space', async () => {
  const w = await open3d(full(), { extra: 'window.DASH_BELT3D_SCENE.createScene = () => { throw new Error("boom"); };' });
  assert.match(b3(w).querySelector('.b3-note').textContent, /^The Board could not draw the floor: boom/);
});

// Issue 421: full screen, and filling the window, the panel's header is set aside (no box, so no height) and the
// header strip is the top row, the full-screen button at its right end after the counts, ahead of the details in the
// focus order as it was in the header, and still focused if it was; out of it, the button is back first in the
// header's tools and the strip holds the counts alone. jsdom lays nothing out: the CSS rules are read here, and no test measures the
// boxes. Bug it catches: a header bar left over the floor full screen, or a button with no
// way to it once the header is gone, after the counts and over them, or left in the strip out of full screen.
function inStrip(w, btn, at, focused = true) {
  const p = b3(w), sum = p.querySelector('.b3-sum'), doc = w.document;
  assert.ok(p.classList.contains('b3-headless'), `${at}: the panel is marked headless`);
  assert.match(css, /\.panel\.b3-headless > \.panel-head \{ display: none; \}/, `${at}: the header is set aside`);
  assert.match(css, /\.panel\.b3-headless > \.panel-body \{ padding-top: 0; \}/, `${at}: the strip is at the top`);
  assert.equal(btn.parentElement, sum, `${at}: the button is in the header strip`);
  assert.equal(sum.lastElementChild, btn, `${at}: at its right end`);
  assert.ok(btn.previousElementSibling.classList.contains('b3-ks') && btn.previousElementSibling.querySelector('.b3-k-landed'), `${at}: after the counts`);
  assert.match(css, /\.b3-ks \{[^}]*min-width: 0; overflow: hidden; \}/, `${at}: the counts give way before the button`);
  assert.match(css, /\.b3-sum \.tool\.full \{ flex: none; margin-left: auto;/, `${at}: the button keeps its size at the strip's right end`);
  assert.equal(p.querySelector('.panel-tools .tool.full'), null, `${at}: no second button in the header`);
  assert.ok(btn.compareDocumentPosition(p.querySelector('.b3-detail')) & w.Node.DOCUMENT_POSITION_FOLLOWING, `${at}: ahead of the details in the focus order`);
  if (focused) assert.equal(doc.activeElement, btn, `${at}: the button keeps the focus`);
}
function inHead(w, btn, at, focused = true) {
  const p = b3(w), tools = p.querySelector('.panel-head .panel-tools');
  assert.equal(tools.firstElementChild, btn, `${at}: the button is back first in the header's tools`);
  assert.ok(!p.classList.contains('b3-headless'), `${at}: the header is shown`);
  const sum = p.querySelector('.b3-sum');  // none while the panel shows its error or "empty"
  if (sum) assert.deepEqual(Array.from(sum.children, (e) => e.className), ['b3-ks'], `${at}: the strip holds the counts alone`);
  if (focused) assert.equal(w.document.activeElement, btn, `${at}: the button keeps the focus`);
}

// Done when: the button asks the browser for full screen on the Belt 3D panel, and pressing it again (or leaving full
// screen) puts the panel back; the scene is resized to the panel's new size on entering and on leaving full screen.
// Bug it catches: a button that asks for full screen on the wrong element (the page, or the stage without the header
// and its way back), that keeps offering full screen once it is, a floor left at its old size either way, or (#377) a
// browser with full screen given the fill-the-window stand-in instead.
test('belt3d: the header\'s button shows the panel full screen and back, the floor refitted each way', async () => {
  const w = await open3d(full(), { extra: FULLSCREEN });
  const btn = b3(w).querySelector('.panel-head .panel-tools .tool.full'), said = () => btn.getAttribute('aria-label');
  assert.ok(btn, 'the button is in the panel\'s header');
  assert.equal(said(), 'Show Belt 3D full screen');
  btn.focus();
  inHead(w, btn, 'in its place');
  btn.click();
  await settle();
  // By identity: two DOM elements compare equal whatever they are.
  assert.ok(w.fsAsked.length === 1 && w.fsAsked[0] === b3(w), 'full screen is asked for on the Belt 3D panel, its way back with it');
  assert.equal(said(), 'Leave full screen');
  assert.deepEqual([...w.scene3d.resized], ['full screen'], 'the floor is fitted to the full screen');
  inStrip(w, btn, 'full screen');
  btn.click();
  await settle();
  assert.ok(w.fsAsked.length === 2 && w.fsAsked[1] === null, 'the same button leaves full screen');
  assert.equal(said(), 'Show Belt 3D full screen');
  assert.deepEqual([...w.scene3d.resized], ['full screen', 'in its place'], 'the floor is fitted back to the panel');
  inHead(w, btn, 'out of full screen');
  // Esc: the browser leaves full screen itself and says so.
  btn.click();
  await settle();
  inStrip(w, btn, 'full screen again');
  w.fsEl = null;
  w.document.dispatchEvent(new w.Event('fullscreenchange'));
  assert.equal(said(), 'Show Belt 3D full screen', 'after Esc the button offers full screen again');
  inHead(w, btn, 'after Esc');
  assert.deepEqual([...w.scene3d.resized], ['full screen', 'in its place', 'full screen', 'in its place']);
  assert.equal(w.document.querySelector('.b3-fill, html.b3-filling'), null, 'where the browser gives full screen, the panel never fills the window instead');
});

// Done when (#377): with no Fullscreen API, or one that refuses, the button is shown, and pressing it makes the panel
// fill the window and resizes the scene; pressing it again, or Esc, restores the panel and resizes the scene back; a
// resize of the window (a turn of the phone) while it fills it resizes the scene. Bug it catches: no way to make the
// floor bigger on an iPhone (no button, or one that does nothing), a panel that fills the window but leaves the page
// behind it scrolling or under other panels, a floor left at its old size, a panel stuck filling the window, or a
// collapsed panel filling the window with nothing drawn.
test('belt3d: with no Fullscreen API, or one that refuses, the button makes the panel fill the window and back, the floor refitted each way', async () => {
  const w = await open3d(full(), { reducedMotion: true });
  const p = b3(w), html = w.document.documentElement, btn = p.querySelector('.panel-head .panel-tools .tool.full');
  const said = () => btn.getAttribute('aria-label'), resized = () => [...w.scene3d.resized];
  assert.ok(btn, 'no Fullscreen API (Safari on iPhone): the button is in the panel\'s header all the same');
  assert.equal(said(), 'Show Belt 3D full screen');
  btn.focus();
  btn.click();
  await settle();
  assert.ok(p.classList.contains('b3-fill') && html.classList.contains('b3-filling'), 'the panel fills the window, the page behind it held still');
  assert.match(css, /\.panel\.b3-fill \{ position: fixed; inset: 0; z-index: 40;/, 'the panel covers the window, over the page\'s header (z-index 20) and its sheet (25)');
  assert.match(css, /html\.b3-filling, html\.b3-filling body \{ overflow: hidden; \}/, 'the page behind does not scroll');
  inStrip(w, btn, 'filling the window');
  assert.equal(said(), 'Leave full screen');
  assert.deepEqual(resized(), ['window'], 'the floor is fitted to the window');
  w.dispatchEvent(new w.Event('resize'));
  assert.deepEqual(resized(), ['window', 'window'], 'a turn of the phone: the floor is fitted to the window again');
  btn.click();
  await settle();
  assert.ok(!p.classList.contains('b3-fill') && !html.classList.contains('b3-filling'), 'the same button puts the panel back');
  assert.equal(said(), 'Show Belt 3D full screen');
  inHead(w, btn, 'put back');
  assert.deepEqual(resized(), ['window', 'window', 'in its place'], 'the floor is fitted back to the panel');
  w.dispatchEvent(new w.Event('resize'));
  assert.equal(resized().length, 3, 'in its place, a resize is the scene\'s own to follow');
  btn.click();
  await settle();
  inStrip(w, btn, 'filling the window again');
  btn.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  assert.ok(!p.classList.contains('b3-fill') && !html.classList.contains('b3-filling'), 'Esc puts the panel back');
  inHead(w, btn, 'after Esc');
  assert.deepEqual(resized().slice(3), ['window', 'in its place']);
  // Collapsed, then filling the window: the floor is shown and drawn (as full screen).
  p.querySelector('.panel-tools .tool[aria-controls]').click();
  await settle();
  frames(w, 3);
  const drawn = w.scene3d.frames.length;
  frames(w, 3);
  assert.equal(w.scene3d.frames.length, drawn, 'collapsed: nothing is drawn');
  btn.click();
  await settle();
  assert.match(css, /\.panel\.b3-fill > \.panel-body\[hidden\] \{ display: block !important; \}/, 'filling the window shows the hidden body');
  frames(w);
  assert.ok(w.scene3d.frames.length > drawn, 'filling the window: the floor is drawn');
  // A browser that has the API but refuses (a frame that may not, or no full screen for this element): the panel
  // fills the window instead, and the same button brings it back without asking the browser to leave full screen.
  for (const [why, extra] of [['refuses', `${FULLSCREEN} Element.prototype.requestFullscreen = function () { window.fsAsked.push(this); return Promise.reject(new TypeError('denied')); };`],
    ['not allowed here', `${FULLSCREEN} document.fullscreenEnabled = false;`]]) {
    const v = await open3d(full(), { extra });
    const q = b3(v), b = q.querySelector('.tool.full');
    assert.ok(b, `${why}: the button is shown`);
    b.click();
    await settle();
    assert.ok(q.classList.contains('b3-fill'), `${why}: the panel fills the window`);
    assert.deepEqual([...v.scene3d.resized], ['window'], `${why}: the floor is fitted to the window`);
    b.click();
    await settle();
    assert.ok(!q.classList.contains('b3-fill'), `${why}: the button puts it back`);
    assert.ok(!v.fsAsked.includes(null), `${why}: leaving asks nothing of the browser's full screen`);
  }
  // Bug it catches: the owner leaves the tab (another tab, or Back) while the panel fills the window; the panel is
  // taken out of the page with its button, and the other tabs are left unable to scroll.
  const t = await open3d(full(), { reducedMotion: true });
  const tp = b3(t), troot = t.document.documentElement;
  tp.querySelector('.tool.full').click();
  await settle();
  assert.ok(troot.classList.contains('b3-filling'), 'filling the window');
  tabBtn(t, 'overview').click();
  await settle();
  assert.ok(!tp.isConnected, 'the Belt 3D panel is out of the page');
  assert.ok(!troot.classList.contains('b3-filling'), 'another tab: the page scrolls again');
  tabBtn(t, 'belt3d').click();
  await settle();
  assert.ok(tp.isConnected && !tp.classList.contains('b3-fill'), 'back on its tab, the panel is in its place');
  assert.equal(tp.querySelector('.tool.full').getAttribute('aria-label'), 'Show Belt 3D full screen');
});

// Bug it catches: full screen, a refresh that finds the floor empty clears the panel's body, the header strip and the
// button in it with it, while the header stays set aside: on a phone, filling the window, nothing is left to tap to
// leave. The button goes back to the header, shown again, and works; the floor back, it returns to the strip. A refresh
// that fails (an SSH timeout: the part's error) keeps the floor drawn, with a note above it (#559): the button stays
// in the strip and still leaves.
for (const [mode, extra] of [['filling the window', ''], ['full screen', FULLSCREEN]]) {
  test(`belt3d: ${mode}, an empty refresh puts the button back in the shown header, a failed one keeps it in the strip, and it still leaves`, async () => {
    const failed = full(), empty = full();
    failed.panels.belt3d = { error: 'ssh: connect to host timed out', data: null };
    empty.panels.belt3d.data = { ...empty.panels.belt3d.data, belt: [], needs: [], landed: [], queue: { next: [], waiting: [], held: [] } };
    for (const [why, data] of [['failed', failed], ['empty', empty]]) {
      const w = await open3d(full(), { extra, reducedMotion: true });
      const p = b3(w), btn = p.querySelector('.tool.full'), on = () => (extra ? w.fsEl === p : p.classList.contains('b3-fill'));
      btn.click();
      await settle();
      inStrip(w, btn, `${mode}`, false);
      next(w, data);
      await settle();
      if (why === 'failed') {
        assert.equal(state(w, 'belt3d'), 'ready', 'failed: the panel keeps its floor');
        assert.ok(p.querySelector('.panel-body > .panel-note'), 'failed: with a note above it');
        assert.ok(on(), `failed: still ${mode}`);
        inStrip(w, btn, `failed, ${mode}`, false);
        btn.click();
        await settle();
        assert.ok(!on(), `failed: the button in the strip leaves ${mode}`);
        continue;
      }
      assert.equal(state(w, 'belt3d'), 'empty', `${why}: the panel shows its ${why} state`);
      assert.ok(on(), `${why}: still ${mode}`);
      assert.equal(p.querySelector('.b3-sum'), null, `${why}: the header strip is gone with the floor`);
      inHead(w, btn, `${why}, ${mode}`, false);
      assert.equal(btn.getAttribute('aria-label'), 'Leave full screen', `${why}: the button still offers the way out`);
      const sel = extra ? '\\.panel:fullscreen' : '\\.panel\\.b3-fill';
      assert.match(css, new RegExp(`${sel} \\.panel-head \\.drag, ${sel} \\.panel-tools \\.tool:not\\(\\.full\\),`), `${why}: the shown header has only the button`);
      next(w, full());
      await settle();
      inStrip(w, btn, `${why}, the floor back`, false);
      next(w, data);
      await settle();
      btn.click();
      await settle();
      assert.ok(!on(), `${why}: the button in the header leaves ${mode}`);
      inHead(w, btn, `${why}, left`, false);
    }
  });
}

// Bug it catches: a collapsed panel shown full screen as an empty header with no way to open it (the collapse
// control is set aside full screen), its body still hidden and its floor not drawn.
test('belt3d: a collapsed panel shown full screen shows its floor and draws it, and is collapsed again on leaving', async () => {
  // Reduced motion: the panel folds at once, with no fade first.
  const w = await open3d(full(), { extra: FULLSCREEN, reducedMotion: true });
  const p = b3(w), body = p.querySelector('.panel-body');
  p.querySelector('.panel-tools .tool[aria-controls]').click();
  await settle();
  frames(w, 3);
  assert.equal(body.hidden, true, 'collapsed');
  const drawn = w.scene3d.frames.length;
  frames(w, 3);
  assert.equal(w.scene3d.frames.length, drawn, 'collapsed: nothing is drawn');
  p.querySelector('.tool.full').click();
  await settle();
  assert.match(css, /\.panel:fullscreen > \.panel-body\[hidden\] \{ display: block !important; \}/, 'full screen shows the hidden body');
  frames(w);
  assert.ok(w.scene3d.frames.length > drawn, 'full screen: the floor is drawn');
  p.querySelector('.tool.full').click();
  await settle();
  frames(w);
  const back = w.scene3d.frames.length;
  frames(w, 3);
  assert.equal(w.scene3d.frames.length, back, 'back in its place, still collapsed: nothing is drawn');
  assert.equal(body.hidden, true);
});

// The frame loop draws nothing while the scene is out of sight, and draws again once it is back. A row a way of
// leaving: the frames run first, what puts the scene out of sight, what brings it back, what is then not drawn, and
// how many frames are drawn once it is back (one, or some).
const setVisibility = (w, v) => Object.defineProperty(w.document, 'visibilityState', { value: v, configurable: true });
for (const [name, first, hide, show, hidden, one] of [
  ['the page is out of view, and goes on when it is back', 0, (w) => setVisibility(w, 'hidden'),
    (w) => { setVisibility(w, 'visible'); w.document.dispatchEvent(new w.Event('visibilitychange')); }, 'the page is hidden', true],
  ['another tab is shown, and goes on when its tab is back', 1, (w) => tabBtn(w, 'overview').click(),
    (w) => { tabBtn(w, 'belt3d').click(); tick(w, 1000); }, 'Overview is shown', false],
]) {
  test(`belt3d: the frame loop stops while ${name}`, async () => {
    const w = await open3d(full());
    if (first) frames(w, first);
    const drawn = w.scene3d.frames.length;
    hide(w);
    frames(w, 3);
    assert.equal(w.scene3d.frames.length, drawn, `nothing is drawn while ${hidden}`);
    assert.equal(w.frames.length, 0, 'and no frame is asked for');
    show(w);
    frames(w);
    if (one) assert.equal(w.scene3d.frames.length, drawn + 1);
    else assert.ok(w.scene3d.frames.length > drawn, 'its tab shown again, the scene draws again');
  });
}

// Issue 569: a floor where nothing moves asks for no frame (each one drew 2048-pixel soft shadows and placed every
// label), not even as the clock moves its times on; whatever moves it asks for frames again until it settles. Bug it
// catches: a loop that asks for a frame each frame whatever the scene says, the clock restarting a settled scene each
// second, or an update, the pointer, the details, a resize or the panel back in sight left on the old picture.
test('belt3d: a settled scene asks for no frame in 2 s; an update, a camera move, the pointer or a resize asks again until it settles', async () => {
  const w = await open3d(full());
  w.scene3d.still = true;  // the stand-in says what the scene's frame says: whether the floor has settled
  frames(w);
  const drawn = w.scene3d.frames.length;
  for (let i = 0; i < 2; i += 1) { tick(w, 1000); frames(w); }
  assert.equal(w.frames.length, 0, 'D1: settled, no frame is asked for in 2 s of the clock');
  assert.equal(w.scene3d.frames.length, drawn, 'and nothing is drawn');
  for (const [what, act] of [
    ['an update', (x) => { const d = full(); d.panels.belt3d.data.belt[0].step = 'tests'; next(x, d); }],
    ['a camera move (the details open)', (x) => x.scene3d.o.pick('sample:c2-13')],
    ['the pointer on a card', (x) => x.scene3d.o.hover('sample:c3-63', 200, 120)],
    ['a resize of the window', (x) => x.dispatchEvent(new x.Event('resize'))],
    ['a new size of the stage', (x) => x.scene3d.o.wake()],
    ['the panel back in sight', (x) => { tabBtn(x, 'overview').click(); tick(x, 1000); tabBtn(x, 'belt3d').click(); tick(x, 1000); }],
  ]) {
    w.scene3d.still = false;
    act(w);
    const n = w.scene3d.frames.length;
    frames(w, 4);
    assert.equal(w.scene3d.frames.length, n + 4, `D2: ${what} has the scene drawn at each frame while the floor moves`);
    w.scene3d.still = true;
    frames(w, 3);
    assert.equal(w.scene3d.frames.length, n + 5, `after ${what}, drawn no more once it has settled`);
    assert.equal(w.frames.length, 0, `after ${what}, no frame asked for once it has settled`);
  }
});

test('belt3d: a kept layout from when Belt 3D was on Overview loads Overview without it, and Belt 3D on its own tab', () => {
  const store = { [STORE]: JSON.stringify({ tabs: { overview: { order: ['belt3d', 'needs', 'belt'], sizes: { belt3d: 'full' }, lengths: { belt3d: 'all' }, collapsed: ['belt3d'], hidden: [] } }, density: 'comfortable', theme: 'system' }) };
  const w = boot({ store });
  deliver(w, full());
  assert.equal(panel(w, 'belt3d'), null, 'Overview does not draw Belt 3D');
  assert.deepEqual(order(w), OVERVIEW, 'the kept order without it');
  for (const id of OVERVIEW) assert.equal(state(w, id), 'ready', `${id} draws`);
  tabBtn(w, 'belt3d').click();
  assert.deepEqual(order(w), BELT3D_IDS);
  assert.equal(panel(w, 'belt3d').querySelector('.panel-body').hidden, false, 'its tab starts at its default');
});

test('belt3d: the vendored three.js files are those the README there lists, each with its sha256, and hold every module the scene imports', () => {
  const dir = path.join(VIEW, 'vendor', 'three');
  const listed = new Map(Array.from(fs.readFileSync(path.join(dir, 'README.md'), 'utf8').matchAll(/^\| ([\w./-]+) \| ([0-9a-f]{64}) \|$/gm), (m) => [m[1], m[2]]));
  const files = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? files(path.join(d, e.name)) : [path.join(d, e.name)]));
  const present = files(dir).map((f) => path.relative(dir, f)).filter((f) => f !== 'README.md').sort();
  assert.deepEqual(present, Array.from(listed.keys()).sort(), 'every vendored file is listed, and every listed file is there');
  for (const [f, sum] of listed) assert.equal(createHash('sha256').update(fs.readFileSync(path.join(dir, f))).digest('hex'), sum, `${f} matches its sha256`);
  // Every module the scene reaches is a vendored file, none is asked for by a bare name (the page has no import map),
  // and every vendored module is one the scene reaches: nothing is kept that nothing uses.
  const seen = new Set(), todo = [path.join(VIEW, 'belt3d-scene.js')];
  while (todo.length) {
    const f = todo.pop();
    for (const m of fs.readFileSync(f, 'utf8').matchAll(/^(?:import|export)\b[^;]*?\bfrom '([^']+)';/gms)) {
      assert.match(m[1], /^\.\.?\//, `${path.relative(VIEW, f)} imports ${m[1]} by a path`);
      const to = path.resolve(path.dirname(f), m[1]);
      assert.ok(to.startsWith(dir + path.sep) && listed.has(path.relative(dir, to)), `${m[1]} is a vendored file`);
      if (!seen.has(to)) { seen.add(to); todo.push(to); }
    }
  }
  assert.deepEqual(Array.from(seen, (f) => path.relative(dir, f)).sort(), present.filter((f) => f.endsWith('.js')).sort(), 'every vendored module is used');
});

// Bug: the machine head's project filter cut every list but Belt 3D's: filtered to one project, the floor still
// showed both projects' cards.
test('belt3d: filtered to one project, the floor shows that project\'s cards alone', async () => {
  const data = full();
  data.panels.machine.data.repos = ['sample', 'widgetshop'];
  const w = await open3d(clone(data), { query: '?tab=belt3d&project=widgetshop' });
  assert.deepEqual(lanes(w), [[5, false]]);
  assert.deepEqual(shownTags(w), []);
  assert.deepEqual(['run', 'blocked', 'queued', 'landed'].map((k) => count(w, k)), [1, 0, 0, 0]);
  const all = await open3d(clone(data), { query: '?tab=belt3d' });
  assert.equal(lanes(all).length, 5);
});

// ---- the deck behind the floor (issue 393) ----
const readouts = (w) => Array.from(b3(w).querySelectorAll('.b3-ro'), (el) => Array.from(el.children, (c) => c.textContent).filter(Boolean));
// Done when: the readouts show the snapshot's own values and change when it does. Bug it catches: a readout typed in
// (the mockup's figures), one left at the last snapshot's value, or a loop called LIVE when it is paused.
// Issue 413 (UX30): the corners repeated the header strip's counts 40 px below it, and read the host's test-slot pool
// ("SLOTS 2/16 FREE", then "16/16 FREE") while the head's tile said "5 of 13": four slot figures on one screen. The
// deck's one slots figure is the head tile's (the collector gives both from one count, dashboard-cards.test.sh), filtered to
// a project or not, and no corner repeats a count the header strip shows.
test('belt3d: the deck\'s readouts are the snapshot\'s values, its slots the head tile\'s figure, no header-strip count repeated, and follow each refresh', async () => {
  const data = full();
  const w = await open3d(data);
  // T0 is 17:00 UTC on 9 November: 12:00 in New York (EST).
  assert.deepEqual(readouts(w), [['CONVEYOR · BUILDHOST'], ['SLOTS 2 OF 3 IN USE'], ['ET 12:00:00 PM'], ['LOOP ● LIVE']]);
  assert.equal(fig(w, 'belt'), '2 of 3', 'the head\'s tile gives the same figure');
  assert.doesNotMatch(readouts(w).flat().join(' '), /RUNNING|WAITING|HELD|LANDED|FREE/, 'no corner repeats the header strip\'s counts or a free-slot pool');
  assert.equal(b3(w).querySelector('.b3-ro .bar i') !== null, true, 'the bar under the top-left readout');
  tick(w, 1000);
  assert.deepEqual(readouts(w)[2], ['ET 12:00:01 PM'], 'the clock ticks with the panel\'s second');
  const after = clone(data);
  after.panels.belt3d.data.deck = { host: 'buildhost', state: 'paused', used: 3, cap: 4 };
  next(w, after);
  frames(w);
  assert.deepEqual(readouts(w).slice(0, 2), [['CONVEYOR · BUILDHOST'], ['SLOTS 3 OF 4 IN USE']]);
  assert.deepEqual(readouts(w)[3], ['LOOP ● PAUSED']);
  assert.equal(b3(w).querySelector('.b3-ro.br span').className, 'off', 'a loop not running is not marked live');
  // Filtered to one project, the floor shows its cards alone and the deck the machine's slots, as the head's tile.
  data.panels.machine.data.repos = ['sample', 'widgetshop'];
  const one = await open3d(clone(data), { query: '?tab=belt3d&project=widgetshop' });
  assert.deepEqual(readouts(one)[1], ['SLOTS 2 OF 3 IN USE']);
  assert.equal(fig(one, 'belt'), '2 of 3');
  // No slots in force read: the cards alone, as the tile; a count or a machine not read is a dash, never a number.
  assert.deepEqual(readouts(await open3d(floor({ deck: { host: 'buildhost', state: 'running', used: 2, cap: null } })))[1], ['SLOTS 2 IN USE']);
  const unread = await open3d(floor({ deck: { host: 'buildhost', state: 'not read', used: null, cap: 3 } }));
  assert.deepEqual(readouts(unread).slice(1), [['SLOTS — IN USE'], ['ET 12:00:00 PM'], ['LOOP ● NOT READ']]);
  const none = await open3d(floor({ deck: undefined }));
  assert.deepEqual(readouts(none), [['CONVEYOR · —'], ['SLOTS — IN USE'], ['ET 12:00:00 PM'], ['LOOP ● —']]);
});

// Issue 458: the deck's ET clock is in the Board's Time, 12-hour by default, and 24-hour once Customize says so, at
// once. Bug it catches: a clock fixed at 24-hour ("ET 15:04:47") whatever the owner chose, or one that keeps the old
// style until the page is reloaded.
test('belt3d: the ET clock reads 3:04:47 PM by default and 15:04:47 with Time set to 24-hour', async () => {
  const w = await open3d(full());
  // T0 is 12:00:00 in New York: 3 h 4 min 47 s on is 15:04:47 ET.
  tick(w, (3 * 3600 + 4 * 60 + 47) * 1000);
  assert.deepEqual(readouts(w)[2], ['ET 3:04:47 PM']);
  w.document.getElementById('customize-open').click();
  const r = w.document.querySelector('#customize input[name="choice-time"][value="24-hour"]');
  r.checked = true; r.dispatchEvent(new w.Event('change', { bubbles: true }));
  assert.deepEqual(readouts(w)[2], ['ET 15:04:47'], 'the clock follows the new Time with no reload');
});

// Done when: the deck is SVG, CSS and HTML of the page's own, under the floor, taking no click, and with reduced motion
// nothing of it moves. Bug it catches: an image or a fetch from another site, a deck over the cards' words or catching
// their clicks, or motion the reduced-motion rule cannot stop (an SVG <animate>, or a frame loop of its own).
test('belt3d: the deck is the page\'s own SVG and CSS under the floor, takes no click, and reduced motion stops all of it', async () => {
  const w = await open3d(full(), { reducedMotion: true });
  const deck = b3(w).querySelector('.b3-deck'), hud = b3(w).querySelector('.b3-hud');
  assert.ok(deck && hud && deck.parentElement.classList.contains('b3-stage') && hud.parentElement === deck.parentElement);
  assert.equal(deck.getAttribute('aria-hidden'), 'true');
  assert.equal(deck.querySelectorAll('.b3-ring').length, 3);
  // The owner removed the scan line that swept down the stage (issue 404): the deck is the grid and the rings' picture
  // and nothing else, and no rule draws a scan line. Bug it catches: the scan line's element or styles coming back.
  assert.deepEqual(Array.from(deck.children, (el) => el.getAttribute('class')), ['b3-grid', 'b3-rings']);
  assert.doesNotMatch(css, /b3-scan/, 'no scan line is styled or animated');
  assert.equal(b3(w).querySelectorAll('img, image, use, animate, animateTransform, animateMotion, set').length, 0, 'no image, and no SMIL motion CSS cannot stop');
  assert.doesNotMatch(deck.outerHTML + hud.outerHTML, /https?:|\/\//, 'nothing from another site');
  // Every rule of exactly that selector, together.
  const rule = (sel) => Array.from(css.matchAll(new RegExp(`(?:^|\\n)${sel.replace(/[.*]/g, '\\$&')} \\{([^}]*)\\}`, 'g')), (m) => m[1]).join(' ');
  assert.match(rule('.b3-deck, .b3-hud'), /pointer-events: none;/, 'neither takes a click');
  assert.match(rule('.b3-deck'), /z-index: -1;/, 'the deck is under the canvas');
  assert.match(css, /\.b3-stage \{[^}]*isolation: isolate;/, 'in the stage\'s own stacking context, not under the page');
  assert.match(rule('.b3-hud'), /z-index: 1;/, 'the readouts are under the floor\'s words (z-index 2) and the header strip');
  // Every loop of the deck is a CSS animation, which the page's reduced-motion rules stop, and none is driven by script.
  for (const [sel, name] of [['.b3-grid i', 'b3-roll'], ['.b3-ring.r1', 'b3-spin'], ['.b3-ring.r2', 'b3-spin'], ['.b3-ro .bar i', 'b3-bar']]) {
    assert.match(rule(sel), new RegExp(`animation: ${name} `), `${sel} moves by its CSS animation`);
  }
  assert.match(css, /:root\[data-motion="off"\] \*, :root\[data-motion="off"\] \*::before, :root\[data-motion="off"\] \*::after \{ animation: none !important;/);
  tick(w, 1000);
  frames(w, 3);
  assert.deepEqual(Array.from(deck.querySelectorAll('*'), (el) => el.getAttribute('style')).filter(Boolean), [], 'no script moves the deck');
});
