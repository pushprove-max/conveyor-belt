// SPDX-License-Identifier: Apache-2.0
// The Rules tab's moved rows (issue 177): a row Queue, Hold or their Undo moved stays shown as moved until a snapshot
// made after the change shows it. Bug: the row went at once, a snapshot made before the change drew it again as held,
// and the next one took it away. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { T0, boot, deliver, next, settle, full, act, record, rulesP, groupEl, issuesP, heldP, clone, tick, cases } from './dashboard-view.helpers.mjs';

// A page of the repository (a name with no folder is a page of docs/), its bold marks taken out and its lines joined. Defined in
// this file, not in the helpers: the bug check puts only the card's test files on main's code, where a new helper is missing.
const guide = (name) => readFileSync(new URL(`../../../${name.includes('/') ? name : `docs/${name}`}`, import.meta.url), 'utf8').replace(/\*\*/g, '').replace(/\s+/g, ' ');
const test = cases(import.meta.url);

// Bug (issue 1430): a split umbrella held by the owner had Queue on its Held row and was in Queue all, which send
// `control release`: the release clears the hold and builds nothing (the Board's Held column offers no Queue for it).
test('Rules: a split umbrella held by you has no Queue, and Queue all sends no release for it', async () => {
  const w = boot({ tab: 'rules' });
  const d = snap(T0 - 60000);
  d.panels.rules.data.open.held.find((x) => x.issue === 76).umbrella = [77, 78];
  deliver(w, d);
  act(groupEl(w, 'infra'), 'group').click();
  assert.ok(row(w), 'the umbrella is listed as held');
  assert.equal(act(row(w), 'queue'), null, 'no Queue on its row');
  act(groupEl(w, 'infra'), 'queue-all').click();
  const yes = act(groupEl(w, 'infra'), 'queue-all-yes');
  if (yes) yes.click();
  await settle();
  assert.ok(!w.posts.some((p) => p.body.action === 'release' && p.body.args.includes('76')), `no release of #76: ${JSON.stringify(w.posts.map((p) => p.body))}`);
});

// Bug: the umbrella of a split into cards with no GitHub issue has `umbrella: []` and its slices in sliceCards; the
// Rules tab checked only `umbrella`, so Queue and Queue all sent a release that cleared the split's hold.
test('Rules: a split umbrella whose slices are cards with no issue has no Queue, and Queue all sends no release for it', async () => {
  const w = boot({ tab: 'rules' });
  const d = snap(T0 - 60000);
  Object.assign(d.panels.rules.data.open.held.find((x) => x.issue === 76), { umbrella: [], sliceCards: [{ card: 'c1', state: 'waiting' }] });
  deliver(w, d);
  act(groupEl(w, 'infra'), 'group').click();
  assert.ok(row(w), 'the umbrella is listed as held');
  assert.equal(act(row(w), 'queue'), null, 'no Queue on its row');
  act(groupEl(w, 'infra'), 'queue-all').click();
  const yes = act(groupEl(w, 'infra'), 'queue-all-yes');
  if (yes) yes.click();
  await settle();
  assert.ok(!w.posts.some((p) => p.body.action === 'release' && p.body.args.includes('76')), `no release of #76: ${JSON.stringify(w.posts.map((p) => p.body))}`);
});

// Bug: Open issues counted a split umbrella held by you in Queue, as `mine` comes from the record's hold, so picking it
// and clicking Queue sent a release that cleared the split's hold and built nothing. Each case picks the umbrella (76)
// and a plain held issue (79), clicks the enabled Queue 1, and checks that only 79 is released.
async function openQueue(edit) {
  const w = boot({ tab: 'rules' });
  const d = snap(T0 - 60000, [76, 79]), r = d.panels.rules.data;
  r.open.issues.push({ repo: 'sample', issue: 79, title: 'A plain held one', priority: 'P2', labels: ['P2'], created: '2026-11-02T00:00:00Z' });
  edit(r);
  deliver(w, d);
  for (const n of [76, 79]) {
    const box = issuesP(w).querySelector(`.rules-issue[data-issue="${n}"] [data-act="pick"]`);
    box.checked = true; box.dispatchEvent(new w.Event('change'));
  }
  const q = act(issuesP(w), 'bulk-release');
  assert.equal(q.textContent, 'Queue 1', 'only the plain held issue is counted in Queue');
  q.click();
  await settle();
  const rel = w.posts.filter((p) => p.body.action === 'release').map((p) => p.body.args);
  assert.deepEqual(rel, [['79']], `only #79 is released: ${JSON.stringify(w.posts.map((p) => p.body))}`);
}
test('Rules: Queue in Open issues sends no release for a picked split umbrella with numbered slices', () =>
  openQueue((r) => { r.open.held.find((x) => x.issue === 76).umbrella = [77, 78]; }));
test('Rules: Queue in Open issues sends no release for a picked split umbrella whose slices are cards with no issue', () =>
  openQueue((r) => { Object.assign(r.open.held.find((x) => x.issue === 76), { umbrella: [], sliceCards: [{ card: 'c1', state: 'waiting' }] }); }));
