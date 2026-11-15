// SPDX-License-Identifier: Apache-2.0
// The Release panel on Overview: main as a release sees it, the release run, and Release and Stop, each on a second
// click. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, full, panel, act, settle, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const A = 'a'.repeat(40), B = 'b'.repeat(40);
// The fixture's release part (main two commits past v1.2.0, at B) with the release run given.
function data(run) {
  const d = full();
  d.panels.release.data.records[0].suites = run ? [run] : [];
  return d;
}
const rel = (w) => panel(w, 'release');
const sent = async (w, fn) => { fn(); await settle(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the owner cannot see from the Board what a release would hold or how its last suite ended (they
// ask the Foreman), and a release starts on one press, or with a version other than the one typed.
test('Release shows the newest tag, the commits since it and the last run; Release sends only on a second press, with the version typed', async () => {
  const w = boot();
  deliver(w, data({ kind: 'release', version: '1.3.0', step: 'release-prep', sha: A, since: '2026-11-14T08:00:00Z', ended: '2026-11-14T08:15:00Z',
    state: 'failed', done: 140, failed: 2, cases: ['code.test: breaks', 'flaky.test: flips'], moved: false, reasons: ['the whole suite failed on aaaaaaaaaaaa (exit 1)'] }));
  assert.match(rel(w).querySelector('[data-figure="tag"]').textContent, /Newest release v1\.2\.0: 2 commits on main since it/);
  assert.deepEqual(Array.from(rel(w).querySelectorAll('[data-list="commits"] li'), (x) => x.textContent), ['bbbbbbb feat: Board panel', 'aaaaaaa fix: A fix']);
  assert.match(rel(w).querySelector('[data-figure="notes"]').textContent, /docs\/releases\/1\.3\.0\.md is not on main yet/);
  assert.match(rel(w).querySelector('[data-figure="last"]').textContent, /Last run: release 1\.3\.0 failed on aaaaaaaaaaaa.*main has moved since/);
  assert.deepEqual(Array.from(rel(w).querySelectorAll('[data-list="failed"] li'), (x) => x.textContent), ['code.test: breaks', 'flaky.test: flips']);
  assert.deepEqual(Array.from(rel(w).querySelectorAll('[data-list="reasons"] li'), (x) => x.textContent), ['the whole suite failed on aaaaaaaaaaaa (exit 1)']);
  const input = rel(w).querySelector('[data-field="version"]');
  assert.equal(input.value, '1.3.0', 'the next minor is filled in');
  input.value = '1.4.0'; input.dispatchEvent(new w.Event('input'));
  assert.deepEqual(await sent(w, () => act(rel(w), 'release').click()), [], 'one press sends nothing');
  assert.deepEqual(await sent(w, () => act(rel(w), 'release').click()), [{ action: 'release-run', args: ['1.4.0'], repo: 'sample' }]);
});

// Bugs this guards: a run under way cannot be stopped from the Board, or a second release is offered beside it; a run
// that main moved under shows no word of it and no way to run on the new main.
test('A run under way shows its cases and a Stop on a second press; a run main moved under offers Run again on the new main', async () => {
  const w = boot();
  deliver(w, data({ kind: 'release', version: '1.3.0', step: 'release-prep', sha: B, since: '2026-11-14T08:00:00Z', ended: null,
    state: 'running', done: 12, failed: 1, cases: ['code.test: breaks'], moved: false, reasons: [] }));
  assert.match(rel(w).textContent, /release-prep 1\.3\.0 is running on bbbbbbbbbbbb/);
  assert.match(rel(w).textContent, /12 cases done · 1 failed/);
  assert.equal(act(rel(w), 'release').disabled, true, 'no second release beside the one under way');
  assert.deepEqual(await sent(w, () => act(rel(w), 'release-stop').click()), []);
  assert.deepEqual(await sent(w, () => act(rel(w), 'release-stop').click()), [{ action: 'release-run', args: ['stop'], repo: 'sample' }]);
  const moved = boot();
  deliver(moved, data({ kind: 'release', version: '1.3.0', step: 'release-prep', sha: A, since: '2026-11-14T08:00:00Z', ended: '2026-11-14T08:15:00Z',
    state: 'passed', done: 140, failed: 0, cases: [], moved: true, reasons: [] }));
  assert.match(rel(moved).textContent, /Main moved while the suite ran/);
  assert.deepEqual(await sent(moved, () => act(rel(moved), 'release-again').click()), []);
  assert.deepEqual(await sent(moved, () => act(rel(moved), 'release-again').click()), [{ action: 'release-run', args: ['1.3.0'], repo: 'sample' }]);
});
