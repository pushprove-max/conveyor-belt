// SPDX-License-Identifier: Apache-2.0
// A card's lint step shows a row for each lint command (#1366), from the record's lint commands. Shared setup:
// dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, next, trackOf, full, cases, openEvery } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const at = (s) => iso(T0 - 1000000 + s * 1000);

const SHELL = 'bash .conveyor/lint-shell.sh {files}';
const RUFF = "command -v ruff >/dev/null || { echo 'lint: missing ruff'; exit 127; }; ruff check --no-fix {files}";
const REASON = 'lint command 1 (bash .conveyor/lint-shell.sh {files}): pass, 4 s; lint command 2 (size, limit 800 lines): pass, 1 s';

// The Every step detail of a card whose steps are the records, as the Board draws it.
function shown(records, now = 'review 1') {
  const w = boot();
  const data = full();
  const card = data.panels.belt.data.cards[0];
  const put = (name) => { card.track = trackOf('+>....', 'review', { since: at(900), records: [
    { name: 'picked', state: 'done', sec: null, at: at(0) }, ...records, { name, state: 'now', sec: null }] }); };
  put(now);
  deliver(w, data);
  const row = () => panel(w, 'belt').querySelector(`li[data-key="sample:${card.card}"]`);
  const d = openEvery(w, row().querySelector('details.track-detail'));
  return { w, d, redraw: (name) => { put(name); next(w, data); return row().querySelector('details.track-detail'); } };
}
const detail = (records) => shown(records).d;

// Bug it guards (#1366): the step showed its commands as one long sentence. Five commands (as in the owner's screenshot)
// are five rows with a short name, a result chip and a time, the whole command on the name's hover and under "Show
// command", and none of the reason's sentence.
test('a lint step with five commands shows five rows, and not the reason sentence', () => {
  const d = detail([{ name: 'lint', state: 'done', sec: 5, at: at(10), why: REASON, lint: [
    { n: 1, run: SHELL, result: 'pass', sec: 4, findings: 0 },
    { n: 2, run: 'bash .conveyor/lint-funcs.sh --max 100 --exempt .conveyor/size-exempt.txt {files}', result: 'pass', sec: 1, findings: 0 },
    { n: 3, run: 'size, limit 800 lines', result: 'pass', sec: 0, findings: 0 },
    { n: 4, run: RUFF, result: 'no files', sec: 0, findings: 0 },
    { n: 5, run: 'bash .conveyor/lint-js.sh {files}', result: 'findings', sec: 0, findings: 0 }] }]);
  const rows = Array.from(d.querySelectorAll('.lint-cmds .lint-cmd'));
  assert.deepEqual(rows.map((r) => [r.querySelector('.lint-cmd-word').textContent, r.querySelector('.chip').textContent.trim(), r.querySelector('.lint-cmd-sec').textContent]), [
    ['lint-shell.sh', 'Pass', '4 s'], ['lint-funcs.sh', 'Pass', '1 s'], ['Size, limit 800 lines', 'Pass', '0 s'],
    ['ruff', 'No files', '0 s'], ['lint-js.sh', 'Findings: 0 of this change', '0 s']]);
  assert.equal(rows[3].querySelector('.lint-cmd-word').title, RUFF, 'the whole command is on the name');
  assert.equal(rows[3].querySelector('.lint-cmd-show code').textContent, RUFF, 'and under Show command');
  assert.equal(d.querySelector('.detail-why'), null, 'the reason sentence is not shown');
});

