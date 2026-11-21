// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab against the owner's approved mockup (#1198, slice 1 of #1197): each item the mockup has that the
// tab lacked, and each text the mockup words differently, on the 7 pages, with the fixture's figures where the mockup's
// are made up (BH.study(), 7 arms on 50 tasks; BH.few(), the 2 runs of 1 task; BH.live(), a run going). The tests use
// jsdom only. Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { boot, settle, act, cases, BH } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { bp, page } = BH;
const text = (el) => el.textContent.replace(/\s+/g, ' ').trim();
const q = (w, s) => page(w).querySelector(s);
const kv = (el) => Array.from(el.querySelectorAll('dt'), (d) => [d.textContent, text(d.nextElementSibling)]);
const box = (w, title) => Array.from(page(w).querySelectorAll('.bench-box')).find((b) => b.querySelector('.bench-h') && b.querySelector('.bench-h').firstChild.textContent.trim() === title);
// store: what Customize left in this browser (the Board's Time and Date).
async function opened(set, p, store) {
  const w = boot({ tab: 'bench', store: store ? { 'conveyor-board-layout': JSON.stringify(store) } : {} });
  BH.open(w, set);
  await settle(); await settle();
  if (p) { BH.go(w, p); await settle(); await settle(); }
  return w;
}

// Bug it guards: the Scoreboard's Hidden tests and Patch quality cards lacked the mockup's chips that say what the
// results must keep, so a reader could not tell an arm's missing grade from a kept one. The chips show only while an
// arm's results lack the grader's report or the reference fix's size: with every result keeping both, a chip that
// asked for them would be stale advice.
test('Scoreboard, 7 arms on 50 tasks, one arm with results that kept no grade: the two heading chips show', async () => {
  const set = BH.study();
  set.shows[BH.STUDY].tasks.flatMap((t) => t.cells).filter((c) => c.arm === 'solo').forEach((c) => Object.assign(c, { class: null, tests: null, ref: null, measures: null }));
  const w = await opened(set);
  const chip = (title) => { const c = box(w, title).querySelector('.bench-h .chip'); return c && [text(c), c.title]; };
  assert.deepEqual(chip('Hidden tests'), ['needs the grader\'s report kept', 'Some results keep only resolved yes or no']);
  assert.deepEqual(chip('Patch quality'), ['needs the reference fix\'s size kept', 'Some results did not keep the reference fix\'s size']);
});

// Bug it guards: the Scoreboard's run history had no Select all, and the tables, tips and definitions said "succeeds" and
// "FAIL_TO_PASS" where the mockup says "passes" and "fail-to-pass".
test('Scoreboard, 7 arms on 50 tasks: the mockup\'s texts, no heading chip when every result keeps its grade, and Select all in the run history', async () => {
  const w = await opened(BH.study());
  assert.deepEqual(['Hidden tests', 'Patch quality'].map((t) => box(w, t).querySelector('.bench-h .chip')), [null, null], 'every arm kept the grader\'s report and the reference size');
  assert.equal(text(box(w, 'Hidden tests').querySelector('.bench-hsub')),
    'What the official harness found in each arm\'s patch, task by task. A task resolves only when every fail-to-pass test passes and no pass-to-pass test breaks.');
  assert.deepEqual(Array.from(box(w, 'Hidden tests').querySelectorAll('th'), text), ['Arm', 'Fail-to-pass passed', 'Pass-to-pass broken', 'Partial fixes']);
  assert.equal(text(box(w, 'Patch quality').querySelector('.bench-hsub')), 'The resolved tasks only: a patch can pass the hidden tests and still be a poor change.');
  assert.deepEqual(Array.from(box(w, 'Patch quality').querySelectorAll('th'), (t) => t.title).filter(Boolean),
    ['At most twice the size of the reference fix', 'Changes a file the reference fix does not touch', 'Adds a test that fails on the base commit and passes with the patch']);
  assert.deepEqual(kv(box(w, 'Patch quality')).filter(([k]) => /^(Lint clean|Proves the fix)$/.test(k)),
    [['Lint clean', 'No new finding from ruff (its default rules) in the Python files the patch changes.'], ['Proves the fix', 'The patch adds a test that fails on the base commit and passes with the patch.']]);
  assert.equal(Array.from(q(w, '.bench-leader').querySelectorAll('th')).find((t) => text(t) === 'Broke tests').title, 'Tasks where the patch broke tests that passed before');
  assert.match(text(box(w, 'Leaderboard').querySelector('.bench-note')), /^Click an arm to compare it with Conveyor\. "From tokens"/);
  // Select all ticks every run of the history and shows the selection bar; ticked again, it clears them.
  const runs = () => Array.from(page(w).querySelectorAll('.bench-runs tbody input'));
  const all = () => act(bp(w), 'pick-all');
  assert.equal(all().getAttribute('aria-label'), 'Select all');
  assert.equal(all().closest('th'), page(w).querySelector('.bench-runs th'), 'the box is the head of the first column');
  all().checked = true; all().dispatchEvent(new w.Event('change'));
  assert.deepEqual([runs().length, runs().every((b) => b.checked), all().checked], [7, true, true], 'every run ticked');
  assert.equal(text(q(w, '.bench-selbar strong')), '7 runs selected');
  all().checked = false; all().dispatchEvent(new w.Event('change'));
  assert.deepEqual([runs().some((b) => b.checked), q(w, '.bench-selbar')], [false, null], 'none ticked, no selection bar');
});