// Bug: the split holds its umbrella before its card closes (lib/slices.sh); meanwhile the issue is on the belt, so the
// snapshot leaves it out of open.held and only splitting (its card filed the slices) says it is a split.
test('Rules: Queue in Open issues sends no release for a split umbrella whose card has not closed yet', () =>
  openQueue((r) => { r.open.held = r.open.held.filter((x) => x.issue !== 76); r.onBelt = [76]; r.splitting = [76]; }));

// A snapshot the collector began at `begun`, with the record holding `held` (76 by default, as full()).
function snap(begun, held = [76]) {
  const d = full(begun + 20000), r = d.panels.rules.data;
  r.control.held = held;
  r.held = r.held.filter((x) => held.includes(x.issue));
  r.open.held = r.open.held.filter((x) => held.includes(x.issue) || !x.reasons.some((y) => y.kind === 'you'));
  r.open.issues = [{ repo: 'sample', issue: 76, title: 'Split the PROD stack', priority: 'P1', labels: ['P1', 'area:infra'], created: '2026-11-01T00:00:00Z' }];
  return d;
}
const row = (w) => { const g = groupEl(w, 'infra'); return g ? g.querySelector('[data-issue="76"]') : null; };
async function queued(w, reply) {
  deliver(w, snap(T0 - 60000));
  act(groupEl(w, 'infra'), 'group').click();
  w.reply = reply;
  act(row(w), 'queue').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.action), ['release']);
}

test('Rules: a queued row stays shown as queued through a snapshot made before the change, and goes with one made after that shows it', async () => {
  const w = boot({ tab: 'rules' });
  await queued(w, record({ held: [] }, T0));
  assert.ok(row(w).classList.contains('is-pending'), 'shown as moved, not removed');
  assert.match(row(w).textContent, /Queued: this shows in about a minute/);
  assert.ok(guide('board.md').includes('the row says "Queued: this shows in about a minute."'), 'docs/board.md names the note the row shows after Queue');
  assert.equal(act(row(w), 'queue'), null, 'no second Queue while it waits');
  w.clock = T0 + 30000;
  next(w, snap(T0 - 1000));
  assert.ok(row(w) && row(w).classList.contains('is-pending'), 'a snapshot made before the change does not bring the row back as held');
  next(w, snap(T0 + 5000, []));
  assert.equal(row(w), null, 'a snapshot made after the change that shows it removes the row');
});

// Issue 288: the live feed's snapshot of the record (readAt) can have begun before the release while data.js around it
// is dated after the answer. Bug: that first update came back "Not queued: ... still shows it held" and the user had to
// press Queue again.
test('Rules: a Queue answered, then an update dated after it whose record snapshot began before it, keeps the row queued; the next shows it', async () => {
  const w = boot({ tab: 'rules' });
  await queued(w, record({ held: [] }, T0));
  w.clock = T0 + 30000;
  const stale = snap(T0 + 5000);
  stale.panels.rules.data.readAt = new Date(T0 - 3000).toISOString();
  next(w, stale);
  assert.ok(row(w) && row(w).classList.contains('is-pending'), 'still shown as queued, not as refused');
  assert.equal(row(w).querySelector('.rules-refused'), null);
  const fresh = snap(T0 + 10000, []);
  fresh.panels.rules.data.readAt = new Date(T0 + 2000).toISOString();
  next(w, fresh);
  assert.equal(row(w), null, 'the record snapshot begun after the answer shows it queued');
});

test('Rules: when the first snapshot made after a Queue still holds the issue the host released, the error says a later hold holds it', async () => {
  const w = boot({ tab: 'rules' });
  await queued(w, record({ held: [] }, T0));
  w.clock = T0 + 30000;
  next(w, snap(T0 + 5000));
  assert.ok(!row(w).classList.contains('is-pending'));
  assert.ok(act(row(w), 'queue'), 'it can be queued again');
  assert.match(row(w).querySelector('.rules-refused').textContent, /^Not queued: the host released it, but a later hold holds it again \(/);
});

test('Rules: a refused Queue brings the row back with the refusal beside it', async () => {
  const w = boot({ tab: 'rules' });
  await queued(w, { ok: false, status: 409, text: () => Promise.resolve('issue 76 is not held'), headers: { get: () => null } });
  assert.ok(!row(w).classList.contains('is-pending'));
  assert.ok(act(row(w), 'queue'));
  assert.match(row(w).querySelector('.rules-refused').textContent, /^Not queued: .*issue 76 is not held/);
});

test('Rules: the Undo of a Queue holds the row again the same way: older snapshots keep it moved, a newer one that holds it ends the wait', async () => {
  const w = boot({ tab: 'rules' });
  await queued(w, record({ held: [] }, T0));
  w.clock = T0 + 30000;
  next(w, snap(T0 + 5000, []));
  const issue = () => issuesP(w).querySelector('[data-issue="76"]');
  w.reply = record({ held: [76] }, T0 + 30000);
  act(rulesP(w), 'undo').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => [p.body.action, p.body.args]), [['hold', ['76']]]);
  assert.ok(issue().classList.contains('is-pending'));
  assert.match(issue().textContent, /Held by you.*Held: this shows in about a minute/);
  w.clock = T0 + 60000;
  next(w, snap(T0 + 10000, []));
  assert.ok(issue().classList.contains('is-pending'), 'a snapshot made before the Undo does not show it queued again');
  assert.match(issue().textContent, /Held by you/);
  next(w, snap(T0 + 40000));
  assert.ok(!issue().classList.contains('is-pending'), 'one made after it that holds it ends the wait');
  assert.equal(issue().querySelector('.rules-refused'), null);
});

