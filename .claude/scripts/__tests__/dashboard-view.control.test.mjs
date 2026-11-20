// SPDX-License-Identifier: Apache-2.0
// Issue 409, the Control tab made clear: the pause controls named by scope and cost, and a paused loop saying who
// paused it and how to resume (UX10); a dependency's title beside its number and a cycle refused in plain words
// (UX19); one filter row, and a column the filter empties saying so with Clear (UX20); a project's Held list closed
// under "Held (N) · Show" (UX32); Landed today cut to its newest five (UX33).
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, deliver, next, settle, panel, P, CONTROL, full, board, loopP, bcard, column, inCol, act, note, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const head = (w) => w.document.getElementById('machine-head');
const project = (w) => panel(w, 'machine').querySelector('.project[data-project="sample"]');
const said = (ok, text) => ({ ok, status: ok ? 200 : 409, text: () => Promise.resolve(text), headers: { get: () => null } });

// Bug: five stop controls on one screen ("Pause the machine", "Pause <project>", "Pause after current", "Stop now")
// did not say what each stops, Stop now hid its cost (the cards it sends back) in hover text, and a paused loop did
// not say who paused it or how to start it again.
test('UX10: the machine, a project and the Board name what each pause stops; Stop now carries how many cards it requeues', () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  assert.equal(act(head(w), 'machine-pause').textContent, 'Pause all projects');
  assert.equal(act(project(w), 'pause').textContent, 'Pause sample');
  assert.equal(act(loopP(w), 'pause').textContent, 'Pause sample after current');
  // Building #5 and Review #63 are in progress.
  assert.equal(act(loopP(w), 'stop').textContent, 'Stop now and requeue 2 cards');
  assert.equal(loopP(w).querySelector('.board-paused'), null, 'a running loop says nothing of a pause');
  assert.equal(project(w).querySelector('.project-paused'), null);
  assert.equal(head(w).querySelector('.machine-paused'), null);
  // One more building is in progress.
  const d = full(T0 + 60000), b = d.panels.board.data;
  b.building.push({ ...b.building[0], card: 'c9-10', issue: 10, step: 'tests' });
  next(w, d);
  assert.equal(act(loopP(w), 'stop').textContent, 'Stop now and requeue 3 cards');
  // Bug: the count took in cards the engine's stop leaves running (halt() in conveyor/lib/run.sh): landed and still
  // pushing, filing its follow-ups, landing, or filed them, so the label promised to requeue cards it never would.
  // The server marks each such card stays (dashboard.test.sh proves it from the snapshot's fields).
  b.building.push({ ...b.building[0], card: 'c9-9', issue: 9, step: 'push', stays: true },
    { ...b.building[0], card: 'c9-12', issue: 12, step: 'landing', stays: true });
  b.review.push({ ...b.review[0], card: 'c9-13', issue: 13, stays: true });
  next(w, d);
  assert.equal(act(loopP(w), 'stop').textContent, 'Stop now and requeue 3 cards', 'cards Stop now leaves running are not requeued');
  b.building = []; b.review = [];
  next(w, d);
  assert.equal(act(loopP(w), 'stop').textContent, 'Stop now and requeue 0 cards');
});