// Bug it guards: the Scoreboard of 2 runs of 1 task reworded the mockup's notes (the leaderboard note, the patch note,
// the callout on what the results keep) and its "never checked" line. The patch note says what the patches kept show.
test('Scoreboard, 2 runs of 1 task: the mockup\'s leaderboard note, patch note, callout and next-run line', async () => {
  const w = await opened(BH.few());
  const notes = Array.from(page(w).querySelectorAll('.bench-note'), text);
  // The table shows "not priced" for these arms and adds no estimate: the note must not say it prices them from tokens.
  assert.ok(notes.includes('"Not priced": agent arms report no usage by model today, so their cost is not priced.'), notes.join(' | '));
  assert.ok(notes.includes('Real, from the patches the results keep. All five made the same one-line fix; only Conveyor, Codex builds v1.7.0 and Conveyor v1.7.0 added a test.'), notes.join(' | '));
  assert.equal(text(q(w, '.bench-callout-warn')), 'Every arm passed the task\'s hidden tests: that is all the results keep. The run records resolved yes or no and the patch, '
    + 'and the harness report with each fail-to-pass and pass-to-pass test is removed. To show these panels, the engine must keep that report. Size, strays and lint can be read from the patches the results already keep.');
  assert.ok(Array.from(box(w, 'Next run to make').querySelectorAll('li'), text).includes('The other 10 arms were never checked. A check costs 1 small task each.'));
});

// Bug it guards: the patch note claimed that every arm made the same fix whatever the patches were. With one arm's
// patch not kept, it says neither that the fixes are the same nor who added a test.
test('Scoreboard, 2 runs of 1 task: the patch note claims only what the kept patches show', async () => {
  const set = BH.few();
  set.shows[BH.FEW1].tasks[0].cells[1].patch = null;
  const w = await opened(set);
  const notes = Array.from(page(w).querySelectorAll('.bench-note'), text);
  assert.ok(notes.includes('Real, from the patches the results keep.'), notes.join(' | '));
});

// Bug it guards: Versions said "engine <sha>" and a long belt line where the mockup names the version and says what
// the figure did; its dates were the Board's long stamp where the mockup has month-day.
test('Versions, 6 versions on 50 tasks: the drift subtitle and belt line name the version, and the dates are month-day', async () => {
  const set = BH.study();
  const w = await opened(set, 'versions');
  assert.equal(text(box(w, 'Drift watch: the belt\'s own cards').querySelector('.bench-hsub')), 'Cards that ended on the engine commit before (61 cards) and on v1.9.0 (54 cards).');
  assert.equal(text(q(w, '.bench-vw')), 'On the belt, cards on v1.9.0 waited less (4 min against 12 min a card): that moved past its usual range. The other figures stayed in their usual range.');
  const day = (iso) => { const d = new Date(iso); return `${String(d.getMonth() + 1).padStart(2, '0')}/${String(d.getDate()).padStart(2, '0')}`; };
  const dates = Array.from(q(w, '.bench-versions').querySelectorAll('tbody tr'), (r) => text(r.children[1]));
  assert.ok(dates.every((d) => /^\d{2}\/\d{2}$/.test(d)), dates.join(', '));
  assert.equal(dates[5], day(set.hist.runs[0].started), 'the newest version is dated by the start of its run');
});

