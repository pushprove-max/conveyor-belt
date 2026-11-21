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
    [['Lint clean', 'No new ruff finding in the Python files the patch changes.'], ['Proves the fix', 'The patch adds a test that fails on the base commit and passes with the patch.']]);
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
// the callout on what the results keep) and its "never checked" line. The patch note says what the patches kept show,
// in the mockup's form, but says only what the summary shows: the same code files by the same line counts, not "the same fix".
test('Scoreboard, 2 runs of 1 task: the mockup\'s leaderboard note, patch note, callout and next-run line', async () => {
  const w = await opened(BH.few());
  const notes = Array.from(page(w).querySelectorAll('.bench-note'), text);
  assert.ok(notes.includes('Real, from the patches the results keep. All five changed the same code files by the same line counts; only Conveyor, Codex builds v1.7.0 and Conveyor v1.7.0 added a test.'), notes.join(' | '));
  assert.ok(notes.includes('"Not priced": agent arms report no usage by model today.'), notes.join(' | '));
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

// Bug it guards: the mockup's Cost cell is the figure alone: the Board added " estimate" to an arm priced from its tokens,
// and kept a note on "Estimate" for it. The "Not priced" note stays only while an arm in the table shows "not priced".
test('Scoreboard, 2 runs of 1 task, one agent arm priced from its tokens: its Cost cell is the figure alone, and "Not priced" stays for the others', async () => {
  const set = BH.few();
  set.shows[BH.FEW1].tasks[0].cells.find((c) => c.arm === 'solo').cost = { usd: 0.0123, state: 'estimate' };
  const w = await opened(set);
  const cost = Array.from(q(w, '.bench-leader').querySelectorAll('tbody tr'), (r) => text(r.children[3]));
  assert.ok(cost.includes('$0.01') && !cost.some((c) => /estimate/.test(c)), cost.join(' | '));
  const notes = Array.from(page(w).querySelectorAll('.bench-note'), text);
  assert.ok(notes.includes('"Not priced": agent arms report no usage by model today.') && !notes.some((n) => n.includes('Estimate')), notes.join(' | '));
});

// Bug it guards: a cost note shown when no Cost cell reads "not priced" explains a label the table does not show.
test('Scoreboard, 2 runs of 1 task, every cost known: no cost note', async () => {
  const set = BH.few();
  Object.values(set.shows).forEach((sh) => sh.tasks[0].cells.forEach((c) => { c.cost = { usd: 0.01, state: 'known' }; }));
  const notes = Array.from(page(await opened(set)).querySelectorAll('.bench-note'), text);
  assert.ok(!notes.some((n) => n.includes('Not priced') || n.includes('"Estimate"')), notes.join(' | '));
});

// Bug it guards: Versions said "engine <sha>" and a long belt line where the mockup names the version and says what
// the figure did; its dates were the Board's long stamp where the mockup has month-day with a hyphen ("11-09").
test('Versions, 6 versions on 50 tasks: the drift subtitle and belt line name the version, and the dates are month-day', async () => {
  const set = BH.study();
  const w = await opened(set, 'versions');
  assert.equal(text(box(w, 'Drift watch: the belt\'s own cards').querySelector('.bench-hsub')), 'Cards that ended on the engine commit before (61 cards) and on v1.9.0 (54 cards).');
  assert.equal(text(q(w, '.bench-vw')), 'On the belt, cards on v1.9.0 waited less (4 min against 12 min a card): that moved past its usual range. The other figures stayed in their usual range.');
  const day = (iso) => { const d = new Date(iso); return `${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };
  const dates = Array.from(q(w, '.bench-versions').querySelectorAll('tbody tr'), (r) => text(r.children[1]));
  assert.ok(dates.every((d) => /^\d{2}-\d{2}$/.test(d)), dates.join(', '));
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

// Bug it guards: the Not run chip listed every cause the engine counts (swe_task in conveyor/bench/swe.sh) whatever
// failed, where the mockup says the one that did ("image fetch failed · tried again next run"); the legend said "Not run"
// where the mockup says "Not run (image)".
test('Live run, a run going with 2 task runs not run (an image and a grading): the chip names those causes in the mockup\'s words, and the legend says Not run (image)', async () => {
  const set = BH.live();
  set.hist.runs[0].cols[0].notRun = 2;
  const cells = set.shows[BH.LIVE].tasks.slice(0, 2).map((t) => t.cells[0]);
  Object.assign(cells[0], { resolved: false, result: 'not run: its Docker image could not be fetched or built' });
  Object.assign(cells[1], { resolved: false, result: 'not run: the harness could not grade it (exit 1)' });
  const w = await opened(set, 'run');
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-stat')).map((s) => [text(s.children[0]), text(s.children[1]), text(s.children[2])]).pop(),
    ['2', 'Not run', 'image fetch failed, grading failed · tried again next run']);
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-legend span')).map(text).pop(), 'Not run (image)');
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
  assert.deepEqual(kv(box(w, 'This task over time')).map(([k]) => k), ['Repository', 'Difficulty', 'Patch size', 'Task image']);
  assert.deepEqual(kv(box(w, 'This task over time')).find(([k]) => k === 'Task image'), ['Task image', 'not kept'], 'the results keep no image size');
  const tools = Array.from(page(w).querySelectorAll('.bench-tools button'));
  assert.deepEqual(tools.map((b) => [text(b), b.disabled]), [['Open the patch', false], ['Open the logs', false], ['Run this task again', false]]);
  assert.equal(page(w).querySelectorAll('.bench-box details[data-fold^="patch-"]').length, 0, 'the patch is a button, not a fold');
  assert.equal(page(w).querySelectorAll('.bench-patch, .bench-log').length, 0, 'the patch and the logs are shut');
  act(bp(w), 'open-patch').click();
  const shown = Array.from(page(w).querySelectorAll('.bench-patch'), text);
  assert.deepEqual(shown, ['Conveyor v1.9.0: pkg/models.py +9 −3, tests/test_models.py +14 −0'], 'one patch, not a list of the 7 arms\' patches');
  assert.equal(act(bp(w), 'open-patch').getAttribute('aria-expanded'), 'true');
  act(bp(w), 'open-patch').click();
  assert.equal(page(w).querySelectorAll('.bench-patch').length, 0, 'the same button shuts it');
});

// Bug it guards: Open the logs and Run this task again were always disabled, and Open the patch listed the patch of each
// arm. Open the logs opens the kept log of the task (the saved task log, not the card's step summaries); Run this task
// again sends the arms that ran the task, that one task alone (--task, n 1: n 3 would run the first 3 tasks) on the engine
// the Conveyor arms ran (without --engine the engine is main), with --again, so the engine keeps a new result apart and
// runs the task (without it the saved result is reused and nothing runs).
test('Task, 7 arms on the third task of the study: Open the logs shows the kept log and Run this task again queues that task alone on its engine', async () => {
  const set = BH.study();
  const id = set.shows[BH.STUDY].tasks[2].id;
  set.shows[BH.STUDY].tasks[2].cells.filter((c) => c.arm.startsWith('conveyor')).forEach((c, i) => { c.log = `loop output ${i}\nlast line ${i}`; });
  const w = await opened(set, 'map');
  act(bp(w), `sq-${id}`).click();
  await settle();
  assert.equal(page(w).querySelectorAll('.bench-log').length, 0, 'the logs are shut');
  act(bp(w), 'open-logs').click();
  assert.equal(act(bp(w), 'open-logs').getAttribute('aria-expanded'), 'true');
  const logs = Array.from(page(w).querySelectorAll('.bench-log'));
  assert.deepEqual(logs.map((l) => [text(l.querySelector('b')), l.querySelector('pre').textContent]),
    [['Conveyor v1.9.0', 'loop output 0\nlast line 0'], ['Conveyor, Codex builds v1.9.0', 'loop output 1\nlast line 1']], 'the 2 arms with a kept log, each as saved; the 5 with none are left out');
  act(bp(w), 'open-logs').click();
  assert.equal(page(w).querySelectorAll('.bench-log').length, 0, 'the same button shuts them');
  w.reply = BH.reply('conveyor: run r20261109T170000-9 started');
  act(bp(w), 'run-again').click();
  const [sent] = w.posts.splice(0);
  assert.deepEqual(sent.body, { action: 'bench', args: ['run', '1', '--arm', 'conveyor', '--arm', 'conveyor-codex-claude', '--arm', 'solo-review', '--arm', 'codex-sol', '--arm', 'superpowers', '--arm', 'solo', '--arm', 'caveman', '--task', id, '--engine', '9'.repeat(40), '--again'], repo: 'sample' });
  await settle();
  assert.match(text(q(w, '[data-said="again-' + id + '"]')), /run r20261109T170000-9 started/);
});

// Bug it guards: Run this task again sent the arm names alone, so a task run on an older release was run again on main.
// One run takes one engine, so a task whose Conveyor arms ran on two is not sent at all: the button is off and says why.
test('Task, Conveyor arms that ran the task on two engines: Run this task again is off', async () => {
  const set = BH.study();
  const id = set.shows[BH.STUDY].tasks[2].id;
  set.hist.runs[0].cols.find((c) => c.arm === 'conveyor-codex-claude').engine = '8'.repeat(40);
  const w = await opened(set, 'map');
  act(bp(w), `sq-${id}`).click();
  await settle();
  const b = act(bp(w), 'run-again');
  assert.equal(b.disabled, true);
  assert.match(b.title, /more than one engine/);
  b.click();
  assert.deepEqual(w.posts, [], 'a disabled button sends nothing');
});

// Bug it guards: Run this task again sent every arm that has a cell on the task, also one the usage guard stopped before
// it reached the task (state "not reached"): the rerun then ran an arm that never ran the task.
test('Task, 2 arms of 7 never reached the task: Run this task again sends only the arms that ran it', async () => {
  const set = BH.study();
  const id = set.shows[BH.STUDY].tasks[2].id;
  set.shows[BH.STUDY].tasks[2].cells.filter((c) => ['solo', 'caveman'].includes(c.arm)).forEach((c) => { c.state = 'not reached'; });
  const w = await opened(set, 'map');
  act(bp(w), `sq-${id}`).click();
  await settle();
  w.reply = BH.reply('conveyor: run r20261109T170000-9 started');
  act(bp(w), 'run-again').click();
  const [sent] = w.posts.splice(0);
  assert.deepEqual(sent.body.args.filter((a, i, all) => all[i - 1] === '--arm'),
    ['conveyor', 'conveyor-codex-claude', 'solo-review', 'codex-sol', 'superpowers'], 'the 5 arms that ran it; solo and caveman never reached it');
});

// Bug it guards: when no arm reached the task, Run this task again stayed on and sent `bench swe 1 --task <id> --again`
// with no --arm, so the engine would run its default arms on a task the study never ran.
test('Task, no arm reached the task: Run this task again is off and says so', async () => {
  const set = BH.study();
  const id = set.shows[BH.STUDY].tasks[2].id;
  set.shows[BH.STUDY].tasks[2].cells.forEach((c) => { c.state = 'not reached'; });
  const w = await opened(set, 'map');
  act(bp(w), `sq-${id}`).click();
  await settle();
  const b = act(bp(w), 'run-again');
  assert.equal(b.disabled, true);
  assert.match(b.title, /No arm reached this task/);
  b.click();
  assert.deepEqual(w.posts, [], 'a disabled button sends nothing');
});

// Bug it guards: the "Good for arms" text said "differed ... in the last study" and quoted the smallest gap's task count
// (2 points, 5000 tasks), where the mockup says "differ by 2 to 10 points: a 10-point gap needs 200 tasks", the largest
// gap's; the guard chip said "fits in the week left", a forecast the history cannot give (it keeps only whether the guard
// is reached now, and swe.sh checks it again before each trial), so it says "not reached now; the run stops if it is";
// arms with no guard (a Codex arm, swe_guards) have none to say.
test('Plan a run: the usage guard chip says the guard is not reached now, none for arms with no guard, and the gap between two Conveyor versions is the study\'s largest', async () => {
  const w = await opened(BH.study(), 'plan');
  const guard = () => kv(q(w, '.bench-before')).find(([k]) => k === 'Usage guard')[1];
  const tick = async (arm, on) => { const b = act(bp(w), `arm-${arm}`); b.checked = on; b.dispatchEvent(new w.Event('change')); await settle(); };
  assert.equal(guard(), 'not reached now; the run stops if it is');
  // A bigger plan does not change the chip: it is the state now, not a forecast of the plan's own use.
  const n = act(bp(w), 'plan-n'); n.value = '500'; n.dispatchEvent(new w.Event('input'));
  assert.equal(guard(), 'not reached now; the run stops if it is', 'a plan of 500 tasks: still the state now');
  n.value = '50'; n.dispatchEvent(new w.Event('input'));
  assert.equal(text(q(w, '.bench-before .bench-callout')),
    'Good for arms: a gap of 20% or more shows, and Conveyor against Claude alone was 24 points in the last study. Two Conveyor versions differ by 2 to 40 points: a 40-point gap needs 13 tasks.');
  await tick('conveyor', false); await tick('solo', false); await tick('codex-sol', true);
  assert.equal(guard(), 'none for these arms', 'codex-sol alone: no arm has a guard');
  await tick('conveyor', true);
  assert.equal(guard(), 'not reached now; the run stops if it is', 'conveyor and codex-sol: Conveyor has a guard');
});

// Bug it guards: with the guard reached, the chip must say so as the state it is ("would reach" was a forecast), and Start
// must stay off while no run can start.
test('Plan a run, the usage guard reached: the chip says it is reached now and Start is off', async () => {
  const held = BH.study();
  held.hist.guard.conveyor = true;
  const w = await opened(held, 'plan');
  assert.deepEqual(kv(q(w, '.bench-before')).find(([k]) => k === 'Usage guard'), ['Usage guard', 'reached now: no run starts']);
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
// changed another file. The summary the Board reads holds only each file's path and line counts, never the code, so equal
// files and counts do not make it the same fix either: the note says "changed the same code files by +1 −1" and never
// "the same fix".
test('Scoreboard, 2 runs of 1 task, one arm editing another file with the same counts: the patch note does not claim the same fix', async () => {
  const set = BH.few();
  set.shows[BH.FEW1].tasks[0].cells[1].patch = [{ path: 'django/db/models/other_module.py', added: 1, removed: 1 }];
  const w = await opened(set);
  const notes = Array.from(page(w).querySelectorAll('.bench-note'), text);
  assert.ok(notes.includes('Real, from the patches the results keep. Only Conveyor, Codex builds v1.7.0 and Conveyor v1.7.0 added a test.'), notes.join(' | '));
});

// Bug it guards: when no arm produced a patch (each result has an empty patch summary), the note said "All five changed
// the same code files by +0 −0" though no arm changed a file.
test('Scoreboard, 2 runs of 1 task, no arm with a patch: the patch note does not say the arms changed the same files', async () => {
  const set = BH.few();
  for (const id of [BH.FEW1, BH.FEW2]) for (const c of set.shows[id].tasks[0].cells) c.patch = [];
  const w = await opened(set);
  const notes = Array.from(page(w).querySelectorAll('.bench-note'), text);
  assert.ok(notes.includes('Real, from the patches the results keep.'), notes.join(' | '));
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
  assert.equal(text(q(w, '.bench-vv')), `The last run ended ${p2(d.getDate())}/${p2(d.getMonth() + 1)}/${d.getFullYear()} at ${p2(d.getHours())}:${p2(d.getMinutes())}, after 9 minutes.`);
});

// Bug it guards: Versions wrote the month before the day whatever the Date in Customize was.
test('Versions, Date set to dd/mm/yyyy: each version is dated day before month', async () => {
  const w = await opened(BH.study(), 'versions', { date: 'dd/mm/yyyy' });
  const n = new Date(BH.study().hist.runs[0].started), p2 = (x) => String(x).padStart(2, '0');
  assert.equal(text(q(w, '.bench-versions').querySelectorAll('tbody tr')[5].children[1]), `${p2(n.getDate())}-${p2(n.getMonth() + 1)}`);
});