// Bug it guards (#1366): a command with findings of this change sat among the passing ones with its findings nowhere. It
// comes first, with a Findings chip and its findings under it; an error comes first too, with its reason under it.
test('a command with findings or an error comes first, with its findings under the row', () => {
  const d = detail([{ name: 'lint', state: 'failed', sec: 5, at: at(10), why: REASON, lint: [
    { n: 1, run: SHELL, result: 'pass', sec: 4, findings: 0 },
    { n: 2, run: 'bash .conveyor/lint-js.sh {files}', result: 'findings', sec: 2, findings: 2,
      reported: [{ file: 'src/a.js', line: 7, text: 'Unused variable' }, { file: 'src/b.js', line: 9, text: 'Missing semicolon' }] },
    { n: 3, run: RUFF, result: 'error', sec: 1, findings: 0, why: 'the base run: its worktree could not be made' }] }]);
  const rows = Array.from(d.querySelectorAll('.lint-cmds .lint-cmd'));
  assert.deepEqual(rows.map((r) => r.querySelector('.lint-cmd-word').textContent), ['lint-js.sh', 'ruff', 'lint-shell.sh']);
  assert.equal(rows[0].querySelector('.chip').textContent.trim(), 'Findings: 2 of this change');
  assert.notEqual(rows[0].querySelector('.chip-bad'), null, 'a Findings chip is red');
  assert.equal(rows[1].querySelector('.chip').textContent.trim(), 'Error');
  assert.deepEqual(Array.from(d.querySelectorAll('.lint-finding'), (li) => li.textContent),
    ['src/a.js:7Unused variable', 'src/b.js:9Missing semicolon', 'the base run: its worktree could not be made']);
  assert.equal(rows[0].nextElementSibling.className, 'lint-found-row', 'the findings are under their row');
});

// Bug it guards (#1366): a command with 0 findings of this change (a finding on an unchanged line) sorted ahead of one
// with findings of this change, and the ESLint command of Conveyor setup was named "[", the guard's first word.
test('a command with 0 findings of this change does not come before one with findings; ESLint is named eslint', () => {
  const ESLINT = "[ -x node_modules/.bin/eslint ] || { echo 'lint: missing eslint'; exit 127; }; node_modules/.bin/eslint --max-warnings 0 {files}";
  const d = detail([{ name: 'lint', state: 'failed', sec: 5, at: at(10), why: REASON, lint: [
    { n: 1, run: RUFF, result: 'findings', sec: 1, findings: 0 },
    { n: 2, run: ESLINT, result: 'findings', sec: 2, findings: 1, reported: [{ file: 'a.js', line: 1, text: 'No var' }] }] }]);
  const rows = Array.from(d.querySelectorAll('.lint-cmds .lint-cmd'));
  assert.deepEqual(rows.map((r) => [r.querySelector('.lint-cmd-word').textContent, r.querySelector('.chip').textContent.trim()]),
    [['eslint', 'Findings: 1 of this change'], ['ruff', 'Findings: 0 of this change']]);
});

// Bug it guards (#1366): the whole command showed on hover and tap only. A keyboard reader who tabs to the name sees it
// in the tip, and it closes when the focus leaves.
test('keyboard focus on a command name shows the whole command', () => {
  const { w, d } = shown([{ name: 'lint', state: 'done', sec: 5, at: at(10), why: REASON, lint: [{ n: 1, run: RUFF, result: 'pass', sec: 1, findings: 0 }] }]);
  const word = d.querySelector('.lint-cmd-word');
  word.focus();
  const box = w.document.getElementById('tip');
  assert.ok(box && !box.hidden, 'the tip opens on focus');
  assert.equal(box.textContent, RUFF);
  word.blur();
  assert.equal(box.hidden, true, 'and closes when the focus leaves');
});

// Bug it guards (#1366): a redraw of the card (the next step starts) closed a "Show command" the reader had opened.
test('an open Show command stays open when the card is drawn again', () => {
  const { d, redraw } = shown([{ name: 'lint', state: 'done', sec: 5, at: at(10), why: REASON, lint: [
    { n: 1, run: SHELL, result: 'pass', sec: 4, findings: 0 }, { n: 2, run: RUFF, result: 'pass', sec: 1, findings: 0 }] }]);
  const first = d.querySelectorAll('.lint-cmd-show')[1];
  first.open = true;
  const again = redraw('review 2');
  assert.notEqual(again.querySelectorAll('.lint-cmd-show')[1], first, 'the toggle was drawn again');
  assert.deepEqual(Array.from(again.querySelectorAll('.lint-cmd-show'), (x) => x.open), [false, true]);
});

// Bug it guards (#1366): a line written before the commands were recorded has none, and its reason is all there is: it
// shows as before, as one sentence.
test('a lint step with no commands shows its reason as before', () => {
  const d = detail([{ name: 'lint', state: 'done', sec: 5, at: at(10), why: REASON }]);
  assert.equal(d.querySelector('.lint-cmds'), null);
  assert.equal(d.querySelector('.detail-why').textContent, REASON);
});