// Bug it guards: Compare's bars were named by the arm's whole label, which pushed the bar off its row; the mockup names
// each by the first 2 words of its label.
test('Compare, Conveyor against Conveyor, Codex builds: each bar is named by the first 2 words of its arm label', async () => {
  const w = await opened(BH.study(), 'compare');
  const s = act(bp(w), 'cmp-b'); s.value = 'arm:conveyor-codex-claude'; s.dispatchEvent(new w.Event('change'));
  await settle(); await settle();
  const names = Array.from(box(w, 'Cost and time').querySelectorAll('.bench-pair')[0].querySelectorAll('.bench-pl'), text);
  assert.deepEqual(names, ['Conveyor v1.9.0', 'Conveyor, Codex']);
  assert.match(text(box(w, 'Where they differ').querySelector('.bench-note')), /and is labelled as such on the Board\.$/);
});

// Bug it guards: the Not run chip blamed the image fetch for every task not run, but the engine also records a failed
// repository fetch and an unreadable patch as "not run".
test('Live run, a run going with 2 task runs not run: the chip on Not run names each cause the engine counts', async () => {
  const set = BH.live();
  set.hist.runs[0].cols[0].notRun = 2;
  const w = await opened(set, 'run');
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-stat')).map((s) => [text(s.children[0]), text(s.children[1]), text(s.children[2])]).pop(),
    ['2', 'Not run', 'image or repository fetch failed, or patch not read · tried again next run']);
});

// Bug it guards: the Task page lacked the mockup's first step (split), its Task image fact and its three buttons, said
// "From the run" where the mockup says "From the real run", and named the patch's size "Reference fix".
test('Task, 7 arms on one task of the study: the split step, Task image, and the three buttons', async () => {
  const set = BH.study();
  const conv = set.shows[BH.STUDY].tasks[0].cells.find((c) => c.arm === 'conveyor'), first = conv.steps[0];
  conv.steps.unshift({ step: 'split', result: 'ok', time: new Date(Date.parse(first.time) - 60000).toISOString(), tokens: { claude: 0, codex: 0 } });
  const w = await opened(set, 'task');
  const spans = Array.from(page(w).querySelectorAll('.bench-swim span'));
  assert.deepEqual([spans[0].dataset.step, text(spans[0]), spans[0].className, spans[1].dataset.step], ['split', 'split', 'bench-s7', 'build']);
  assert.match(text(page(w).querySelector('.bench-hsub')), /^From the real run r\S+ \(Conveyor v1\.9\.0\)\. Width is time\.$/);
  assert.deepEqual(kv(box(w, 'This task over time')).map(([k]) => k), ['Repository', 'Difficulty', 'Patch size', 'Task image', 'Hidden tests']);
  assert.deepEqual(kv(box(w, 'This task over time')).find(([k]) => k === 'Task image'), ['Task image', 'not kept'], 'the results keep no image size');
  const tools = Array.from(page(w).querySelectorAll('.bench-tools button'));
  assert.deepEqual(tools.map((b) => [text(b), b.disabled]), [['Open the patch', false], ['Open the logs', true], ['Run this task again', true]]);
  assert.match(tools[1].title + tools[2].title, /log.*Board.*one task cannot be run alone/);
  assert.equal(page(w).querySelectorAll('.bench-box details[data-fold^="patch-"]').length, 0, 'the patch is a button, not a fold');
  assert.equal(page(w).querySelectorAll('.bench-tools ~ p').length, 0, 'the patches are shut');
  act(bp(w), 'open-patch').click();
  const shown = Array.from(page(w).querySelectorAll('.bench-tools ~ p'), text);
  assert.equal(shown[0], 'Conveyor v1.9.0: pkg/models.py +9 −3, tests/test_models.py +14 −0');
  assert.equal(shown.length, 7, 'one line for each arm');
  assert.equal(act(bp(w), 'open-patch').getAttribute('aria-expanded'), 'true');
  act(bp(w), 'open-patch').click();
  assert.equal(page(w).querySelectorAll('.bench-tools ~ p').length, 0, 'the same button shuts them');
});

// Bug it guards: the "Good for arms" text copied the mockup's "2 to 10 points" and "200 tasks" for two Conveyor
// versions, where the fixture's own versions differ by 2 to 40 points; Plan a run also said "not reached" of the guard.
test('Plan a run: the usage guard fits the week left, and the gap between two Conveyor versions is the study\'s own', async () => {
  const w = await opened(BH.study(), 'plan');
  assert.deepEqual(kv(q(w, '.bench-before')).find(([k]) => k === 'Usage guard'), ['Usage guard', 'fits in the week left']);
  assert.match(text(q(w, '.bench-before .bench-callout')), / Two Conveyor versions differed by 2 to 40 points in the last study: a 2-point gap needs 5000 tasks\.$/);
});

