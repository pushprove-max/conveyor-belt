// SPDX-License-Identifier: Apache-2.0
// The Tests page's Test map part (#178): the map's state at the top of the page, Build the test map with its tool and
// the last whole-suite run's time, a bar while the build runs, Stop, and the result in place; and its Benchmarks part
// (#237), the latest drift watch. Shared setup:
// dashboard-view.helpers.mjs (TA.snap()).
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, act, cases, T0, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { snap, tp, reply } = TA;
const S = T0 / 1000;
// A snapshot whose Test map part is <m>.
const withMap = (m) => { const d = snap(); d.panels.tests.data.testMap = m; return d; };
const part = (w) => tp(w).querySelector('.tests-map');
const stateOf = (w) => part(w).querySelector('.tests-map-state').textContent;
const MADE = { state: 'made', sources: 12, tests: 5, age: 3, made: '2026-11-15T10:00:00Z', seconds: 200, tool: 'V8 coverage', toolWhy: null, suiteSec: 180, build: null };

// Bug it guards: a user could not see whether the map was made, how old it was, off, or why it failed, nor why no build
// was offered. Each state shows in words; off and a project with no coverage tool offer no Build.
test('Test map: the part shows made, not made yet, off, failed and no tool, at the top of the page', () => {
  const w = boot({ tab: 'tests' });
  deliver(w, withMap(MADE));
  assert.equal(tp(w).querySelector('.tests').firstElementChild, part(w), 'the part is the first of the page');
  assert.match(stateOf(w), /^Made 12 source files and 5 test files mapped · 3 commits behind main · made .+, in 3:20\.$/);
  next(w, withMap({ ...MADE, state: 'none' }));
  assert.match(stateOf(w), /^Not made yet A card's tests are found by name/);
  assert.ok(act(part(w), 'map-build'), 'a map not made yet can be built');
  next(w, withMap({ state: 'off', tool: null, toolWhy: null, suiteSec: null, build: null }));
  assert.match(stateOf(w), /^Off The pack's test\.map is "off".*remove test\.map from the pack/);
  assert.equal(act(part(w), 'map-build'), null, 'no Build while the map is off');
  next(w, withMap({ ...MADE, state: 'failed', why: 'the run with V8 coverage failed after 9s: test/a.test.js failed under coverage' }));
  assert.match(stateOf(w), /^Failed the run with V8 coverage failed after 9s: test\/a\.test\.js failed under coverage$/);
  next(w, withMap({ ...MADE, state: 'none', tool: null, toolWhy: 'coverage.py (the coverage command) is not installed' }));
  assert.equal(act(part(w), 'map-build'), null, 'no Build with no coverage tool');
  assert.match(part(w).textContent, /No test map can be made: coverage\.py \(the coverage command\) is not installed\./);
});

// Bug it guards (#327): a map made with a test file it could not map (it failed under coverage, or runs only under
// another runner) showed as fully made, with no word of which file was left out or why. The state line counts them;
// a folded list names each with its reason and says the map does not use them; a map with none shows no list.
test('Test map: the files not mapped are counted and listed, folded, with why', () => {
  const w = boot({ tab: 'tests' });
  const why = "it imports claude-code/testing, so it runs only under Claude Code's mod test runner";
  deliver(w, withMap({ ...MADE, notMapped: [{ file: 'test/mod.test.tsx', why }] }));
  assert.match(stateOf(w), /^Made 12 source files and 5 test files mapped, 1 test file not mapped · /);
  const fold = part(w).querySelector('details.tests-map-not');
  assert.ok(fold && !fold.open, 'the list is folded');
  assert.equal(fold.querySelector('summary').textContent, "Test files not mapped: 1. The map does not use them to pick a card's tests.");
  assert.deepEqual(Array.from(fold.querySelectorAll('li'), (li) => li.textContent), [`test/mod.test.tsx: ${why}`]);
  next(w, withMap({ ...MADE, notMapped: [] }));
  assert.equal(part(w).querySelector('details.tests-map-not'), null, 'no file left out, no list');
});

// Bug it guards: the owner could not build the map from the Board, nor see it go or stop it. Before the click the button
// names the tool and the last whole-suite run's time; the click sends testmap build; the part shows it starting,
// waiting for a slot, then a bar of the test files done, with Stop (testmap stop); at the end the result, in place.
test('Test map: Build the test map sends the build, shows a bar of the files done with Stop, then the result', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, withMap(MADE));
  assert.match(part(w).textContent, /Runs the whole suite once with V8 coverage\. The last whole-suite run took 3:00: it takes about that long, or more\. Admins only\./);
  w.reply = reply('conveyor: the test map is being built with V8 coverage');
  act(part(w), 'map-build').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'testmap', args: ['build'], repo: 'sample' }]);
  await settle();
  assert.match(stateOf(w), /Starting: sent to the build machine/, 'answered, it shows starting until a snapshot names the build');
  assert.equal(act(part(w), 'map-build'), null, 'no second Build meanwhile');
  const run = { pid: 7, start: S - 30, end: null, state: 'waiting', reason: null, tool: 'V8 coverage' };
  next(w, withMap({ ...MADE, build: run }));
  assert.match(stateOf(w), /Waiting for a test slot/);
  next(w, withMap({ state: 'running', done: 1, of: 3, started: S - 20, tool: 'V8 coverage', toolWhy: null, suiteSec: 180, build: { ...run, state: 'running' } }));
  const bar = part(w).querySelector('progress');
  assert.deepEqual([bar.value, bar.max, bar.getAttribute('aria-label')], [1, 3, 'Test map: 1 of 3 test files']);
  assert.match(stateOf(w), /Being made: 1 of 3 test files run, 0:20 so far\./);
  w.reply = reply('conveyor: the build of the test map is stopped');
  act(part(w), 'map-stop').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['stop']]);
  await settle();
  next(w, withMap({ ...MADE, seconds: 25, build: { start: S - 30, end: S - 5, state: 'made', reason: null, tool: 'V8 coverage' } }));
  assert.equal(part(w).querySelector('progress'), null, 'ended: no bar');
  assert.match(part(w).querySelector('.tests-map-result').textContent, /^Last build: Made in 0:25 · /);
  assert.ok(act(part(w), 'map-build'), 'Build is offered again');
});