// Issue 294: every watch refresh gives the Rules part a new readAt (when its record was read). Bug: the part then
// differed from the one drawn, the tab was drawn again and the open Group by select was replaced, closing it.
test('Rules: a refresh that changes only readAt keeps the Group by select in place; one that changes what it shows draws it again', () => {
  const w = boot({ tab: 'rules' });
  const d = snap(T0 - 60000);
  d.panels.rules.data.readAt = new Date(T0 - 70000).toISOString();
  deliver(w, d);
  // A search typed first puts iq in the address without drawing the tab: the panels still show what they did.
  const q = act(issuesP(w), 'iq');
  q.value = '76';
  q.dispatchEvent(new w.Event('input'));
  const by = act(heldP(w), 'held-by');
  by.focus();
  const age = () => issuesP(w).querySelector('[data-issue="76"] .rules-age').textContent;
  assert.equal(age(), '8 d 17 h old');
  const again = clone(d);
  again.updatedAt = new Date(T0 - 20000).toISOString();
  again.panels.rules.data.readAt = new Date(T0 - 30000).toISOString();
  next(w, again);
  assert.equal(act(heldP(w), 'held-by'), by, 'the select the user has open is the same node');
  assert.equal(w.document.activeElement, by);
  // Bug (review of issue 294): the open issues' ages were set only when the rows were drawn, so with no row drawn
  // again they stopped. An hour on, the age has moved.
  tick(w, 3600000);
  assert.equal(age(), '8 d 18 h old');
  const moved = clone(again);
  moved.panels.rules.data.cap = 7;
  next(w, moved);
  assert.notEqual(act(heldP(w), 'held-by'), by, 'a real change still draws the tab again');
});

// Bug (review of issue 294): a refresh that changed only readAt drew nothing and left the part drawn before it as the
// one shown, so Back with the latest part was taken for that refresh and drew nothing: the address said iq=76 and the
// list still used the later search.
test('Rules: Back after a refresh that changes only readAt draws the open issues the address then searches for', () => {
  const w = boot({ tab: 'rules' });
  const d = snap(T0 - 60000);
  d.panels.rules.data.readAt = new Date(T0 - 70000).toISOString();
  deliver(w, d);
  const q = act(issuesP(w), 'iq');
  q.value = '77';
  q.dispatchEvent(new w.Event('input'));
  assert.equal(issuesP(w).querySelector('[data-issue="76"]'), null, 'the search for 77 hides #76');
  const again = clone(d);
  again.updatedAt = new Date(T0 - 20000).toISOString();
  again.panels.rules.data.readAt = new Date(T0 - 30000).toISOString();
  next(w, again);
  w.history.replaceState(null, '', 'https://dash.test/index.html?tab=rules&iq=76');
  w.dispatchEvent(new w.PopStateEvent('popstate'));
  assert.equal(act(issuesP(w), 'iq').value, '76');
  assert.ok(issuesP(w).querySelector('[data-issue="76"]'), 'the list uses the search the address holds');
});

// Bug (second review of issue 294): a refresh that changed only readAt came while Overview was shown, and Back to
// Rules then brought that part with another search in the address: it was taken for the refresh and drew nothing, so
// the address said iq=76 and the list still used 77.
test('Rules: Back from Overview after a refresh there that changes only readAt draws the open issues the address searches for', () => {
  const w = boot({ tab: 'rules' });
  const d = snap(T0 - 60000);
  d.panels.rules.data.readAt = new Date(T0 - 70000).toISOString();
  deliver(w, d);
  const q = act(issuesP(w), 'iq');
  q.value = '77';
  q.dispatchEvent(new w.Event('input'));
  assert.equal(issuesP(w).querySelector('[data-issue="76"]'), null, 'the search for 77 hides #76');
  w.history.pushState(null, '', 'https://dash.test/index.html?tab=overview&iq=77');
  w.dispatchEvent(new w.PopStateEvent('popstate'));
  const again = clone(d);
  again.updatedAt = new Date(T0 - 20000).toISOString();
  again.panels.rules.data.readAt = new Date(T0 - 30000).toISOString();
  next(w, again);
  w.history.replaceState(null, '', 'https://dash.test/index.html?tab=rules&iq=76');
  w.dispatchEvent(new w.PopStateEvent('popstate'));
  assert.equal(act(issuesP(w), 'iq').value, '76');
  assert.ok(issuesP(w).querySelector('[data-issue="76"]'), 'the list uses the search the address holds');
});
