// SPDX-License-Identifier: Apache-2.0
// Issue 1342: with Show at "All projects", the Control, Rules, Tests and Benchmarks tabs hold one project at a time, so
// they showed the project picked last, with nothing on the tab saying it was one project only. They now show a choice
// of project and no project's data; a pick there sets the same filter as Show in the machine head.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { clone, boot, deliver, next, full, iso, T0, panel, pickProject, tabBtn, cases, order, act, settle, ruled, STORE, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const REPOS = ['sample', 'widgetshop'];
const choice = (w, id) => panel(w, id).querySelector('[data-act="pick-project"]');
const shown = (w) => w.document.querySelector('#machine-head [data-act="project"]').value;

// Two projects on the host: each part that holds one project at a time carries widgetshop under others.
function two() {
  const d = full(), p = d.panels;
  p.machine.data.repos = REPOS;
  p.machine.data.projects = [p.machine.data.projects[0], { ...clone(p.machine.data.projects[0]), repo: 'widgetshop' }];
  p.board.data = { ...p.board.data, repos: REPOS, others: { widgetshop: { ...p.board.data, repo: 'widgetshop', building: [], review: [], needs: [] } } };
  p.rules.data = { ...p.rules.data, repos: REPOS, others: { widgetshop: { ...p.rules.data, repo: 'widgetshop' } } };
  p.tests.data = { ...p.tests.data, repos: REPOS, others: { widgetshop: { repo: 'widgetshop', tests: { ...clone(p.tests.data.tests), files: [] }, machine: p.tests.data.machine } } };
  p.bench.data = { ...p.bench.data, repos: REPOS, others: { widgetshop: { ...clone(p.bench.data), repo: 'widgetshop' } } };
  return d;
}

// What each panel the tab shows (but the machine's, which lists every project) has in its body: the choice and nothing
// else, so no project's controls, rows or "Reading the runs…" sit beside it.
function onlyChoice(w, where) {
  const ids = order(w).filter((id) => id !== 'machine');
  assert.ok(ids.length, `${where}: the tab shows panels`);
  for (const id of ids) {
    const body = panel(w, id).querySelector('.panel-body');
    assert.deepEqual(Array.from(body.children, (c) => c.classList.contains('state')), [true], `${where}: ${id} shows the choice and nothing else (${body.innerHTML.slice(0, 160)})`);
  }
}

// Bug: after Show went back to "All projects", each of these tabs kept the project picked last and drew its data, so
// the owner read it as "all projects" showing one.
test('Show at All projects after one project: Control, Rules, Tests and Benchmarks show the project choice and none of the first project\'s data', () => {
  const w = boot({ tab: 'control' });
  deliver(w, two());
  pickProject(w, 'sample');
  assert.ok(panel(w, 'board').querySelector('.bcard'), 'with sample picked, the Board shows its cards');
  // Each tab is drawn with sample first (the Benchmarks tab then waits on its history), then Show goes to every project.
  for (const tab of ['rules', 'tests', 'bench']) tabBtn(w, tab).click();
  pickProject(w, '');
  const url = w.location.href;
  assert.equal(shown(w), '', `Show says every project (${url})`);
  for (const [tab, id] of [['bench', 'bench'], ['tests', 'tests'], ['rules', 'rules'], ['control', 'board-loop']]) {
    tabBtn(w, tab).click();
    assert.ok(choice(w, id), `${tab}: the project choice (${url})`);
    assert.match(panel(w, id).textContent, /holds one project's settings/, `${tab}: it says it holds one project`);
    onlyChoice(w, tab);
  }
  assert.equal(panel(w, 'board').querySelector('.panel-title').textContent, 'Board', 'Control: the heading names no project');
});

// Bug: a pick in the choice must be the filter itself, or the machine head would say All projects over one project.
test('A project picked from the choice shows on the tab, and Show in the machine head names it', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, two());
  assert.ok(choice(w, 'rules'), 'Show starts at every project: the choice');
  choice(w, 'rules').click();
  const url = new URL(w.location.href).searchParams;
  assert.equal(shown(w), 'sample', 'Show names the project picked');
  assert.deepEqual([url.get('project'), url.get('repo')], ['sample', 'sample'], 'the address keeps it');
  assert.equal(choice(w, 'rules'), null, 'the choice is gone');
  assert.equal(panel(w, 'rules').querySelector('.panel-title').textContent, 'Rules: sample');
  assert.ok(panel(w, 'rules').querySelector('.rules-row'), 'its rules');
  pickProject(w, '');
  const again = panel(w, 'rules').querySelector('[data-project="widgetshop"]');
  assert.ok(again, 'the choice lists each project');
  again.click();
  assert.equal(shown(w), 'widgetshop');
  assert.equal(panel(w, 'rules').querySelector('.panel-title').textContent, 'Rules: widgetshop');
});