test('UX10: paused, paused by the guard or stopped, each says in one line who did it and how to resume', () => {
  const at = (state, mode, guard = 90) => {
    const d = full(), b = d.panels.board.data, p = d.panels.machine.data.projects[0];
    Object.assign(b, { state, control: { ...CONTROL, mode, guard } });
    Object.assign(p, { state, mode, guard });
    return d;
  };
  const w = boot({ tab: 'control' });
  deliver(w, at('paused', 'pause'));
  const line = 'Paused by you (Pause sample). Resume sample to pick again.';
  assert.equal(loopP(w).querySelector('.board-paused').textContent, line);
  assert.equal(project(w).querySelector('.project-paused').textContent, line);
  assert.equal(act(loopP(w), 'resume').textContent, 'Resume sample', 'the button the line names');
  assert.equal(act(project(w), 'resume').textContent, 'Resume sample');
  const g = boot({ tab: 'control' });
  deliver(g, at('paused by guard', 'run'));
  const guard = 'Paused by the weekly-limit guard at 90%. Raise or turn off "Weekly pause" in Rules to pick again.';
  assert.equal(loopP(g).querySelector('.board-paused').textContent, guard);
  assert.equal(project(g).querySelector('.project-paused').textContent, guard);
  const s = boot({ tab: 'control' });
  deliver(s, at('stopped', 'stop'));
  assert.match(loopP(s).querySelector('.board-paused').textContent, /^Stopped by Stop now: the cards in progress went back to the queue\. Resume sample to pick again\.$/);
  // The machine paused for every project.
  const m = boot({ tab: 'control' }), d = full();
  d.panels.machine.data.state = 'paused';
  deliver(m, d);
  assert.equal(act(head(m), 'machine-resume').textContent, 'Resume all projects');
  assert.equal(head(m).querySelector('.machine-paused').textContent, 'Every project paused by you (Pause all projects). Resume all projects to pick again.');
});

// Bug (issue 135): a loop that paused itself on an expired sign-in was shown as "Paused by you", with no word of the
// sign-in or what to run.
test('a loop paused by a sign-in failure shows that reason, not a pause by you', () => {
  const why = 'build: the Claude sign-in expired; run claude /login (or set up the proxy route), then conveyor.sh control resume';
  const d = full(), b = d.panels.board.data, p = d.panels.machine.data.projects[0];
  Object.assign(b, { state: 'paused', reason: why, control: { ...CONTROL, mode: 'pause' } });
  Object.assign(p, { state: 'paused', reason: why, mode: 'pause' });
  const w = boot({ tab: 'control' });
  deliver(w, d);
  const line = 'Paused by Conveyor for the reason shown. Fix it, then Resume sample to pick again.';
  assert.equal(loopP(w).querySelector('.board-from').textContent, why);
  assert.equal(loopP(w).querySelector('.board-paused').textContent, line);
  assert.equal(project(w).querySelector('.reason').textContent, why);
  assert.equal(project(w).querySelector('.project-paused').textContent, line);
});

// Bug: "Depends on…" took bare numbers, so the owner could not see which issue a number was; the host's refusal of a
// cycle came back as its own text.
test('UX19: each number typed into "Depends on…", and each dependency set, shows its title; a cycle is refused as what already waits on what', async () => {
  const d = full();
  d.panels.board.data.open = { count: 3, split: { queued: 3, you: 0, labelOrRule: 0, belt: 0 }, held: [],
    issues: [{ issue: 20, title: 'Next up', dependsOn: [21] }, { issue: 21, title: 'Later', dependsOn: [] }, { issue: 22, title: 'Last', dependsOn: [] }] };
  const w = boot({ tab: 'control' });
  deliver(w, d);
  act(bcard(w, 20), 'depends').click();
  await settle();
  assert.deepEqual(Array.from(bcard(w, 20).querySelectorAll('.board-dep'), (x) => x.textContent), ['× #21Later'], 'the dependency set, with its title');
  const f = act(bcard(w, 20), 'dep-input');
  f.value = '22, 999, 20'; f.dispatchEvent(new w.Event('input'));
  assert.deepEqual(Array.from(bcard(w, 20).querySelectorAll('.dep-picked li'), (x) => x.textContent),
    ['#22 Last', '#999 is not an open issue of this project', '#20 is this issue itself'], 'each number with its title as it is typed');
  f.value = '22'; f.dispatchEvent(new w.Event('input'));
  w.reply = said(false, 'conveyor: #20 depending on #22 would make a dependency cycle (#20, #22): none of them would ever be picked; nothing changed');
  act(bcard(w, 20), 'dep-add').click();
  await settle(); await settle();
  assert.equal(note(w), 'Not done: #20 cannot wait on #22: #22 already waits on #20.');
  // A longer cycle names the issues between.
  w.reply = said(false, 'conveyor: #20 depending on #22 would make a dependency cycle (#20, #21, #22): none of them would ever be picked; nothing changed');
  act(bcard(w, 20), 'dep-add').click();
  await settle(); await settle();
  assert.equal(note(w), 'Not done: #20 cannot wait on #22: #22 already waits on #20 through #21.');
  // Any other refusal is the host's own words.
  w.reply = said(false, 'conveyor: #20: its card is already running; the dependency would not stop it; nothing changed');
  act(bcard(w, 20), 'dep-add').click();
  await settle(); await settle();
  assert.equal(note(w), 'Not done: conveyor: #20: its card is already running; the dependency would not stop it; nothing changed');
});

