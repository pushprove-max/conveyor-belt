// SPDX-License-Identifier: Apache-2.0
// The rule Split large issues on the Board (#270): its row on the Rules tab (the control record's rules.split: off,
// shadow or on), what a card shows of the split, the umbrella in Held, and the Health measure of the checked cards.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled, panel, withOpen, P, cases } from './dashboard-view.helpers.mjs';

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
// Shadow, is shown selected until the rule is set, whatever the record holds, and that choice sends it.
test('Setup: a project not yet onboarded is asked Split large issues, with Shadow as its default', async () => {
  const w = boot();
  const d = rules('off');
  d.panels.rules.data.control.onboarded = null;
  deliver(w, d);
  const box = w.document.getElementById('onboard');
  assert.deepEqual(Array.from(box.querySelectorAll('.onboard-body .rules-row'), (r) => r.dataset.rule), ['build', 'never', 'split']);
  assert.equal(act(box, 'onboard-default-split').textContent, 'default: Shadow');
  assert.equal(act(box, 'split-shadow').getAttribute('aria-pressed'), 'true');
  assert.deepEqual(await sent(w, () => act(box, 'split-shadow').click()), [{ action: 'rules', args: ['split=shadow'], repo: 'sample' }]);
  assert.equal(box.querySelector('[data-rule="split"]').dataset.set, 'true');
});

// Bugs this guards: the trial's verdict could not be seen on a card; a split issue's closed card read "already fixed";
// an umbrella sat in Held with nothing saying it waits on its slices.
test('Board: a card shows "Would have split into N" in shadow and its slices On; the umbrella in Held names them', () => {
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
  assert.match(inCol('held', 9).textContent, /Umbrella of #101, #102: not built itself, and closed when they land or are already done on main/);
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
