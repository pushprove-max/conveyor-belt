// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab against the owner's approved mockup (#1198, slice 1 of #1197): each item the mockup has that the
// tab lacked, and each text the mockup words differently, on the 7 pages, with the fixture's figures where the mockup's
// are made up (BH.study(), 7 arms on 50 tasks; BH.few(), the 2 runs of 1 task; BH.live(), a run going). The tests use
// jsdom only. Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { boot, settle, act, cases, BH } from './dashboard-view.helpers.mjs';

// A page of the repository (a name with no folder is a page of docs/), its bold marks taken out and its lines joined. Defined in
// this file, not in the helpers: the bug check puts only the card's test files on main's code, where a new helper is missing.
const guide = (name) => readFileSync(new URL(`../../../${name.includes('/') ? name : `docs/${name}`}`, import.meta.url), 'utf8').replace(/\*\*/g, '').replace(/\s+/g, ' ');
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
  assert.deepEqual(chip('Hidden tests'), ['needs the grader\'s report kept', 'Today the results keep only resolved yes or no']);
  assert.deepEqual(chip('Patch quality'), ['needs the reference fix\'s size kept', 'Today the reference fix is removed after grading']);
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
    [['Lint clean', 'No new pyflakes finding (ruff, rules F) in the Python files the patch changes.'], ['Proves the fix', 'The patch adds a test that fails on the base commit and passes with the patch.']]);
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
// as "made the same one-line fix", said only when the arms' patches hold the same code files by the same counts.
test('Scoreboard, 2 runs of 1 task: the mockup\'s leaderboard note, patch note, callout and next-run line', async () => {
  const w = await opened(BH.few());
  const notes = Array.from(page(w).querySelectorAll('.bench-note'), text);
  assert.ok(notes.includes('Real, from the patches the results keep. All five made the same one-line fix; only Conveyor, Codex builds v1.7.0 and Conveyor v1.7.0 added a test.'), notes.join(' | '));
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
  assert.ok(guide('board.md').includes('Not run has a chip with their causes and "tried again next run"'), 'docs/board.md names the chip of Not run and its words');
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
  assert.deepEqual(kv(box(w, 'This task over time')).find(([k]) => k === 'Task image'), ['Task image', 'not kept'], 'a result from before the engine kept the image size');
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

// Bug it guards (#1223): the Task page's Task image row was a hard-coded "not kept". The engine now keeps each task image's
// size in bytes (imageBytes) with the result, and the row says it as the mockup does: "4.1 GB, kept"; a small image in MB.
const imageRow = async (bytes) => {
  const set = BH.study();
  set.shows[BH.STUDY].tasks[0].cells[0].imageBytes = bytes;
  const w = await opened(set, 'task');
  return kv(box(w, 'This task over time')).find(([k]) => k === 'Task image');
};
test('Task, a result that keeps a task image of 4.1 GB: the Task image row says 4.1 GB, kept', async () => {
  assert.deepEqual(await imageRow(4.1e9), ['Task image', '4.1 GB, kept']);
});
test('Task, a result that keeps a task image of 650 MB: the Task image row says 650 MB, kept', async () => {
  assert.deepEqual(await imageRow(650e6), ['Task image', '650 MB, kept']);
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
  // Bug it guards: while the Board waits for the answer, the button was off with a hover title alone; the page said nothing of why.
  assert.equal(act(bp(w), 'run-again').disabled, true);
  assert.equal(text(q(w, '.bench-again-why')), 'The Board waits for the answer to the last action.');
  assert.ok(guide('board.md').includes('The Board waits for the answer to an action that you sent.'), 'docs/board.md lists the wait among the reasons the button is off');
  await settle();
  assert.equal(q(w, '[data-said="again-' + id + '"]'), null, 'the mockup gives Run this task again no answer line');
  assert.equal(q(w, '.bench-again-why'), null, 'a button that is on gives no reason');
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
  assert.match(text(q(w, '.bench-again-why')), /more than one engine/, 'the reason shows on the page, not only in the hover title');
  assert.ok(guide('board.md').includes('ran the task on two engines, or on one that is not known'), 'docs/board.md lists the engine reason');
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
  assert.match(text(q(w, '.bench-again-why')), /No arm reached this task/, 'the reason shows on the page, not only in the hover title');
  assert.ok(guide('board.md').includes('No arm reached the task.'), 'docs/board.md lists the no-arm reason');
  b.click();
  assert.deepEqual(w.posts, [], 'a disabled button sends nothing');
});

// Bug it guards (#1436): the guide's list of reasons Run this task again is off fell behind the page (it left out the wait for
// the last action's answer, checked in the case above); each reason the page gives has its line in the list, here the task that
// is not in the pinned order, which no run can reach: the page says so under the buttons.
test('Task, a task that is not in the pinned order: Run this task again is off and says so', async () => {
  const set = BH.study();
  const id = set.shows[BH.STUDY].tasks[2].id;
  const w = await opened(set, 'map');
  act(bp(w), `sq-${id}`).click();
  await settle();
  // The square comes from the pinned order, so the task leaves it while its page is open: the press of Run this task again
  // reads the history anew, and the next read has an order without the task.
  set.hist.order = set.hist.order.filter((t) => t !== id);
  w.reply = BH.reply('conveyor: run r20261109T170000-9 started');
  act(bp(w), 'run-again').click();
  w.posts.splice(0);
  await settle();
  const b = act(bp(w), 'run-again');
  assert.equal(b.disabled, true);
  assert.equal(text(q(w, '.bench-again-why')), 'The task is not in the pinned order, so no run can reach it.');
  assert.ok(guide('board.md').includes('The task is not in the pinned order.'), 'docs/board.md lists the pinned-order reason');
  b.click();
  assert.deepEqual(w.posts, [], 'a disabled button sends nothing');
});

// Bug it guards: with no receipt line, a refusal of the build machine (the usage guard reached, a run already going) was hidden
// too, so a press of Run this task again that failed looked like nothing happened.
test('Task, the build machine refuses Run this task again: the refusal shows under the buttons', async () => {
  const set = BH.study();
  const id = set.shows[BH.STUDY].tasks[2].id;
  const w = await opened(set, 'map');
  act(bp(w), `sq-${id}`).click();
  await settle();
  w.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: the usage guard is reached: no SWE-bench run starts while it stands') };
  act(bp(w), 'run-again').click();
  await settle();
  const said = q(w, '[data-said="again-' + id + '"]');
  assert.match(text(said), /^Not done: .*usage guard is reached/, text(page(w)));
  assert.ok(said.classList.contains('bench-said-bad'));
  assert.equal(act(bp(w), 'run-again').disabled, false, 'a refusal leaves the button on');
});

// Bug it guards: while a run goes the button was off with a hover title alone; the page said nothing of why.
test('Task, a run goes now: Run this task again is off and the page says why under the buttons', async () => {
  const w = await opened(BH.live(), 'task');
  const b = act(bp(w), 'run-again');
  assert.equal(b.disabled, true);
  assert.equal(text(q(w, '.bench-again-why')), 'A run goes now: this task can run again when it ends.');
  assert.ok(guide('board.md').includes('A run goes.'), 'docs/board.md lists the running-run reason');
  b.click();
  assert.deepEqual(w.posts, [], 'a disabled button sends nothing');
});

// Bug it guards (the 50-task fixture): the Live run guard sentence said "The usage guard is reached: the run stops at the end
// of the task it is on." where the mockup has only the share of the week left and what the run needs.
test('Live run, the usage guard reached: no sentence of its own, the mockup\'s percentage sentence stands', async () => {
  const set = BH.live();
  set.hist.guard.conveyor = true;
  Object.assign(set.shows[BH.LIVE].run, { weekStart: { conveyor: 40, agent: 40, shared: false }, weekLeft: { conveyor: 31, agent: 33, shared: false } });
  set.shows[BH.LIVE].run.cols.forEach((c) => { c.ran = c.done; });
  const said = text(q(await opened(set), '.bench-vw'));
  assert.doesNotMatch(said, /guard is reached|stops at the end/, said);
  assert.match(said, /The usage guard has 31% of the week left; this run needs about 32% more\.$/, said);
});

// Bug it guards: a last run's cell with no grade showed "stopped", "not started" or "not run" chips, which the mockup does not
// have (it has resolved and unresolved): the cell says not kept.
for (const [name, cell] of [['stopped by you', { state: 'interrupted' }], ['not run (image)', { result: 'not run: image fetch failed' }]]) {
  test(`Live run, the last run of one task with a cell ${name}: the chip says not kept`, async () => {
    const set = BH.few(), run = set.shows[BH.FEW1];
    Object.assign(run.tasks[0].cells[0], { result: null, resolved: undefined }, cell);
    const w = await opened(set, 'run');
    assert.ok(!/stopped|not started|not run/.test(text(q(w, '.bench-t'))), text(q(w, '.bench-t')));
    assert.equal(text(q(w, '.bench-t tbody tr td:nth-child(2)')), 'not kept');
  });
}

// Bug it guards: the "Good for arms" text said "differed ... in the last study" and quoted the smallest gap's task count
// (2 points, 5000 tasks), where the mockup says "differ by 2 to 10 points: a 10-point gap needs 200 tasks", the largest
// gap's; arms with no guard (a Codex arm, swe_guards) have no state of it kept.
test('Plan a run: the gap between two Conveyor versions is the study\'s largest, and arms with no guard say not kept', async () => {
  const w = await opened(BH.study(), 'plan');
  const guard = () => kv(q(w, '.bench-before')).find(([k]) => k === 'Usage guard')[1];
  const tick = async (arm, on) => { const b = act(bp(w), `arm-${arm}`); b.checked = on; b.dispatchEvent(new w.Event('change')); await settle(); };
  assert.equal(text(q(w, '.bench-before .bench-callout')),
    'Good for arms: a gap of 20% or more shows, and Conveyor against Claude alone was 24 points in the last study. Two Conveyor versions differ by 2 to 40 points: a 40-point gap needs 13 tasks.');
  await tick('conveyor', false); await tick('solo', false); await tick('codex-sol', true);
  assert.equal(guard(), 'not kept', 'codex-sol alone: no arm has a guard');
});

// Bug it guards (#1223): the guard chip said "not reached now; the run stops if it is", a state, where the mockup says
// whether the plan "fits in the week left" or "would reach the guard; the run stops there". The engine now keeps the
// guard's share of the week left with each run (weekStart, weekLeft, and the trials a col ran) and in history (weekLeft):
// the chip sets the plan's trials times the share a trial used against the share left. Here a Conveyor trial used 0.09% of
// the week (9 points over 100 trials) and 31% is left: 50 tasks, all kept, need none; 500 tasks need about 40%.
test('Plan a run, with the guard\'s share of the week kept: the chip says fits in the week left, or would reach the guard', async () => {
  const set = BH.study();
  set.hist.weekLeft = { conveyor: 31, agent: 31, shared: false, stop: 2 };
  Object.assign(set.hist.runs[0], { weekStart: { conveyor: 40, agent: 40, shared: false }, weekLeft: { conveyor: 31, agent: 35, shared: false } });
  set.hist.runs.forEach((r) => r.cols.forEach((c) => { c.ran = c.done; }));
  const w = await opened(set, 'plan');
  const guard = () => kv(q(w, '.bench-before')).find(([k]) => k === 'Usage guard')[1];
  assert.equal(guard(), 'fits in the week left', '50 tasks, every result kept: no trial to run');
  const n = act(bp(w), 'plan-n'); n.value = '500'; n.dispatchEvent(new w.Event('input'));
  assert.equal(guard(), 'would reach the guard; the run stops there', '450 Conveyor trials at 0.09% each: about 40% of the week, 31% left');
});

// Bug it guards (#1223, review E1): the chip compared the plan's use with the share left, though the guard stops new trials
// at its own percent (98 used: 2 left, history's weekLeft.stop), so a plan that fits in the week left but ends under the
// stop said "fits". Here 3% is left and the guard stops at 2% left: 22 trials at 0.09% (about 2%) leave 1%, under the stop.
test('Plan a run, a plan that fits in the week left but ends past the guard\'s stop: the chip says would reach the guard', async () => {
  const set = BH.study();
  set.hist.weekLeft = { conveyor: 3, agent: 3, shared: false, stop: 2 };
  Object.assign(set.hist.runs[0], { weekStart: { conveyor: 40, agent: 40, shared: false }, weekLeft: { conveyor: 31, agent: 35, shared: false } });
  set.hist.runs.forEach((r) => r.cols.forEach((c) => { c.ran = c.done; }));
  const w = await opened(set, 'plan');
  const n = act(bp(w), 'plan-n'); n.value = '72'; n.dispatchEvent(new w.Event('input'));
  assert.equal(kv(q(w, '.bench-before')).find(([k]) => k === 'Usage guard')[1], 'would reach the guard; the run stops there', '22 trials at 0.09%: 1.98 of the 3 left, 2 is the stop');
});

// Bug it guards (#1226): with the guard off the engine keeps stop "off", but the chip priced the plan against a stop of 0 and
// said "would reach the guard; the run stops there" when 3% is left and the plan needs 4%, though the guard is off.
// Bug it guards (#1233): with the guard off the chip said "off; the guard will not stop the run", a sentence the mockup does
// not have; it uses "fits in the week left", as the guard cannot stop the plan.
test('Plan a run, the guard off: the chip says fits in the week left, not the guard will not stop the run', async () => {
  const set = BH.study();
  set.hist.weekLeft = { conveyor: 3, agent: 3, shared: false, stop: 'off' };
  Object.assign(set.hist.runs[0], { weekStart: { conveyor: 40, agent: 40, shared: false }, weekLeft: { conveyor: 31, agent: 35, shared: false } });
  set.hist.runs.forEach((r) => r.cols.forEach((c) => { c.ran = c.done; }));
  const w = await opened(set, 'plan');
  const n = act(bp(w), 'plan-n'); n.value = '50'; n.dispatchEvent(new w.Event('input'));
  assert.equal(kv(q(w, '.bench-before')).find(([k]) => k === 'Usage guard')[1], 'fits in the week left', 'the guard is off: the plan fits whatever it uses of the 3% left');
  assert.ok(!text(page(w)).includes('will not stop the run'), 'the removed sentence is nowhere on the page');
});

// Bug it guards (#1233, review E1): with the guard off and no reading of the week left (the engine keeps null), the chip said
// "fits in the week left" before it looked at the reading. With no share left kept, it says "not kept".
test('Plan a run, the guard off and no share of the week left kept: the chip says not kept', async () => {
  const set = BH.study();
  set.hist.weekLeft = { conveyor: null, agent: null, shared: false, stop: 'off' };
  const w = await opened(set, 'plan');
  assert.equal(kv(q(w, '.bench-before')).find(([k]) => k === 'Usage guard')[1], 'not kept', 'weekLeft {conveyor: null, agent: null, stop: "off"}');
});

// Bug it guards (#1223, review E2): Conveyor and Claude alone read one login, so a run of both arms that used 9 points
// kept the same drop for both guards, and the chip priced each Conveyor trial at 9 / 100 instead of 9 / 300 (all trials of
// the run). With the run's shared: true the rate is 0.03% a trial: 450 trials need about 13%, and 29% is free to use.
test('Plan a run, one run of both guards on one login: the share used is spread over the trials of both', async () => {
  const set = BH.study();
  set.hist.weekLeft = { conveyor: 31, agent: 31, shared: true, stop: 2 };
  Object.assign(set.hist.runs[0], { weekStart: { conveyor: 40, agent: 40, shared: true }, weekLeft: { conveyor: 31, agent: 31, shared: true } });
  set.hist.runs.forEach((r) => r.cols.forEach((c) => { c.ran = c.done; }));
  const w = await opened(set, 'plan');
  const n = act(bp(w), 'plan-n'); n.value = '500'; n.dispatchEvent(new w.Event('input'));
  assert.equal(kv(q(w, '.bench-before')).find(([k]) => k === 'Usage guard')[1], 'fits in the week left', '450 Conveyor trials at 9 / 300 trials: about 13%');
});

// Bug it guards (#1223): a run from before the engine kept the share of the week left gave the chip nothing to say: it said
// a state the mockup does not have. With none kept the chip says "not kept", for the history's share and for a trial's use.
test('Plan a run, no share of the week kept by any run: the chip says not kept', async () => {
  const set = BH.study();
  set.hist.weekLeft = { conveyor: 31, agent: 31, shared: false, stop: 2 };
  const w = await opened(set, 'plan');
  assert.deepEqual(kv(q(w, '.bench-before')).find(([k]) => k === 'Usage guard'), ['Usage guard', 'not kept'], 'the share left now is kept, what a trial uses is not');
});

// Bug it guards: with the guard reached, Start must stay off while no run can start; the chip says the mockup's "would
// reach the guard; the run stops there", not "reached now: no run starts".
test('Plan a run, the usage guard reached: the chip says would reach the guard and Start is off', async () => {
  const held = BH.study();
  held.hist.guard.conveyor = true;
  const w = await opened(held, 'plan');
  assert.deepEqual(kv(q(w, '.bench-before')).find(([k]) => k === 'Usage guard'), ['Usage guard', 'would reach the guard; the run stops there']);
  assert.equal(act(bp(w), 'start').disabled, true, 'no run starts while the guard stands');
});

// Bug it guards (#1223): the Live run page said "The usage guard's week left: not kept." though the guard's reading is the
// run's own to keep. With the run's kept share it says the mockup's sentence: 31% left, and the run needs what its trials so
// far used (40 less 31: 9 points over the 22 Conveyor-arm trials done) times the 78 left on those arms. A run from before
// the engine kept it says not kept.
const liveGuard = async (week) => {
  const set = BH.live();
  const line = set.shows[BH.LIVE].run;
  line.cols.forEach((c) => { c.ran = c.done; });
  Object.assign(line, week);
  return text(q(await opened(set), '.bench-vw'));
};
test('Live run, a run from before the share of the week was kept: the usage guard sentence says not kept', async () => {
  assert.match(await liveGuard({}), /Spent \$61\.24 of the \$[\d.]+ estimate\. The usage guard's week left: not kept\.$/);
});
test('Live run, with the guard\'s share of the week kept: the mockup\'s percentage sentence', async () => {
  assert.match(await liveGuard({ weekStart: { conveyor: 40, agent: 40, shared: false }, weekLeft: { conveyor: 31, agent: 33, shared: false } }),
    /The usage guard has 31% of the week left; this run needs about 32% more\.$/, 'the tightest guard, 9 / 22 × 78');
});
// Bug it guards (#1223, review E2): on one login the 9 points the run used are the use of the trials of every arm with a guard, not of
// the arms of the tightest guard alone: 9 over the 63 trials done by the 6 arms with a guard (22 Conveyor, 41 Claude), times
// the 237 trials they have left (78 and 159): about 34%, not 32%.
test('Live run, both guards on one login: the share the run needs is spread over the trials of every arm that has a guard', async () => {
  const said = await liveGuard({ weekStart: { conveyor: 40, agent: 40, shared: true }, weekLeft: { conveyor: 31, agent: 31, shared: true } });
  assert.match(said, /The usage guard has 31% of the week left; this run needs about 34% more\.$/, said);
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
// changed another file. "Made the same one-line fix" is said only when the arms hold the same code files by the
// same counts.
test('Scoreboard, 2 runs of 1 task, one arm editing another file with the same counts: the patch note does not claim the same fix', async () => {
  const set = BH.few();
  set.shows[BH.FEW1].tasks[0].cells[1].patch = [{ path: 'django/db/models/other_module.py', added: 1, removed: 1 }];
  const w = await opened(set);
  const notes = Array.from(page(w).querySelectorAll('.bench-note'), text);
  assert.ok(notes.includes('Real, from the patches the results keep. Only Conveyor, Codex builds v1.7.0 and Conveyor v1.7.0 added a test.'), notes.join(' | '));
});

// Bug it guards (review E3): the note counted its lines wrong when the arms changed more than one file: it says
// the larger of the added and removed lines, for the patches of every arm alike.
test('Scoreboard, 2 runs of 1 task, every arm changing two files by the same counts: the patch note says how many lines', async () => {
  const set = BH.few();
  for (const id of [BH.FEW1, BH.FEW2]) for (const c of set.shows[id].tasks[0].cells) c.patch = [{ path: 'django/db/a.py', added: 2, removed: 1 }, { path: 'django/db/b.py', added: 3, removed: 0 }];
  const w = await opened(set);
  const notes = Array.from(page(w).querySelectorAll('.bench-note'), text);
  assert.ok(notes.some((n) => /^Real, from the patches the results keep\. All five made the same 5-line fix/.test(n)), notes.join(' | '));
});

// Bug it guards: when no arm produced a patch (each result has an empty patch summary), the note said "All five made
// the same 0-line fix" though no arm changed a file.
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

// Bug it guards (#1230): the next run's missing cost and time were worded "Cost not priced," and "machine time not kept.",
// where the mockup puts "not kept" in the place of the figure. The old lint wording must be gone from the page too.
test('Scoreboard, 7 arms on 50 tasks, results that kept no cost and no minutes: each missing figure says not kept as the mockup does', async () => {
  const set = BH.study();
  set.shows[BH.STUDY].tasks.flatMap((t) => t.cells).forEach((c) => Object.assign(c, { cost: null, minutes: null }));
  const w = await opened(set);
  const tied = text(box(w, 'Next run to make').querySelector('li'));
  assert.match(tied, /tasks, 12%\. Cost: not kept, machine time: not kept\. open question$/, tied);
  const all = text(page(w));
  for (const gone of ['default ruff rules', 'Cost not priced', 'machine time not kept', 'cost not known']) assert.ok(!all.includes(gone), `the Scoreboard no longer says "${gone}"`);
});

// Bug it guards (#1230): with no cost kept for the two arms, the few page's next run said "cost not known" in a sentence
// of its own; the mockup's place for a missing figure says "not kept".
test('Scoreboard, 2 runs of 1 task, arms with no per-task cost kept: the next run says not kept', async () => {
  const set = BH.few();
  set.hist.arms.forEach((a) => { a.perTask = null; });
  const w = await opened(set);
  const lis = Array.from(box(w, 'Next run to make').querySelectorAll('li'), text);
  assert.deepEqual(lis.slice(0, 2), ['Is Conveyor better than Claude alone? 50 tasks, 2 arms: not kept. Shows a 10-task difference.', 'Does v1.7.0 work at all? 5 tasks, Conveyor only: not kept.']);
});

// Bug it guards: Versions wrote the month before the day whatever the Date in Customize was.
test('Versions, Date set to dd/mm/yyyy: each version is dated day before month', async () => {
  const w = await opened(BH.study(), 'versions', { date: 'dd/mm/yyyy' });
  const n = new Date(BH.study().hist.runs[0].started), p2 = (x) => String(x).padStart(2, '0');
  assert.equal(text(q(w, '.bench-versions').querySelectorAll('tbody tr')[5].children[1]), `${p2(n.getDate())}-${p2(n.getMonth() + 1)}`);
});
