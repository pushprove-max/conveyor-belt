// SPDX-License-Identifier: Apache-2.0
// The demo's mock timeline (timeline.js) carries the storyboard's Board beats: what the README's demo shows is what
// these snapshots say, so a timeline edit that loses a beat fails here, not in a minute-long render nobody watches.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { BELT3D, createTimeline, REPO, URL } from './timeline.js';

const card = (s, n) => s.panels.belt.data.cards.find((c) => c.issue === n);
const landed = (s, n) => s.panels.landed.data.cards.find((c) => c.issue === n);

// Beat 5. Bug caught: #41 no longer shows review 1 finding a P1, the fix round, a clean review 2 and its landing.
test('card #41: review 1 finds a P1, the fix round runs, review 2 is clean, it lands', () => {
  const tl = createTimeline();
  assert.equal(card(tl.snapshot(4), 41).step, 'review');
  const fix = card(tl.snapshot(5), 41);
  assert.equal(fix.reviews.length, 1);
  assert.equal(fix.reviews[0].verdict, 'NO-GO');
  assert.equal(fix.reviews[0].counts.P1, 1);
  assert.equal(fix.step, 'fix');
  assert.equal(fix.track.steps[2].state, 'now');
  const r2 = card(tl.snapshot(11), 41).reviews;
  assert.deepEqual(r2.map((r) => r.verdict), ['NO-GO', 'GO']);
  const after = tl.snapshot(16);
  assert.equal(card(after, 41), undefined, 'a landed card leaves the belt');
  assert.ok(landed(after, 41));
});

// Beats 4 and 6. Bug caught: #42 does not land in beat 4's window, or Retry does not put #44 back on the belt.
test('#42 lands at 5 s; #44 is blocked until Retry, then builds', () => {
  const tl = createTimeline();
  assert.ok(card(tl.snapshot(4.9), 42));
  assert.equal(landed(tl.snapshot(5), 42).sha, '4f2c9e1', 'the commit the composition shows for #42');
  assert.equal(tl.snapshot(2).panels.needs.data.cards.blocked[0].issue, 44);
  // Bug caught: the Needs you panel lists only the kinds its part names (panels/needs.js), so with no "blocked"
  // kind beat 6 shows "Nothing needs you" and has no Retry to press.
  assert.ok(tl.snapshot(2).panels.needs.data.kinds.some((k) => k.kind === 'blocked' && typeof k.title === 'string'));
  tl.act('retry', ['44'], 3);
  const s = tl.snapshot(3.5);
  assert.deepEqual(s.panels.needs.data.cards.blocked, []);
  assert.equal(card(s, 44).step, 'build');
});

