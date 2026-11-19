// SPDX-License-Identifier: Apache-2.0
// The rule Pick settings on the Board (#763): its row on the Rules tab (the control record's rules.pick: off, shadow
// or on) and the Cost panel's table of picked cards by group and builder (cost.cards.picks, one row a group and builder
// as the snapshot sums them). Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, settle, full, act, rulesP, ruled, panel, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// The Rules part with the rule as given; none: a record from an engine before the rule.
function rules(pick) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, rules: { ...r.control.rules, ...(pick === 'none' ? {} : { pick }) } };
  return d;
}
const pressed = (w) => ['pick-off', 'pick-shadow', 'pick-on'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed'));
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the owner could not set the rule from the Board; the row did not show its three settings with the
// one in force; a change sent nothing, or a word the engine does not take.
test('Rules: Pick settings shows Off, Shadow and On and sends the setting chosen', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, rules('off'));
  assert.deepEqual(pressed(w), ['true', 'false', 'false'], 'off is the setting in force');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'pick-shadow').click()), [{ action: 'rules', args: ['pick=shadow'], repo: 'sample' }]);
});

// Bug this guards: an engine with no rules.pick was sent a setting it refuses.
test('Rules: Pick settings sends nothing to an older engine', () => {
  const old = boot({ tab: 'rules' });
  deliver(old, rules('none'));
  assert.ok(['pick-off', 'pick-shadow', 'pick-on'].every((a) => act(rulesP(old), a).disabled), 'an older engine is sent none of them');
  assert.match(ruled(old).querySelector('[data-rule="pick"]').textContent, /needs a newer Conveyor/);
});

// Bugs this guards: the panel showed a group's whole spend as its spend per landed card (no division by the cards
// that landed), or a part sum for a group with an unpriced step. The snapshot's sum of a group's spend, blocked
// attempts in it, is the engine's (t_picktable, conveyor/tests/modelpick.test.sh); this case is given that sum. Group
// small docs: $10 over 3 cards, 2 landed (one on its first try, 4 review rounds), so $5.00 per landed card; group
// small code has a step with no price: unknown.
test("Cost: the Pick settings table divides each group's spend by its landed cards, and shows unknown for an unpriced step", () => {
  const w = boot();
  const d = full();
  d.panels.cost.data.cards.picks = [
    { repo: 'sample', group: 'small docs', model: 'claude-sonnet-5-5', effort: 'medium', cards: 3, landed: 2, usd: 10, firstTry: 1, reviews: 4, open: 1 },
    { repo: 'sample', group: 'small code', model: 'claude-sonnet-5-5', effort: 'medium', cards: 2, landed: 1, usd: null, firstTry: 1, reviews: 1, open: 1 },
  ];
  deliver(w, d);
  const row = (g) => Array.from(panel(w, 'cost').querySelector(`table.picks tr[data-group="${g}"]`).cells, (c) => c.textContent);
  assert.deepEqual(row('small docs').slice(1), ['small docs', 'claude-sonnet-5-5 medium', '3', '$5.00', '50%', '2.00', '1']);
  assert.deepEqual(row('small code').slice(3, 8), ['2', 'unknown: a step has no price', '100%', '1.00', '1']);
});

// Bugs this guards (#828): a group whose trial challenger was dropped after two blocked trial cards, or a trial card
// whose change touches pipeline files its issue does not name, was not shown to the owner.
test('Cost: Pick settings trials shows each dropped challenger and each flagged trial card', () => {
  const w = boot();
  const d = full();
  d.panels.cost.data.cards.trials = {
    dropped: [{ repo: 'sample', group: 'small docs', model: 'claude-sonnet-5-5', effort: 'medium', cards: ['c1-5', 'c1-10'] }],
    flagged: [{ repo: 'sample', card: 'c1-15', issue: 15, group: 'small code', files: ['ci/deploy.sh'] }],
  };
  deliver(w, d);
  const p = panel(w, 'cost');
  assert.match(p.querySelector('ul.trials li[data-dropped="small docs"]').textContent, /no more trials in small docs.*c1-5, c1-10.*default builder/);
  assert.match(p.querySelector('ul.trials li[data-flagged="c1-15"]').textContent, /#15: .*pipeline files .*ci\/deploy\.sh\. Its review and judge use the defaults/);
});