// Guard: a panel that lists rows of every project (projects: true) is not turned into a choice.
test('Show at All projects: a panel that lists every project\'s rows still does', () => {
  const w = boot({ tab: 'control' });
  deliver(w, two());
  pickProject(w, '');
  assert.deepEqual(Array.from(panel(w, 'machine').querySelectorAll('.project'), (p) => p.dataset.project), REPOS);
  assert.equal(choice(w, 'machine'), null, 'no choice in it');
});

// Bug (E1): each of these panels draws itself again from its own timer or reply (Stop now's arming running out, a
// history read, a save answered), and that draw put the project last shown over the choice.
test('Control: the arming of Stop now running out, after Show went to All projects, leaves the choice alone', () => {
  const w = boot({ tab: 'control' });
  deliver(w, two());
  pickProject(w, 'sample');
  act(panel(w, 'board-loop'), 'stop').click();
  pickProject(w, '');
  const arming = w.timeouts.filter((t) => t.ms === 5000);
  assert.ok(arming.length, 'Stop now armed a timer');
  arming.forEach((t) => t.fn());
  onlyChoice(w, 'control');
});

test('Benchmarks: a history that arrives after Show went to All projects leaves the choice alone', async () => {
  const w = boot({ tab: 'bench' });
  const real = w.fetch;
  let open; const gate = new Promise((r) => { open = r; });
  let asked = 0;
  w.fetch = (url, o) => (/^bench\?/.test(url) ? (asked += 1, gate.then(() => real(url, o))) : real(url, o));
  deliver(w, two());
  pickProject(w, 'sample');
  assert.equal(asked, 1, 'the history of sample is being read');
  pickProject(w, '');
  open();
  await settle();
  onlyChoice(w, 'bench');
});

// The answer to the next control action waits until the returned function is called: it comes after Show went to every project.
const slowReply = (w) => { let open; const gate = new Promise((r) => { open = r; }); w.reply = { ok: true, status: 200, text: () => gate.then(() => 'sent to main') }; return open; };

test('Rules: a change answered after Show went to All projects leaves the choice alone', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, two());
  pickProject(w, 'sample');
  const open = slowReply(w);
  act(ruled(w).querySelector('[data-rule="suite"]'), 'suite-devbox').click();
  assert.equal(w.posts.length, 1, 'the change is out');
  pickProject(w, '');
  open();
  await settle();
  onlyChoice(w, 'rules');
});

test('Tests: a setting saved and answered after Show went to All projects leaves the choice alone', async () => {
  const w = boot({ tab: 'tests' });
  const d = two();
  d.panels.tests.data.tests.settings.slowIssues = false;
  deliver(w, d);
  pickProject(w, 'sample');
  const sec = TA.sp(w).querySelector('.tests-limits');
  const field = act(sec, 'slow-issues-field');
  field.value = 'true'; field.dispatchEvent(new w.Event('change'));
  const open = slowReply(w);
  act(sec, 'slow-issues-save').click();
  assert.equal(w.posts.length, 1, 'the save is out');
  pickProject(w, '');
  open();
  await settle();
  onlyChoice(w, 'tests');
});

