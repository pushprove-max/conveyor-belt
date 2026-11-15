// SPDX-License-Identifier: Apache-2.0
// The Release panel on Overview (#27): one wide card for each project that releases with Conveyor, its status chip,
// three steps, the version and one button whose label follows the state (each on a second click), and the changes
// since the tag, closed until opened. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, full, panel, act, settle, cases, STORE } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const HEAD = 'b'.repeat(40), NEW = 'c'.repeat(40);
const URL = 'https://github.com/example/plugin';
// 26 changes since the tag, newest first, each a finding's subject as Conveyor commits it.
const COMMITS = Array.from({ length: 26 }, (_, i) => ({ sha: (100 + i).toString(16).padStart(40, '0'),
  subject: `fix(plugin): [P1] conveyor/foreman/watch-conveyor.sh:${56 + i} Suite status counts cases ${26 - i}. Proof: .conveyor/project.json:33 runs it (#${126 - i})` }));
// The plugin: docs/releases/1.0.0.md on main and no tag yet. The shop: tags, but no docs/releases/ (it ships by its
// own deploy).
function data(run, plugin = {}) {
  const d = full();
  d.panels.release.data.records = [
    { repo: 'plugin', url: URL, suites: run ? [run] : [], release: { tag: null, count: 26, next: '1.0.0', notes: true, written: ['1.0.0'], head: HEAD, releases: true, commits: COMMITS, ...plugin } },
    { repo: 'shop', url: 'https://github.com/example/shop', suites: [], release: { tag: 'v1.33.0', count: 673, next: '1.34.0', notes: false, head: NEW, releases: false, commits: [] } },
  ];
  return d;
}
const RUN = { kind: 'release', version: '1.0.0', step: 'release-prep', sha: HEAD, since: '2026-11-14T08:00:00Z', moved: false, reasons: [] };
const rel = (w) => panel(w, 'release');
const card = (w) => rel(w).querySelector('[data-project="plugin"]');
const chip = (w) => card(w).querySelector('[data-figure="status"]').textContent;
const stepOf = (w, name) => card(w).querySelector(`[data-step="${name}"]`);
const sent = async (w, fn) => { fn(); await settle(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the panel sits in the narrow column and shows a project that does not release with Conveyor; the
// version is the next minor of no tag (0.1.0) though main holds the 1.0.0 notes; nothing says what to do next.
test('D1: one card, for the project that releases with Conveyor: No release yet, notes done, Suite not run, 1.0.0, Run suite on a second press', async () => {
  const w = boot();
  deliver(w, data(null));
  assert.equal(rel(w).dataset.size, 'wide', 'as wide as Landed, not the right column');
  assert.deepEqual(Array.from(rel(w).querySelectorAll('[data-project]'), (x) => x.dataset.project), ['plugin'], 'the shop, with no docs/releases/, is left out');
  assert.equal(card(w).querySelector('[data-figure="tag"]').textContent, 'No release yet');
  assert.equal(card(w).querySelector('[data-figure="count"]').textContent, '26 changes since');
  assert.equal(stepOf(w, 'release-notes').dataset.state, 'done');
  assert.match(stepOf(w, 'release-notes').textContent, /docs\/releases\/1\.0\.0\.md on main: written/);
  assert.equal(stepOf(w, 'full-suite').dataset.state, 'todo');
  assert.equal(chip(w), 'Suite not run');
  assert.equal(card(w).querySelector('[data-field="version"]').value, '1.0.0');
  assert.equal(act(card(w), 'release').textContent, 'Run suite');
  assert.equal(act(card(w), 'release-stop'), null, 'Stop shows only while a run is under way');
  assert.deepEqual(await sent(w, () => act(card(w), 'release').click()), [], 'one press sends nothing');
  // Bug: Run suite also made the tag and the GitHub release once the suite passed: it sends prep, release-prep alone.
  assert.deepEqual(await sent(w, () => act(card(w), 'release').click()), [{ action: 'release-run', args: ['prep', '1.0.0'], repo: 'plugin' }]);
  // Bug: a version typed in place of 1.0.0 kept 1.0.0's notes step and button, then sent the typed one, whose missing
  // notes made release-prep draft them in place of the suite the button named.
  const field = card(w).querySelector('[data-field="version"]');
  // Bug (#33): the redraw put the focus back without preventScroll, so a reader scrolled away was pulled back to the
  // field. jsdom lays nothing out, so the focus call's options are recorded.
  const focused = [], focus = w.HTMLElement.prototype.focus;
  w.HTMLElement.prototype.focus = function (opt) { focused.push(Boolean(opt && opt.preventScroll)); return focus.call(this, opt); };
  field.value = '1.1.0'; field.dispatchEvent(new w.Event('input'));
  w.HTMLElement.prototype.focus = focus;
  assert.deepEqual(focused, [true], 'the redraw focuses the field without scrolling the page');
  assert.equal(stepOf(w, 'release-notes').dataset.state, 'todo');
  assert.match(stepOf(w, 'release-notes').textContent, /docs\/releases\/1\.1\.0\.md on main: missing/);
  assert.equal(chip(w), 'Notes missing');
  assert.equal(act(card(w), 'release').textContent, 'Draft notes');
  assert.equal(w.document.activeElement, card(w).querySelector('[data-field="version"]'), 'the field keeps the focus as the card is drawn again');
  act(card(w), 'release').click();
  assert.deepEqual(await sent(w, () => act(card(w), 'release').click()), [{ action: 'release-run', args: ['prep', '1.1.0'], repo: 'plugin' }]);
  // With no project that releases with Conveyor, one line says so.
  const none = boot(), d = data(null);
  d.panels.release.data.records.splice(0, 1);
  deliver(none, d);
  assert.equal(rel(none).querySelector('.state-title').textContent, 'No project releases with Conveyor.');
});

// Bug this guards: a layout kept in the browser when Release was small (Customize keeps every panel's width) put it
// back in the narrow column. Release takes wide or full only; the queue's kept width stays the owner's.
test('a kept layout with Release small shows it wide, and Customize offers no small width for it', () => {
  const store = { [STORE]: JSON.stringify({ tabs: { overview: { sizes: { release: 'small', queue: 'wide' } } } }) };
  const w = boot({ store });
  deliver(w, data(null));
  assert.equal(rel(w).dataset.size, 'wide');
  assert.equal(panel(w, 'queue').dataset.size, 'wide');
  w.document.getElementById('customize-open').click();
  assert.deepEqual(Array.from(w.document.getElementById('size-release').options, (o) => o.value), ['wide', 'full']);
});

// Bugs this guards: a run under way shows no progress and cannot be stopped from the Board, or a second run is offered.
// Bug: it counted the cases and named the failed cases, not the test files.
test('D2: a run under way shows a progress bar of files done of all, the failed files\' names, Suite running and Stop', async () => {
  const w = boot();
  deliver(w, data({ ...RUN, ended: null, state: 'running', done: 120, of: 1400, failed: 2, cases: ['code.test: breaks', 'code.test: flips'],
    files: { done: 12, of: 140, failed: ['code.test'] } }));
  const bar = stepOf(w, 'full-suite').querySelector('progress');
  assert.deepEqual([bar.value, bar.max], [12, 140]);
  assert.match(stepOf(w, 'full-suite').querySelector('[data-figure="progress"]').textContent, /12 of 140 files done · 1 failed/);
  assert.deepEqual(Array.from(stepOf(w, 'full-suite').querySelectorAll('[data-list="failed"] li'), (x) => x.textContent), ['code.test']);
  assert.equal(chip(w), 'Suite running');
  // #31: the line, a span with a time in it, showed as "[object HTMLSpanElement]".
  const going = stepOf(w, 'full-suite').querySelector('.release-line');
  assert.match(going.textContent, /^Running on bbbbbbbbbbbb · .+ so far$/);
  assert.ok(going.querySelector('time.since'), 'the time is a live time element');
  assert.equal(act(card(w), 'release').hidden, true, 'no second run beside the one under way');
  assert.deepEqual(await sent(w, () => act(card(w), 'release-stop').click()), []);
  assert.deepEqual(await sent(w, () => act(card(w), 'release-stop').click()), [{ action: 'release-run', args: ['stop'], repo: 'plugin' }]);
});

// Bugs this guards: a suite passed on main's head offers no release; once a card lands it still offers one, of a main
// the suite never tested; a release made shows as still to do.
test('D3: passed on main\'s head, Release 1.0.0; a card lands, Main moved and Run again on the new main; released, Released', async () => {
  const w = boot();
  const passed = { ...RUN, ended: '2026-11-14T08:15:00Z', state: 'passed', done: 140, of: 140, failed: 0, cases: [] };
  deliver(w, data(passed));
  assert.equal(chip(w), 'Ready to release');
  assert.equal(stepOf(w, 'full-suite').dataset.state, 'done');
  // #31: the result, commit and time showed as "[object HTMLSpanElement]".
  assert.match(stepOf(w, 'full-suite').querySelector('.release-line').textContent, /^Passed on bbbbbbbbbbbb · .+ ago$/);
  assert.equal(act(card(w), 'release').textContent, 'Release 1.0.0');
  // Release alone sends release-run <version>, the one that makes the tag and the GitHub release.
  act(card(w), 'release').click();
  assert.deepEqual(await sent(w, () => act(card(w), 'release').click()), [{ action: 'release-run', args: ['1.0.0'], repo: 'plugin' }]);
  next(w, data(passed, { head: NEW, count: 27 }));
  assert.equal(chip(w), 'Main moved since the suite');
  assert.match(stepOf(w, 'full-suite').querySelector('.release-line').textContent, /^Passed on bbbbbbbbbbbb · .+ ago · main has moved since$/);
  assert.equal(act(card(w), 'release').textContent, 'Run again on the new main');
  assert.deepEqual(await sent(w, () => act(card(w), 'release').click()), []);
  assert.deepEqual(await sent(w, () => act(card(w), 'release').click()), [{ action: 'release-run', args: ['prep', '1.0.0'], repo: 'plugin' }]);
  next(w, data({ ...passed, step: 'release', state: 'released' }, { tag: 'v1.0.0', count: 2, head: NEW, next: '1.1.0', notes: false }));
  assert.equal(chip(w), 'Released');
  assert.equal(stepOf(w, 'release').dataset.state, 'done');
});

// Bug this guards: every change since the tag was listed open, as a raw subject with its hash, a finding's file:line
// and its "Proof:" text.
test('D4: the changes are closed under "Show 26 changes"; open, each is its issue\'s title, linked, no hash or Proof:, 10 at a time', () => {
  const w = boot();
  deliver(w, data(null));
  const box = card(w).querySelector('details[data-list="changes"]');
  assert.equal(box.open, false);
  assert.equal(box.querySelector('summary').textContent, 'Show 26 changes');
  box.open = true;
  const lines = () => Array.from(box.querySelectorAll('.release-change'));
  assert.equal(lines().length, 10);
  assert.equal(lines()[0].textContent, '#126 Suite status counts cases 26.', 'newest first, the title alone');
  assert.equal(lines()[0].querySelector('a').href, `${URL}/issues/126`);
  for (const l of lines()) assert.doesNotMatch(l.textContent, /Proof:|watch-conveyor\.sh|[0-9a-f]{7}|\(#/, l.textContent);
  box.querySelector('[data-act="list-more"]').click();
  assert.equal(lines().length, 20);
  // The snapshot lists only the newest changes (100): those it does not list are counted, not left out unsaid.
  next(w, data(null, { count: 130 }));
  assert.match(card(w).querySelector('details[data-list="changes"]').textContent, /Show 130 changes[\s\S]*\b104 older changes are not listed here\./);
});

// Bug this guards: a refusal's reasons were one list under the run, so the owner could not tell which step to fix.
test('D5: a refused release shows each reason under the step it belongs to', () => {
  const w = boot();
  deliver(w, data({ ...RUN, step: 'release', ended: '2026-11-14T08:15:00Z', state: 'refused', done: 140, failed: 0, cases: [], moved: true,
    reasons: ['docs/releases/1.0.0.md breaks the release notes style', 'main moved while the suite ran, from bbbbbbbbbbbb to cccccccccccc', 'the privacy check found 1 hit in the changes since the first commit'] }));
  const reasons = (name) => Array.from(stepOf(w, name).querySelectorAll('[data-list="reasons"] li'), (x) => x.textContent);
  assert.deepEqual(reasons('release-notes'), ['docs/releases/1.0.0.md breaks the release notes style']);
  assert.deepEqual(reasons('full-suite'), ['main moved while the suite ran, from bbbbbbbbbbbb to cccccccccccc']);
  assert.deepEqual(reasons('release'), ['the privacy check found 1 hit in the changes since the first commit']);
  assert.equal(stepOf(w, 'release').dataset.state, 'failed');
});