// Bug it guards: with the guard reached, the chip said the run "would reach the guard; the run stops there" as a
// forecast, while the guard is a state (the engine sends only reached or not) and Start is off, and no run starts.
test('Plan a run, the usage guard reached: the chip says it is reached and Start is off', async () => {
  const held = BH.study();
  held.hist.guard.conveyor = true;
  const w = await opened(held, 'plan');
  assert.deepEqual(kv(q(w, '.bench-before')).find(([k]) => k === 'Usage guard'), ['Usage guard', 'reached: no run starts while it stands']);
  assert.equal(act(bp(w), 'start').disabled, true, 'no run starts while the guard stands');
});

// Bug it guards: the few-task verdict gave every arm the range of an arm that resolved every task (21% to 100%), though
// one arm here resolved nothing: its range is 0% to 79%.
test('Scoreboard, 2 runs of 1 task with one arm unresolved: the verdict gives the ranges of the arms, not 21% to 100% for all', async () => {
  const set = BH.few();
  Object.assign(set.shows[BH.FEW1].tasks[0].cells[3], { resolved: false, result: 'unresolved' });
  const w = await opened(set);
  assert.match(text(q(w, '.bench-vv')), /^Nothing can be told yet\. 4 of 5 arms resolved a task\./);
  assert.match(text(q(w, '.bench-vw')), /only a total break shows: the 95% ranges of the arms run from 0% to 100%\. To tell/);
});

// Bug it guards: the patch note said the arms made "the same fix" when only the line counts matched, though one arm
// changed another file; the engine keeps paths and counts, so the same fix means the same code files with the same counts.
test('Scoreboard, 2 runs of 1 task, one arm editing another file with the same counts: the patch note does not claim the same fix', async () => {
  const set = BH.few();
  set.shows[BH.FEW1].tasks[0].cells[1].patch = [{ path: 'django/db/models/other_module.py', added: 1, removed: 1 }];
  const w = await opened(set);
  const notes = Array.from(page(w).querySelectorAll('.bench-note'), text);
  assert.ok(notes.includes('Real, from the patches the results keep. Only Conveyor, Codex builds v1.7.0 and Conveyor v1.7.0 added a test.'), notes.join(' | '));
});

// Bug it guards: Compare named both bars "Claude with" when two arms' labels share their first 2 words.
test('Compare, Claude with Superpowers against Claude with Caveman: the bars keep apart names', async () => {
  const w = await opened(BH.study(), 'compare');
  const a = act(bp(w), 'cmp-a'), s = act(bp(w), 'cmp-b');
  a.value = 'arm:superpowers'; a.dispatchEvent(new w.Event('change'));
  await settle(); await settle();
  s.value = 'arm:caveman'; s.dispatchEvent(new w.Event('change'));
  await settle(); await settle();
  const names = Array.from(box(w, 'Cost and time').querySelectorAll('.bench-pair')[0].querySelectorAll('.bench-pl'), text);
  assert.deepEqual(names, ['Claude + Superpowers', 'Claude + Caveman']);
});

// Bug it guards: Live run wrote its times as 24-hour with the year first whatever Customize set; the Board's Time and
// Date settings apply to every date and time it writes.
test('Live run, Time set to 24-hour and Date to dd/mm/yyyy: the last run\'s end follows', async () => {
  const w = await opened(BH.few(), 'run', { time: '24-hour', date: 'dd/mm/yyyy' });
  const d = new Date(BH.few().hist.runs[0].ended), p2 = (n) => String(n).padStart(2, '0');
  assert.equal(text(q(w, '.bench-vv')), `The last run ended ${p2(d.getDate())}/${p2(d.getMonth() + 1)}/${d.getFullYear()}, ${p2(d.getHours())}:${p2(d.getMinutes())}, after 9 minutes.`);
});

// Bug it guards: Versions wrote the month before the day whatever the Date in Customize was.
test('Versions, Date set to dd/mm/yyyy: each version is dated day before month', async () => {
  const w = await opened(BH.study(), 'versions', { date: 'dd/mm/yyyy' });
  const n = new Date(BH.study().hist.runs[0].started), p2 = (x) => String(x).padStart(2, '0');
  assert.equal(text(q(w, '.bench-versions').querySelectorAll('tbody tr')[5].children[1]), `${p2(n.getDate())}/${p2(n.getMonth() + 1)}`);
});