// Bug it guards: a member's Build was refused with nothing said. The server's refusal shows in the part.
test('Test map: a refused Build says why in the part', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, withMap(MADE));
  w.reply = { ok: false, status: 403, text: () => Promise.resolve('only an admin builds the test map') };
  act(part(w), 'map-build').click();
  await settle();
  assert.equal(part(w).querySelector('[role="alert"]').textContent, 'Not started: only an admin builds the test map');
  assert.ok(act(part(w), 'map-build'), 'Build is still offered');
});

// The Benchmarks part (#237) is on the same page, so it shares this file's boot. Bug it guards: the Board did not show
// the latest drift watch, or showed a group of 2 cards as if it meant something; a snapshot with no drift watch shows
// no part.
test('Benchmarks: the latest drift watch shows both groups with their cards, and a group of 2 is called too small', () => {
  const w = boot({ tab: 'tests' });
  const g = (engine, cards, x) => ({ engine, cards, landed: cards, blocked: 0, tokens: x, minutes: 14, reviews: 1, fixes: 0.2, waits: null });
  const d = snap();
  d.panels.tests.data.drift = { before: g('aaaaaaaa1111', 5, 1320), after: g('bbbbbbbb2222', 2, 3000), small: ['after'] };
  deliver(w, d);
  const bench = tp(w).querySelector('.tests-bench');
  assert.equal(bench.querySelector('.tests-drift').textContent, 'Drift watch, engine aaaaaaaa (5 cards) against bbbbbbbb (2 cards): tokens a card 1320 to 3000, '
    + 'minutes a card 14 to 14, reviews to land 1 to 1, fix rounds a card 0.2 to 0.2, blocked 0 to 0, minutes waited a card - to -.');
  assert.deepEqual(Array.from(bench.querySelectorAll('.warn-note'), (p) => p.textContent), ['The after group holds 2 cards: too small to mean anything (fewer than 5 cards).']);
  next(w, snap());
  assert.equal(tp(w).querySelector('.tests-bench'), null, 'no drift watch, no part');
});
