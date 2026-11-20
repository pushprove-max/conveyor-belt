// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Archive, Restore and Delete of runs (#1053): sent as `bench swe runs archive | restore | delete
// <id>...`; an archived run leaves History, Compare's choices and the infographic for the Archived view; Delete of the
// runs selected takes one confirm that names them; a run that has not ended has both off. Shared setup:
// dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { boot, settle, act, cases, BH } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { bp, heads, NEW, OLD } = BH;
const text = (el) => el.textContent.replace(/\s+/g, ' ').trim();
const pick = (w, a) => { const b = act(bp(w), a); b.checked = !b.checked; b.dispatchEvent(new w.Event('change')); };
const listed = (w) => Array.from(bp(w).querySelectorAll('.bench-history tr[data-run]'), (r) => r.dataset.run);
const choices = (w) => Array.from(act(bp(w), 'cmp-a').options, (o) => o.textContent);
// What GET bench gives, with each run's line changed as `over` says (by run id): the history, or a run's page.
const body = (over) => {
  const hist = () => { const x = BH.hist(); x.runs = x.runs.map((r) => ({ ...r, ...(over[r.id] || {}) })); return x; };
  return (url) => (/&run=/.test(url) ? { ...BH.run(), run: hist().runs.find((r) => url.endsWith(encodeURIComponent(r.id))) } : hist());
};
const served = (w, over) => { w.benchBody = body(over); };
async function opened(over = {}) {
  const w = boot({ tab: 'bench' });
  BH.open(w, { body: body(over) });
  await settle();
  return w;
}

// Bug it guards: a failed or test run stayed in History, Compare's choices and the infographic for good. Archive on a
// run's page sends `bench swe runs archive <id>`; once the history read again marks it, it is in the Archived view
// alone, and Restore there brings it back to History and to Compare.
test('Archive: the run leaves History, Compare and the infographic for the Archived view; Restore brings it back', async () => {
  const w = await opened();
  pick(w, `pick-${NEW}`); pick(w, `pick-${OLD}`);
  act(bp(w), 'sel-compare').click();
  assert.deepEqual(choices(w), ['Conveyor 1.5.0', 'Claude alone (claude-opus-5-5)', 'Codex alone (gpt-6.2-sol)', 'Conveyor 1.4.0']);
  act(bp(w), 'back').click();
  act(bp(w), `run-${OLD}`).click();
  await settle();
  w.reply = BH.reply(`conveyor: archived ${OLD}.`);
  act(bp(w), 'archive-runs').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'bench', args: ['runs', 'archive', OLD], repo: 'sample' }]);
  served(w, { [OLD]: { archived: '2026-11-20T10:00:00Z' } });
  await settle(); await settle();
  assert.equal(text(bp(w).querySelector('.bench-run-head .bench-said')), `Archived ${OLD}.`);
  assert.ok(text(bp(w).querySelector('.bench-run-head .bench-head')).includes('Archived'), 'the archived run\'s page says so');
  assert.equal(act(bp(w), 'restore-runs').textContent, 'Restore', 'the archived run\'s page offers Restore');
  act(bp(w), 'back').click();
  assert.deepEqual(listed(w), [NEW], 'History leaves the archived run out');
  assert.deepEqual(heads(w), ['Newest run', 'History', 'Archived', 'Arms', 'Drift watch']);
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-archived tr[data-run]'), (r) => r.dataset.run), [OLD]);
  act(bp(w), 'sel-compare').click();
  assert.deepEqual(choices(w), ['Conveyor 1.5.0', 'Claude alone (claude-opus-5-5)', 'Codex alone (gpt-6.2-sol)'], 'Compare offers no arm of the archived run');
  act(bp(w), 'back').click();
  act(bp(w), 'sel-infographic').click();
  assert.ok(!text(bp(w)).includes(`Run ${OLD}`), 'the infographic leaves the archived run out');
  act(bp(w), 'back').click();
  w.reply = BH.reply(`conveyor: restored ${OLD}.`);
  bp(w).querySelector(`.bench-archived tr[data-run="${OLD}"] [data-act="restore-runs"]`).click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['runs', 'restore', OLD]]);
  served(w, {});
  await settle(); await settle();
  assert.deepEqual(listed(w), [NEW, OLD], 'the run restored is back in History');
  assert.equal(bp(w).querySelector('.bench-archived'), null, 'no Archived view with no run archived');
});

// Bug it guards: runs could not be deleted, one or several at once. Delete of the two runs selected asks once, in
// words that name both and say a result another run shows stays (history's shared), then sends one request for both.
// A result only the selected runs show (OLD made a/t-1, NEW alone reused it) is not counted as staying: the delete
// removes it, so a confirm that counted each run's shared promised to keep it.
test('Delete: two runs selected are deleted after one confirm that names them and the result that stays', async () => {
  const w = await opened({ [OLD]: { shared: { 'a/t-1': [NEW], 'a/t-2': ['r20261101T090000-9'] } }, [NEW]: { shared: { 'a/t-1': [OLD] } } });
  pick(w, `pick-${NEW}`); pick(w, `pick-${OLD}`);
  const del = bp(w).querySelector('.bench-selbar [data-act="delete-runs"]');
  del.click();
  assert.deepEqual(w.posts, [], 'the first click sends nothing');
  assert.equal(del.textContent, `Click again: delete ${NEW} and ${OLD} (1 result another run shows stays; the rest goes)`);
  w.reply = BH.reply(`conveyor: deleted ${NEW}, ${OLD}; 1 result stays: another run shows it.`);
  del.click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['runs', 'delete', NEW, OLD]], 'one request deletes both');
  w.benchBody = () => ({ ...BH.hist(), runs: [] });
  await settle(); await settle();
  assert.equal(text(bp(w).querySelector('.bench-history .bench-said')), `Deleted ${NEW}, ${OLD}; 1 result stays: another run shows it.`);
  assert.deepEqual(listed(w), []);
  assert.equal(bp(w).querySelector('.bench-selbar'), null, 'the deleted runs are no longer selected');
});

// Bug it guards: a run that has not ended (its process gone with no end written, or going) could be archived or
// deleted while its process may still write its line and results. Both are off on its page and in the selection
// bar, with the reason.
test('A run not ended: Archive and Delete are off on its page and when it is selected, with the reason', async () => {
  const w = await opened({ [NEW]: { state: 'stopped', gone: true, ended: null } });
  pick(w, `pick-${NEW}`);
  const bar = bp(w).querySelector('.bench-selbar');
  assert.deepEqual(['archive-runs', 'delete-runs'].map((a) => bar.querySelector(`[data-act="${a}"]`).disabled), [true, true]);
  assert.ok(text(bar).includes(`${NEW} has not ended: stop it first to archive or delete.`), text(bar));
  act(bp(w), `run-${NEW}`).click();
  await settle();
  const head = bp(w).querySelector('.bench-run-head');
  assert.deepEqual(['archive-runs', 'delete-runs'].map((a) => head.querySelector(`[data-act="${a}"]`).disabled), [true, true]);
  assert.ok(text(head).includes('has not ended: stop it first'), text(head));
});
