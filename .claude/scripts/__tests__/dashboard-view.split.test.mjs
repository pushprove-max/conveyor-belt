// SPDX-License-Identifier: Apache-2.0
// The rule Split large issues on the Board (#270): its row on the Rules tab (the control record's rules.split: off,
// shadow or on), what a card shows of the split, the umbrella in Held, and the Health measure of the checked cards.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled, panel, withOpen, dragTo, P, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// The Rules part with the rule as given; none: a record from an engine before the rule.
function rules(split) {
  const d = full(), r = d.panels.rules.data;
  const rs = { ...r.control.rules };
  delete rs.split;
  r.control = { ...r.control, rules: { ...rs, ...(split === 'none' ? {} : { split }) } };
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="split"]');
const pressed = (w) => ['split-off', 'split-shadow', 'split-on'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed'));
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the owner could not set the rule from the Board; the row did not show its three settings with the
// one in force, nor what Shadow means; a change sent nothing, or a word the engine does not take.
test('Rules: Split large issues shows Off, Shadow and On, says what Shadow does, and sends the setting chosen', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, rules('shadow'));
  assert.deepEqual(pressed(w), ['false', 'true', 'false'], 'shadow is the setting in force');
  assert.match(row(w).textContent, /shadow: the verdict is recorded, and the issue is built whole/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'split-shadow').click()), [], 'the setting in force sends nothing');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'split-on').click()), [{ action: 'rules', args: ['split=on'], repo: 'sample' }]);
  next(w, rules('on'));
  assert.deepEqual(pressed(w), ['false', 'false', 'true']);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'split-off').click()), [{ action: 'rules', args: ['split=off'], repo: 'sample' }]);
});

// Bug this guards: a record with no rules.split (an engine before the rule) was sent a rule it refuses.
test('Rules: Split large issues, unset, is not sent to an engine that does not know it', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, rules('none'));
  assert.ok(['split-off', 'split-shadow', 'split-on'].every((a) => act(rulesP(w), a).disabled), 'an older engine is sent none of them');
  assert.match(row(w).textContent, /needs a newer Conveyor/);
});

// Bug this guards: the setup (#250) asks every project rule, and it left Split large issues unasked. Its default,
// On, is shown selected until the rule is set, whatever the record holds, and that choice sends it.
test('Setup: a project not yet onboarded is asked Split large issues, with On as its default', async () => {
  const w = boot();
  const d = rules('off');
  d.panels.rules.data.control.onboarded = null;
  deliver(w, d);
  const box = w.document.getElementById('onboard');
  assert.deepEqual(Array.from(box.querySelectorAll('.onboard-body .rules-row'), (r) => r.dataset.rule), ['build', 'never', 'split']);
  assert.equal(act(box, 'onboard-default-split').textContent, 'default: On');
  assert.equal(act(box, 'split-on').getAttribute('aria-pressed'), 'true');
  assert.deepEqual(await sent(w, () => act(box, 'split-on').click()), [{ action: 'rules', args: ['split=on'], repo: 'sample' }]);
  assert.equal(box.querySelector('[data-rule="split"]').dataset.set, 'true');
});

