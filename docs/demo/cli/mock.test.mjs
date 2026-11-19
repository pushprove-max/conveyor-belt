// SPDX-License-Identifier: Apache-2.0
// mock.js, the belt of the Claude Code beats: the Foreman's own watcher reads its snapshot and wakes on the blocked
// card, and its retry puts that card back on the belt, as the Foreman beat shows.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { createTimeline } from '../timeline.js';
import { answer, writeFeed } from './mock.js';

const WATCH = fileURLToPath(new URL('../../../conveyor/foreman/watch-conveyor.sh', import.meta.url));

// Bug caught: the snapshot is not the record the watcher reads (it stops as "not a health record" and never wakes),
// or it wakes on something else, so the Foreman beat has no wake naming #44.
test("the Foreman's watcher wakes on the snapshot's blocked card, #44", (t) => {
  const T = mkdtempSync(join(tmpdir(), 'demo-mock-'));
  t.after(() => rmSync(T, { recursive: true, force: true }));
  const M = join(T, 'acme-api'), FD = join(T, 'foreman');
  mkdirSync(join(T, 'config', 'conveyor'), { recursive: true });
  spawnSync('git', ['init', '-q', M]);
  writeFileSync(join(T, 'config', 'conveyor', 'host.json'), JSON.stringify({ records: [{ repo: 'acme-api', main: M }] }));
  writeFileSync(join(T, 'snapshot.json'), answer(createTimeline(), 0, 'snapshot', [])[1]);
  const r = spawnSync('bash', [WATCH, '--once'], { cwd: M, encoding: 'utf8',
    env: { ...process.env, HOME: T, XDG_CONFIG_HOME: join(T, 'config'), CONVEYOR_MAIN: M, CONVEYOR_FOREMAN_DIR: FD,
      CONVEYOR_FOREMAN_ASK: `[ "$CONVEYOR_CMD" = snapshot ] && cat ${join(T, 'snapshot.json')} || echo null` } });
  assert.equal(r.status, 0, `the watcher put no wake: ${r.stderr}`);
  const wake = readdirSync(join(FD, 'pending')).map((f) => readFileSync(join(FD, 'pending', f), 'utf8')).join('\n');
  assert.match(wake, /blocked: #44/);
  assert.doesNotMatch(wake, /no loop|gh signed out|idle|stuck/);
});

// Bug caught: the Foreman's retry does not reach the timeline, so the /units pane still shows #44 blocked after the
// pick; or a retry of a card that is not blocked is taken.
test('retry 44 puts #44 back on the belt; a retry of a card not blocked is refused', () => {
  const tl = createTimeline();
  assert.equal(answer(tl, 2, 'retry', ['45'])[0], 1);
  assert.deepEqual(answer(tl, 2, 'retry', ['44']), [0, 'conveyor: #44 can be picked again']);
  const snap = JSON.parse(answer(tl, 3, 'snapshot', [])[1]);
  assert.deepEqual(snap.needsYou.blocked, []);
  assert.deepEqual(snap.health.blocked, []);
  assert.equal(snap.belt.find((c) => c.issue === 44).step, 'build');
  assert.equal(answer(tl, 3, 'retry', ['44'])[0], 1);
});

// Bug caught: the demo's feed folder has data.js but no limit.json (or one in another shape), so the /units pane in
// the Claude Code beats loses its 31% weekly limit and shows the older-engine line; /units reads only limit.json.
test("the feed folder's limit.json holds the health panel's usedPct and resetsAt, null with no limit", (t) => {
  const T = mkdtempSync(join(tmpdir(), 'demo-feed-'));
  t.after(() => rmSync(T, { recursive: true, force: true }));
  const read = () => JSON.parse(readFileSync(join(T, 'limit.json'), 'utf8'));
  const board = createTimeline().snapshot(0);
  const l = board.panels.health.data.limit;
  writeFeed(T, board);
  assert.deepEqual(read(), { limit: { usedPct: 31, resetsAt: l.resetsAt } });
  assert.match(l.resetsAt, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
  board.panels.health.data.limit = null;
  writeFeed(T, board);
  assert.deepEqual(read(), { limit: null });
});
