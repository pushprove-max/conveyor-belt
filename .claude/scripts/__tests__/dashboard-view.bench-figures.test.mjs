// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's figures in states its other files do not reach (issue 1430): a run stopped before a result, a
// task an arm did not run, and a project with no Conveyor arm. Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { boot, settle, act, cases, BH } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { bp, page, STUDY } = BH;
const text = (el) => el.textContent.replace(/\s+/g, ' ').trim();
const q = (w, s) => page(w).querySelector(s);
const rows = (el) => Array.from(el.querySelectorAll('tbody tr'), (r) => Array.from(r.children, text));
async function opened(set, p) {
  const w = boot({ tab: 'bench' });
  BH.open(w, set);
  await settle(); await settle();
  if (p) { BH.go(w, p); await settle(); await settle(); }
  return w;
}

// Bug it guards: the last run's Minutes column read the minutes of kept results, so a run stopped before its first
// result read 0 though the arm worked on it (bench swe show keeps that in wall).
test('Live run, the last run stopped before a result: Minutes shows the arm\'s wall minutes, not 0', async () => {
  const set = BH.few();
  Object.assign(set.hist.runs[0].cols[0], { minutes: 0, wall: 1.2 });
  const w = await opened(set, 'run');
  const [arm, , , , minutes] = rows(q(w, '.bench-t'))[0];
  assert.deepEqual([arm, minutes], ['Conveyor, Codex builds v1.7.0', '1.2']);
});

// Bug it guards: the hidden-tests cell of an arm that did not run the task was '–', where the page's word for a figure
// it does not have is "not kept".
test('Task, an arm that did not run the task: its hidden-tests cell says not kept', async () => {
  const set = BH.few();
  Object.assign(set.shows[BH.FEW1].tasks[0].cells[0], { result: 'not run: image fetch failed', resolved: undefined });
  const w = await opened(set, 'run');
  act(bp(w), 'open-task').click();
  await settle(); await settle();
  const row = rows(q(w, '.bench-arms')).find((r) => r[1] === 'not run');
  assert.ok(row, 'the arm that did not run the task has its row');
  assert.equal(row[3], 'not kept');
});

// Bug it guards: with no Conveyor arm the page took the best arm as Conveyor, so "Where Conveyor loses tasks" counted
// Claude alone's unresolved tasks under Conveyor's heading.
test('Scoreboard, a project with only a Claude alone run: no Where Conveyor loses tasks box counts its tasks', async () => {
  const set = BH.study(), run = set.hist.runs[0];
  Object.assign(run, { arms: ['solo'], cols: run.cols.filter((c) => c.arm === 'solo') });
  set.hist.runs = [run];
  set.hist.arms = set.hist.arms.filter((a) => a.name === 'solo');
  set.hist.keys = set.hist.keys.filter((k) => k.key === 'solo');
  set.shows[STUDY].tasks.forEach((t) => { t.cells = t.cells.filter((c) => c.arm === 'solo'); });
  const w = await opened(set);
  const heads = Array.from(page(w).querySelectorAll('.bench-h'), (x) => x.textContent);
  assert.ok(heads.some((x) => /^Effort and steadiness/.test(x)), `the Scoreboard is drawn: ${heads.join(' | ')}`);
  assert.ok(!heads.some((x) => /Where Conveyor loses tasks/.test(x)), 'no box counts another arm\'s losses as Conveyor\'s');
});