// Beats 7 and 8, and the privacy of the demo. Bug caught: a control the beats press changes nothing the Board reads,
// an unknown action is taken silently, or the snapshot names a repository other than the invented one.
test('the controls the beats press change the snapshot; the data names only example/acme-api', () => {
  const tl = createTimeline();
  for (const n of [4, 5, 6]) tl.act('cap', [String(n)], 3);
  tl.act('model', ['claude', 'claude-opus-5-5', 'high'], 3);
  tl.act('hold', ['45'], 3);
  let s = tl.snapshot(3);
  assert.equal(s.panels.rules.data.cap, 6);
  assert.equal(s.panels.rules.data.modelSettings.builder.model, 'claude-opus-5-5');
  assert.deepEqual(s.panels.board.data.held.map((x) => x.issue), [45]);
  assert.ok(!s.panels.board.data.queue.some((x) => x.issue === 45));
  tl.act('release', ['45'], 3);
  tl.act('rules', ['P2=off'], 3);
  tl.act('rules', ['followups=on'], 3);
  s = tl.snapshot(3);
  assert.deepEqual(s.panels.board.data.held, []);
  assert.equal(s.panels.rules.data.control.rules.P2, false);
  assert.equal(s.panels.rules.data.control.rules.followups, true);
  assert.ok(tl.act('deploy', [], 3) instanceof Error);
  const text = JSON.stringify(s);
  const urls = text.match(/https?:\/\/[^"]+/g);
  assert.ok(urls.length > 0 && urls.every((u) => u.startsWith(`${URL}/`)), 'every address is the invented repository');
  assert.ok(s.panels.belt.data.cards.every((c) => c.repo === REPO));
});

// Beat 9, the Tests page. Bug caught: the Tests tab shows no files ("No tests to show"), every row looks the same, or
// Explain the slowdown and Judge this test show no answer, so the beat cannot show what the page is for. The statuses
// are read from the fields the page's marks() reads (panels/tests.js): over (not slow on purpose), slower, flaky; a
// fine file has none of them, nor a change of -25% or less, a last run over 2x its CPU, 2 failed steps or an issue.
test('the Tests beat: one file Over budget, one Slower than usual, one Flaky, the rest fine; both test actions answer', () => {
  const tl = createTimeline();
  const d = tl.snapshot(3).panels.tests.data;
  assert.equal(d.repo, REPO);
  const files = d.tests.files, share = d.tests.settings.slower.share;
  const status = (f) => [f.over && !f.slowOnPurpose && 'Over budget', f.slower && 'Slower than usual', f.flaky > 0 && 'Flaky',
    (f.change <= -share || f.lastRun.clockPerCpu > 2 || f.failedSteps >= 2 || f.issue !== null) && 'other'].filter(Boolean);
  assert.ok(files.length >= 8, `about 8 files: ${files.length}`);
  assert.deepEqual(files.map(status).filter((s) => s.length).sort(), [['Flaky'], ['Over budget'], ['Slower than usual']]);
  assert.ok(files.every((f) => f.cpu > 0 && f.median > 0 && f.runs.length > 0), 'each file has its CPU s, median and last runs');
  assert.deepEqual(d.control.tests, { cli: 'claude', model: 'claude-sonnet-5-5', effort: 'high' }, 'a Tests model is set: else Judge and Explain are disabled');
  // Explain the slowdown on the file over its budget, then Judge this test on a second file.
  const over = files.find((f) => f.over).file;
  const asked = tl.act('testaction', ['explain', over], 3);
  assert.match(asked, /\n[0-9a-f]{12}$/, 'the answer ends with the action id, as conveyor.sh testaction prints it');
  const judged = tl.act('testaction', ['judge', 'test/customers-lookup.test.ts'], 4);
  assert.ok(tl.act('testaction', ['judge', 'test/auth.test.ts'], 4) instanceof Error, 'a file with no answer is refused, not run silently');
  const acts = (t) => tl.snapshot(t).panels.tests.data.testActions.actions;
  assert.deepEqual(acts(4).map((a) => [a.action, a.state]), [['judge', 'running'], ['explain', 'running']]);
  const [judge, explain] = acts(7);
  assert.equal(explain.id, asked.split('\n').pop());
  assert.equal(judge.id, judged.split('\n').pop());
  assert.deepEqual([explain.state, explain.file], ['done', over]);
  assert.match(explain.text, /went from 7\.9 to 9\.4 CPU s with #42/);
  assert.deepEqual([judge.state, judge.verdict], ['done', 'merge']);
  assert.match(judge.text, /VERDICT: merge\n$/);
  const urls = JSON.stringify(tl.snapshot(7).panels.tests).match(/https?:\/\/[^"]+/g);
  assert.ok(urls.every((u) => u.startsWith(`${URL}/`)), 'every address is the invented repository');
});

// The README's Belt 3D GIF (capture-board.js, belt3d). Bug caught: in its story seconds (BELT3D.from to .to) the Belt
// 3D part shows no card going from Review back to Fix, none blocked or none landing (before #641 it was empty).
test('Belt 3D window: a card goes from Review back to Fix, one is blocked throughout, one lands', () => {
  const tl = createTimeline();
  const parts = [];
  for (let t = BELT3D.from; t <= BELT3D.to; t += 0.5) parts.push(tl.snapshot(t).panels.belt3d.data);
  const steps = (n) => parts.map((p) => (p.belt.find((c) => c.issue === n) || {}).step);
  const back = [...new Set(parts.flatMap((p) => p.belt.map((c) => c.issue)))].find((n) => {
    const s = steps(n), r = s.indexOf('review');
    return r >= 0 && s.indexOf('fix', r) > r;
  });
  assert.ok(back, 'no card goes from Review to Fix');
  // What the floor reads to draw the card's lane: its track's records, the review that found something, then its fix.
  const inFix = parts.map((p) => p.belt.find((c) => c.issue === back)).find((c) => c && c.step === 'fix');
  assert.deepEqual(inFix.track.records.map((r) => r.name), ['building', 'review 1']);
  assert.equal(inFix.reviews[0].verdict, 'NO-GO');
  assert.ok(parts.every((p) => p.needs.some((c) => c.kind === 'blocked' && c.track.steps[3].state === 'failed')), 'a card is blocked throughout');
  const landedAt = (p) => p.landed.map((c) => c.issue);
  assert.ok(landedAt(parts.at(-1)).some((n) => !landedAt(parts[0]).includes(n)), 'no card lands');
});

// Bug caught: the click lands on another card. The capture finds #41's lane, then clicks it: a card landing just
// then moves the lanes and the click opens another card's details (it opened #43's). So no lane comes or goes from a
// second before the click to the time its details show, and #41 is in its fix round with what they show: its six
// steps with their times, its review round and its cost.
test('Belt 3D click: #41 in Fix, on a belt that does not change around the click, with steps, review and cost', () => {
  const tl = createTimeline();
  const { issue, at } = BELT3D.click;
  const lanes = (t) => tl.snapshot(t).panels.belt3d.data.belt.map((c) => c.issue).join(' ');
  for (let t = at - BELT3D.speed; t <= at + 0.5; t += 0.1) assert.equal(lanes(t), lanes(at), `the lanes change at story second ${t.toFixed(1)}`);
  const c = tl.snapshot(at).panels.belt3d.data.belt.find((x) => x.issue === issue);
  assert.equal(c.step, 'fix');
  assert.deepEqual(c.track.steps.map((s) => [s.name, s.state]), [['Build', 'done'], ['Review', 'done'], ['Fix', 'now'], ['Test', 'todo'], ['Land', 'todo'], ['Push', 'todo']]);
  assert.ok(c.track.steps[0].sec > 0 && c.track.steps[1].sec > 0, 'the steps done have their times');
  assert.deepEqual(c.reviews.map((r) => r.verdict), ['NO-GO']);
  assert.ok(c.usd > 0, 'its cost');
});