test('UX19: the Rules waiting list shows each dependency\'s title and each number typed with its title, and says a cycle plainly', async () => {
  const d = full(), r = d.panels.rules.data;
  r.waits = [{ repo: 'sample', card: null, issue: 24, title: 'Second half', url: `${P}/24`, priority: 'P2', waitsFor: [20] }];
  r.open = { ...(r.open || {}), issues: [{ issue: 24, title: 'Second half', dependsOn: [20] }, { issue: 20, title: 'Next up', dependsOn: [] }, { issue: 21, title: 'Later', dependsOn: [] }] };
  const w = boot({ tab: 'rules' });
  deliver(w, d);
  const produce = panel(w, 'rules-produce');
  act(produce, 'waits-open').click();
  await settle();
  const row = () => produce.querySelector('.rules-wait[data-issue="24"]');
  assert.deepEqual(Array.from(row().querySelectorAll('.board-dep'), (x) => x.textContent), ['× #20Next up']);
  act(row(), 'depends').click();
  await settle();
  const f = act(row(), 'dep-input');
  f.value = '21'; f.dispatchEvent(new w.Event('input'));
  assert.deepEqual(Array.from(row().querySelectorAll('.dep-picked li'), (x) => x.textContent), ['#21 Later']);
  w.reply = said(false, 'conveyor: #24 depending on #21 would make a dependency cycle (#21, #24): none of them would ever be picked; nothing changed');
  act(row(), 'dep-add').click();
  await settle(); await settle();
  assert.equal(produce.querySelector('.rules-note').textContent, 'Not done: #24 cannot wait on #21: #21 already waits on #24.');
});

// Bug: a filter left on emptied a column, which then read "The queue is empty." as if the queue were empty.
test('UX20: a column the filter empties says "Nothing queued matches the filter · Clear", and Clear shows every card again', () => {
  const w = boot({ query: '?tab=control&bprio=P0' });
  deliver(w, full());
  assert.equal(column(w, 'queue').querySelector('.board-unmatched').textContent, 'Nothing queued matches the filter · Clear');
  assert.equal(column(w, 'queue').querySelector('.board-head .panel-count').textContent, '0 of 3', 'the count says the filter hides them');
  assert.doesNotMatch(column(w, 'queue').textContent, /The queue is empty/);
  act(column(w, 'queue'), 'filter-clear').click();
  assert.deepEqual(inCol(w, 'queue'), [20, 21, 22]);
  assert.equal(new URL(w.location.href).searchParams.get('bprio'), null, 'the address drops the filter');
  assert.equal(board(w).querySelector('[data-act="bprio"]').value, '');
  // A column that is empty with no filter on, or empty before the filter, still says it is empty.
  const e = boot({ query: '?tab=control&bprio=P0' }), d = full();
  d.panels.board.data.review = [];
  deliver(e, d);
  assert.equal(column(e, 'review').textContent.includes('Nothing is in review.'), true);
  // One row: the text filter is in it, and no column has filters of its own.
  assert.ok(board(e).querySelector('.board-viewbar [data-filter="text"]'));
  assert.equal(board(e).querySelectorAll('.board-col select, .board-col input').length, 0);
});