// Bugs this guards: the trial's verdict could not be seen on a card; a split issue's closed card read "already fixed".
test('Board: a card shows "Would have split into N" in shadow and its slices On', () => {
  const w = boot({ tab: 'control' });
  const d = withOpen({ held: [{ repo: 'sample', issue: 9, title: 'Big one', url: `${P}/9`, priority: 'P2', labels: [], reasons: [{ kind: 'you' }], umbrella: [101, 102] }] });
  const b = d.panels.board.data;
  b.control = { ...b.control, held: [9] };
  b.landed = [
    { repo: 'sample', card: 'c5-7', issue: 7, title: 'Landed one', url: `${P}/7`, step: 'landed', usd: 2.5, reviews: 2, split: { result: 'split', slices: 3, filed: null } },
    { repo: 'sample', card: 'c6-9', issue: 9, title: 'Big one', url: `${P}/9`, step: 'closed', usd: 0, reviews: 0, split: { result: 'split', slices: 2, filed: [101, 102] } },
    { repo: 'sample', card: 'c6-8', issue: 8, title: 'Kept', url: `${P}/8`, step: 'landed', usd: 0.5, reviews: 1, split: { result: 'kept', slices: 0, filed: null } },
  ];
  deliver(w, d);
  const inCol = (k, n) => panel(w, 'board').querySelector(`.board-col[data-col="${k}"] .bcard[data-issue="${n}"]`), landed = (n) => inCol('landed', n);
  assert.match(landed(7).textContent, /Would have split into 3/);
  assert.match(landed(9).textContent, /Split into #101, #102/);
  assert.match(landed(9).textContent, /split, not built/);
  assert.doesNotMatch(landed(9).textContent, /already fixed/);
  assert.doesNotMatch(landed(8).textContent, /split/i, 'a kept issue shows nothing');
});

// Bugs this guards (#1130): an umbrella of a split showed as a plain held issue with a Queue button that cleared the
// hold and built nothing, with no word on why; an issue waiting on it named only the umbrella; and a slice in Held only
// because it waits on another issue was labelled held.
test('Board: an umbrella of a split shows its slices with their state and no Queue; a plain held issue keeps its Queue', async () => {
  const w = boot({ tab: 'control' });
  // #9 split into #7 (landed today), #63 (in review), #21 (queued), #76 (held by you), #77 (in Held only as it waits on
  // #76) and #99 (closed on an earlier day).
  const d = withOpen({ held: [
    { repo: 'sample', issue: 76, title: 'Split the PROD stack', url: `${P}/76`, priority: 'P2', labels: [], reasons: [{ kind: 'you' }] },
    { repo: 'sample', issue: 9, title: 'Big one', url: `${P}/9`, priority: 'P2', labels: [], reasons: [{ kind: 'you' }], umbrella: [7, 63, 21, 76, 77, 99] },
    { repo: 'sample', issue: 77, title: 'After the stack', url: `${P}/77`, priority: 'P2', labels: [], reasons: [{ kind: 'waits', waitsFor: [76] }] },
    { repo: 'sample', issue: 30, title: 'After the big one', url: `${P}/30`, priority: 'P2', labels: [], reasons: [{ kind: 'waits', waitsFor: [9] }] },
  ] });
  const b = d.panels.board.data;
  b.open.issues = [9, 21, 30, 63, 76, 77].map((issue) => ({ issue, title: `Issue ${issue}`, labels: [] }));
  b.control = { ...b.control, held: [76, 9] };
  b.landed.push({ repo: 'sample', card: 'c6-9', issue: 9, title: 'Big one', url: `${P}/9`, step: 'closed', usd: 0, reviews: 0, split: { result: 'split', slices: 6, filed: [7, 63, 21, 76, 77, 99] } });
  deliver(w, d);
  const card = (n) => panel(w, 'board').querySelector(`.board-col[data-col="held"] .bcard[data-issue="${n}"]`);
  assert.match(card(9).querySelector('.board-umbrella').textContent, /^Split into #7, #63, #21, #76, #77, #99; closes when they land$/);
  assert.deepEqual(Array.from(card(9).querySelectorAll('.board-slice'), (x) => x.textContent),
    ['#7 landed', '#63 building', '#21 waiting', '#76 held', '#77 waiting', '#99 landed'],
    'each slice with its state; one in Held only for a wait is waiting, not held');
  assert.equal(act(card(9), 'release'), null, 'an umbrella has no Queue');
  assert.ok(act(card(76), 'release'), 'a held issue that is no umbrella (here one of its slices) keeps its Queue');
  // Dragged to Queue, the umbrella is not released: the Board says to queue its slices.
  dragTo(w, card(9), panel(w, 'board').querySelector('.board-col[data-col="queue"]'));
  await settle();
  assert.deepEqual(w.posts.splice(0), [], 'no release is sent for an umbrella');
  assert.match(panel(w, 'board').querySelector('.board-note').textContent, /#9 is not built itself: it closes when #7, #63, #21, #76, #77, #99 land\. Queue those instead\./);
  assert.match(card(30).querySelector('[data-reason="waits"]').textContent, /^Waiting on #9 \(its slices #7, #63, #21, #76, #77, #99\)$/);
});

// Bug this guards: the shadow trial had no figures: how many were kept or would split, and how their first reviews went.
test('Health: the split check row gives kept and would-split cards with their first-review GO rate and fix rounds', () => {
  const w = boot();
  const d = full();
  d.panels.health.data.records[0].split = { kept: { cards: 8, reviewed: 8, go: 7, fixes: 2 }, wouldSplit: { cards: 2, reviewed: 2, go: 1, fixes: 3 }, split: 1 };
  deliver(w, d);
  const dd = panel(w, 'health').querySelector('dt[data-check="Split check"]').nextElementSibling;
  assert.match(dd.textContent, /11 checked/);
  assert.match(dd.textContent, /kept 8 \(first-review GO 88%, 0\.25 fix rounds\); would split 2 \(first-review GO 50%, 1\.50 fix rounds\); split into slices 1/);
});