// Bug (E2): the choice sat in the first panel of the tab even when the saved layout hid it, so no choice showed.
test('A panel hidden in the layout does not hold the choice: the next panel shown does, and a hiding made later moves it', () => {
  const w = boot({ tab: 'control', store: { [STORE]: JSON.stringify({ tabs: { control: { hidden: ['board-loop'] } } }) } });
  deliver(w, two());
  assert.equal(panel(w, 'board-loop').hidden, true, 'the saved layout hides Loop');
  assert.ok(choice(w, 'board-push'), 'the choice is in Push landed, the first panel shown');
  assert.equal(choice(w, 'board-loop'), null, 'and not in the hidden Loop');
  const box = w.document.getElementById('show-board-loop');
  box.checked = true; box.dispatchEvent(new w.Event('change'));
  assert.ok(choice(w, 'board-loop'), 'Loop shown again holds it');
  assert.equal(choice(w, 'board-push'), null, 'and Push landed no longer does');
  box.checked = false; box.dispatchEvent(new w.Event('change'));
  assert.ok(choice(w, 'board-push'), 'Loop hidden again: the choice moves back');
});

// Bug (E5): the live feed sends a changed part at a time, Benchmarks' own before the machine part that lists the projects.
// Benchmarks drew from the old list (one project: its data), and the machine part that added the second project drew only
// the panels of that part, so with Show at every project the tab kept the one project's data and no choice.
test('Live feed: a second project that joins after Benchmarks was drawn gives it the project choice, and one that leaves gives its data back', () => {
  const w = boot({ tab: 'bench', feed: true });
  const es = w.sources[0];
  es.readyState = 0; es.emit('error'); // the feed opens after a first failed try: the page is drawn from data.js meanwhile
  deliver(w, full());
  es.readyState = 1; es.emit('open');
  assert.equal(choice(w, 'bench'), null, 'one project on the host: Benchmarks shows its data');
  const joined = two().panels;
  es.emit('panel', { id: 'bench', part: joined.bench, updatedAt: iso(T0) });
  assert.equal(choice(w, 'bench'), null, 'the list still has one project when Benchmarks\' own part comes first');
  es.emit('panel', { id: 'machine', part: joined.machine, updatedAt: iso(T0) });
  assert.ok(choice(w, 'bench'), 'the machine part names two projects: Benchmarks shows the choice');
  assert.equal(panel(w, 'bench').dataset.state, 'empty');
  es.emit('panel', { id: 'machine', part: full().panels.machine, updatedAt: iso(T0 + 1000) });
  assert.equal(choice(w, 'bench'), null, 'one project again: the choice is gone');
  assert.equal(panel(w, 'bench').dataset.state, 'ready', 'and Benchmarks shows its data');
});

// Bug (E6): each new snapshot has a new read time, so a panel's part differs, and the choice was built again for it: the
// button that had the keyboard focus was replaced, and the focus went to the page.
test('The project choice a snapshot leaves as it is: the button with the focus keeps it', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, two());
  const button = choice(w, 'rules');
  button.focus();
  assert.equal(w.document.activeElement, button, 'the button has the focus');
  const d = two();
  d.panels.rules.data.readAt = '2026-11-09T17:05:00Z';
  d.updatedAt = iso(T0 + 15000);
  next(w, d);
  assert.equal(choice(w, 'rules'), button, 'the same button is in the panel');
  assert.equal(w.document.activeElement, button, 'and it still has the focus');
  // A third project is another choice: drawn again, whole.
  const more = two();
  more.panels.machine.data.repos = [...REPOS, 'gadgetworks'];
  next(w, more);
  assert.deepEqual(Array.from(panel(w, 'rules').querySelectorAll('[data-act="pick-project"]'), (b) => b.dataset.project), [...REPOS, 'gadgetworks']);
});