// Bug: a project's 209 held issues were printed as a wall of numbers, the biggest thing on the first Control screen.
test('UX32: a project\'s Held list is "Held (N) · Show", closed; opened, each issue with its title, and it stays open through a refresh', () => {
  const d = full(), held = Array.from({ length: 209 }, (_, i) => ({ repo: 'sample', card: null, issue: 1000 + i, title: `Held thing ${i}`, url: `${P}/${1000 + i}` }));
  d.panels.machine.data.projects[0].held = held;
  const w = boot({ tab: 'control' });
  deliver(w, d);
  const det = () => project(w).querySelector('details.project-held');
  assert.equal(det().open, false, 'closed by default');
  assert.equal(det().querySelector('summary').textContent, 'Held (209)· Show');
  det().open = true;
  det().dispatchEvent(new w.Event('toggle'));
  assert.equal(det().querySelector('summary').textContent, 'Held (209)· Hide');
  assert.equal(det().querySelectorAll('li').length, 209);
  assert.equal(det().querySelector('li').textContent, '#1000Held thing 0', 'each with its title');
  const again = full(T0 + 60000);
  again.panels.machine.data.projects[0].held = held.slice(1);
  next(w, again);
  assert.equal(det().open, true, 'the owner\'s choice survives the redraw');
  // The pinned order names each issue with its title, where the project's lists give it.
  assert.equal(project(w).querySelector('[data-list="Pinned order"]').textContent, 'Pinned order (1)#21', 'no title listed: the number alone');
  const t = full();
  t.panels.machine.data.projects[0].order = [20];
  const p = boot({ tab: 'control' });
  deliver(p, t);
  assert.equal(project(p).querySelector('[data-list="Pinned order"] .project-item').textContent, '#20Next up');
  // Bug: a pinned issue waiting on an open dependency is in no list shown, so it was a bare number.
  t.panels.machine.data.projects[0].order = [32];
  t.panels.machine.data.projects[0].waiting = [{ repo: 'sample', card: null, issue: 32, title: 'Second half', url: 'https://example.com/32' }];
  const q = boot({ tab: 'control' });
  deliver(q, t);
  assert.equal(project(q).querySelector('[data-list="Pinned order"] .project-item').textContent, '#32Second half', 'a waiting pinned issue has its title');
});

// Bug: Landed today listed every landed card in full, so the column acted on least made the page eight screens long.
test('UX33: Landed today shows the newest five, then "Show all (48)"', () => {
  const d = full(), now = T0;
  d.panels.board.data.landed = Array.from({ length: 48 }, (_, i) => ({ repo: 'sample', card: `c${i}-${300 + i}`, issue: 300 + i, title: `Landed ${i}`, url: `${P}/${300 + i}`,
    step: 'landed', time: iso(now - (i + 1) * 60000), usd: 1, reviews: 1 }));
  const w = boot({ tab: 'control' });
  deliver(w, d);
  assert.deepEqual(inCol(w, 'landed'), [300, 301, 302, 303, 304], 'the newest five, as the snapshot lists them newest first');
  assert.ok(Array.from(column(w, 'landed').querySelectorAll('.show-more button'), (b) => b.textContent).includes('Show all (48)'));
  assert.equal(column(w, 'landed').querySelector('.board-head .panel-count').textContent, '48');
  act(column(w, 'landed'), 'list-all').click();
  assert.equal(inCol(w, 'landed').length, 48);
});

// Bug (#524): the snapshot keeps only the day's newest landed cards, and the Board counted and priced those alone: 110
// landed read "20 landed", and the 90 older ones were reached from nowhere on the Board.
test('Landed today: the day\'s whole count and cost, and a link to the older cards in Landed today', () => {
  const d = full(), now = T0;
  d.panels.board.data.landed = Array.from({ length: 20 }, (_, i) => ({ repo: 'sample', card: `c${i}-${300 + i}`, issue: 300 + i, title: `Landed ${i}`, url: `${P}/${300 + i}`,
    step: 'landed', time: iso(now - (i + 1) * 60000), usd: 1, reviews: 1 }));
  d.panels.board.data.today = { landed: 110, usd: 220 };
  const w = boot({ tab: 'control' });
  deliver(w, d);
  assert.match(w.document.querySelector('[data-figure="today"]').textContent, /^Today110 landed\$220\.00$/);
  assert.equal(column(w, 'landed').querySelector('.board-head .panel-count').textContent, '20 of 110');
  const a = act(column(w, 'landed'), 'landed-open');
  assert.equal(a.textContent, 'The 90 older cards are in Landed today');
  assert.match(a.getAttribute('href'), /\?tab=overview#panel-landed$/);
});
