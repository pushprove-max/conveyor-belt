// SPDX-License-Identifier: Apache-2.0
// The rule Pick settings on the Board (#763): its row on the Rules tab (the control record's rules.pick: off, shadow
// or on) and the Cost panel's table of picked cards by group and builder (cost.cards.picks, one row a group and builder
// as the snapshot sums them). Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled, panel, cases, CLAUDE4 } from './dashboard-view.helpers.mjs';

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

// Bug this guards (#1040): On showed the Shadow line ("the card builds on its builder as before"), though On builds a
// trial card of an eligible group on the group's challenger, and (#1046) builds and reviews the card on the Judge's seats;
// (#1047) the line said a trial card was reviewed on the Judge's seats, though it is reviewed on the project's.
test('Rules: Pick settings shows the Shadow line for shadow and the trial line for on', () => {
  const w = boot({ tab: 'rules' });
  const line = () => ruled(w).querySelector('[data-rule="pick"]').textContent;
  deliver(w, rules('shadow'));
  assert.match(line(), /shadow: the pick is recorded, and the card builds on its builder as before/);
  next(w, rules('on'));
  assert.match(line(), /on: the card builds and is reviewed on the Judge's seats\. A card of an eligible group can build on the group's challenger as a trial, one trial card at a time, and is reviewed on the project's reviewer and judge\. A seat you set for a card always wins/);
  assert.doesNotMatch(line(), /builds on its builder as before/, 'On is not the Shadow line');
});

// The efforts each program takes, as the snapshot's packPick gives them (EFFORTS, conveyor/lib/paths.sh).
const EFFORTS = { claude: ['low', 'medium', 'high', 'xhigh', 'max'], codex: ['minimal', 'low', 'medium', 'high', 'xhigh'], opencode: ['minimal', 'low', 'medium', 'high', 'xhigh', 'max'] };
const picked = (lists) => { const d = rules('on'); d.panels.rules.data.packPick = { lists, efforts: EFFORTS }; return d; };

// Bugs this guards (#1067): the owner could only read each seat's models as text and set one effort range a seat, not
// choose which models the pick may give it with a range for each; the seat's label and text ran together
// ("BUILDERmodels: ..."); a model's menus offered efforts its program does not take; Save sent a list in a shape
// `conveyor.sh pick models` does not take, or the row went on showing the old list after the save or did not show
// the saved one after a reload; a refresh dropped a model checked and not yet saved; unchecking every model did not
// take the list off; saving the reviewer's list gave the focus to another seat's Save.
test('Rules: Pick settings saves the models checked for a seat, each with its own effort range, and shows them after a reload', async () => {
  const w = boot({ tab: 'rules' });
  const d = picked({ reviewer: { 'gpt-6.1-sol': { min: 'low', max: 'medium' } } });
  const again = structuredClone(d);
  deliver(w, d);
  const seat = (k, win = w) => ruled(win).querySelector(`[data-rule="pick"] [data-seat="${k}"]`);
  const head = (k, win = w) => seat(k, win).querySelector('.rules-pick-head').textContent;
  const menu = (k, id, which, win = w) => act(seat(k, win), `pick-${which}-${k}-${id}`);
  const words = (sel) => Array.from(sel.options, (o) => o.value);
  const choose = (k, id, which, v) => { const s = menu(k, id, which); s.value = v; s.dispatchEvent(new w.Event('change')); };
  assert.equal(head('builder'), 'Builder All models, any effort', 'a seat with no list says so, with a space after its label');
  assert.equal(head('reviewer'), 'Reviewer gpt-6.1-sol: low to medium');
  assert.deepEqual(Array.from(seat('builder').querySelectorAll('.rules-pick-model'), (r) => r.dataset.model), CLAUDE4, "each of the builder's allowed models is a row");
  assert.equal(menu('builder', 'claude-opus-5-5', 'min'), null, 'a model not checked has no menus');
  assert.deepEqual(words(menu('reviewer', 'gpt-6.1-sol', 'min')), [''].concat(EFFORTS.codex), "a Codex model's menus hold Codex's efforts alone");
  act(seat('builder'), 'pick-model-builder-claude-opus-5-5').click();
  act(seat('builder'), 'pick-model-builder-claude-sonnet-5-5').click();
  assert.deepEqual(words(menu('builder', 'claude-opus-5-5', 'max')), [''].concat(EFFORTS.claude), "a Claude model's menus hold Claude's efforts alone");
  choose('builder', 'claude-opus-5-5', 'min', 'medium'); choose('builder', 'claude-opus-5-5', 'max', 'high'); choose('builder', 'claude-sonnet-5-5', 'max', 'low');
  again.panels.rules.data.modelSettings.builder.effort = 'max';  // a snapshot that differs, so the panel draws again
  next(w, again);
  assert.equal(act(seat('builder'), 'pick-model-builder-claude-opus-5-5').checked, true, 'a refresh keeps a model checked and not yet saved');
  assert.equal(menu('builder', 'claude-opus-5-5', 'min').value, 'medium', 'a refresh keeps a range picked and not yet saved');
  assert.deepEqual(await sent(w, () => act(seat('builder'), 'pick-save-builder').click()),
    [{ action: 'pick-models', args: ['builder', 'claude-opus-5-5=medium-high', 'claude-sonnet-5-5=-low'], repo: 'sample' }]);
  await settle();
  assert.equal(head('builder'), 'Builder claude-opus-5-5: medium to high; claude-sonnet-5-5: low or lower', 'the saved list shows before the next snapshot');
  act(seat('reviewer'), 'pick-model-reviewer-gpt-6.1-sol').click();
  const save = act(seat('reviewer'), 'pick-save-reviewer');
  save.focus();
  assert.deepEqual(await sent(w, () => save.click()), [{ action: 'pick-models', args: ['reviewer', 'clear'], repo: 'sample' }], 'no model checked takes the list off');
  await settle();
  assert.equal(head('reviewer'), 'Reviewer All models, any effort');
  assert.equal(w.document.activeElement, act(seat('reviewer'), 'pick-save-reviewer'), "the focus comes back to the reviewer's Save");
  // A reload: a new page given the pack as the save left it.
  const w2 = boot({ tab: 'rules' });
  deliver(w2, picked({ builder: { 'claude-opus-5-5': { min: 'medium', max: 'high' }, 'claude-sonnet-5-5': { max: 'low' } } }));
  assert.deepEqual(Array.from(seat('builder', w2).querySelectorAll('.rules-pick-model input:checked'), (b) => b.closest('.rules-pick-model').dataset.model), ['claude-opus-5-5', 'claude-sonnet-5-5']);
  assert.deepEqual(['claude-opus-5-5', 'claude-sonnet-5-5'].flatMap((id) => ['min', 'max'].map((x) => menu('builder', id, x, w2).value)), ['medium', 'high', '', 'low']);
  const old = rules('on');
  next(w2, old);
  assert.equal(seat('builder', w2), null, 'a snapshot with no packPick (an older engine) shows no list to set');
});

// Bugs this guards (#1047, #1086): a card did not show the seats the Judge gave it, the Judge's reason for each, or
// that a limit of the pack moved a seat; a failed pick looked like a pick; the card's seats line showed the project's
// builder at medium beside the Judge's pick at high, so the reader could not tell which seats the card runs on; a pick
// the card does not run on (Shadow, a trial) was shown as its seats; the Judge's reasons and clamps went missing on a
// card that does not run on the Judge's seats, and a clamp with no model was dropped; a builder the owner cleared
// after the card started still showed as "this card"; a Shadow card said it does not run on the seat shown above it.
const RUN = { builder: { model: 'claude-opus-5-5', effort: 'high', by: 'judge' }, reviewer: { model: 'gpt-6.1-sol', effort: 'low', by: 'judge' },
  judge: { model: 'claude-sonnet-5-5', effort: 'medium', by: 'judge' } };
const PICKED = {
  builder: { model: 'claude-opus-5-5', effort: 'high', why: 'A wide change.', asked: { model: 'claude-opus-5-5', effort: 'high' } },
  reviewer: { model: 'gpt-6.1-sol', effort: 'low', why: 'One file to read.', asked: { model: 'gpt-6.1-sol', effort: 'low' } },
  judge: { model: 'claude-sonnet-5-5', effort: 'medium', why: 'Few findings expected.', asked: { model: 'claude-sonnet-5-5', effort: 'low' },
    clamp: 'low is not one of the efforts the judge may take on claude-sonnet-5-5 (medium, high): claude-sonnet-5-5 at medium' },
  model: 'claude-opus-5-5', mode: 'on', run: RUN };
const NOTRUN = { builder: null, reviewer: null, judge: null };
const parts = (row) => Array.from(row.querySelector('.board-seat-line').children, (c) => c.textContent);
test("Board: a card shows the seats it runs on, a row each, and the Judge's reason for each in its own callout", () => {
  const w = boot({ tab: 'control' });
  const d = full(), b = d.panels.board.data;
  b.modelSettings.builder.effort = 'medium';  // the project's builder at medium; the Judge's pick builds at high
  b.review[0].seats = PICKED;
  b.landed = [
    { repo: 'sample', card: 'c5-8', issue: 8, title: 'Failed pick', url: null, step: 'landed', usd: 1, reviews: 1, seats: { failed: 'the judge timed out', mode: 'on', run: NOTRUN } },
    { repo: 'sample', card: 'c5-9', issue: 9, title: 'Not picked', url: null, step: 'landed', usd: 1, reviews: 1, seats: null },
    { repo: 'sample', card: 'c5-10', issue: 10, title: 'Shadow pick', url: null, step: 'landed', usd: 1, reviews: 1, seats: { ...PICKED, mode: 'shadow', run: NOTRUN } },
    { repo: 'sample', card: 'c5-11', issue: 11, title: 'Trial', url: null, step: 'landed', usd: 1, reviews: 1,
      seats: { ...PICKED, reviewer: { why: 'r', asked: { model: null, effort: null }, clamp: "the pack allows the reviewer no model, so the project's reviewer stands" },
        run: { builder: { model: 'claude-sonnet-5-5', effort: 'high', by: 'trial' }, reviewer: null, judge: null } } },
    { repo: 'sample', card: 'c5-81', issue: 81, title: 'Shadow, same reviewer', url: null, step: 'landed', usd: 1, reviews: 1,
      seats: { ...PICKED, reviewer: { ...PICKED.reviewer, effort: 'medium' }, mode: 'shadow', run: NOTRUN } },
  ];
  // The pick recorded a builder the owner set; the control record has none for issue 82 now (cleared).
  b.review.push({ ...b.review[0], card: 'c3-82', issue: 82, title: 'Builder cleared',
    seats: { ...PICKED, run: { ...NOTRUN, builder: { model: 'claude-sonnet-5-5', effort: 'low', by: 'card' } } } });
  deliver(w, d);
  const card = (col, n) => panel(w, 'board').querySelector(`.board-col[data-col="${col}"] .bcard[data-issue="${n}"]`);
  const c = card('review', 63), row = (k) => c.querySelector(`.board-seat[data-seat="${k}"]`);
  assert.deepEqual(parts(row('builder')), ['Builder', 'claude-opus-5-5 · high', "Judge's pick"]);
  assert.deepEqual(Array.from(c.querySelectorAll('[data-seat="builder"]'), (x) => x.textContent).filter((t) => /medium/.test(t)), [],
    "the project's builder at medium is nowhere on the card");
  assert.equal(c.querySelectorAll('.board-seats-line').length, 1, 'one list of seats on the card');
  assert.deepEqual(parts(row('reviewer')), ['Reviewer', 'gpt-6.1-sol · low', "Judge's pick"]);
  const why = (k) => Array.from(row(k).querySelectorAll('.why-block'), (x) => [x.dataset.by, x.querySelector('.why-label').textContent,
    Array.from(x.querySelectorAll('.why-line'), (l) => l.textContent)]);
  assert.deepEqual(why('builder'), [['judge', 'Why the Judge chose it', ['A wide change.']]]);
  assert.deepEqual(why('reviewer'), [['judge', 'Why the Judge chose it', ['One file to read.']]], 'a seat no limit moved says nothing of a clamp');
  assert.deepEqual(why('judge'), [['judge', 'Why the Judge chose it', ['Few findings expected.',
    'Clamped: low is not one of the efforts the judge may take on claude-sonnet-5-5 (medium, high): claude-sonnet-5-5 at medium']]]);
  assert.ok(act(c, 'seats') && act(c, 'seats-pick'), 'Settings and Pick for me stay');
  // A failed pick: the card runs on the project's seats, and the callout says why.
  assert.deepEqual(Array.from(card('landed', 8).querySelectorAll('.board-seat'), (r) => parts(r)[2]), ["project's", "project's", "project's"]);
  assert.match(card('landed', 8).querySelector('.why-block').textContent, /Why the card runs on the project's seats.*The Judge's pick failed: the judge timed out/);
  assert.equal(card('landed', 9).querySelector('.board-seats'), null, 'a landed card the rule did not pick shows no seats');
  const shadow = card('landed', 10);
  assert.deepEqual(Array.from(shadow.querySelectorAll('.board-seat'), (r) => parts(r)[2]), ["project's", "project's", "project's"], 'a Shadow pick is not the seats the card runs on');
  const lines = (el, k) => Array.from(el.querySelectorAll(`.board-seat[data-seat="${k}"] .why-block .why-line`), (l) => l.textContent);
  assert.deepEqual(lines(shadow, 'builder'), ['The Judge chose claude-opus-5-5 · high; the card does not run on it, as the rule Pick settings is in Shadow.', 'A wide change.'],
    "a Shadow card keeps the Judge's reason, and says the card does not run on its seat");
  assert.deepEqual(lines(shadow, 'judge').slice(-1), ['Clamped: low is not one of the efforts the judge may take on claude-sonnet-5-5 (medium, high): claude-sonnet-5-5 at medium']);
  const trial = card('landed', 11);
  assert.deepEqual(Array.from(trial.querySelectorAll('.board-seat'), (r) => parts(r).slice(1)),
    [['claude-sonnet-5-5 · high', 'trial'], ['gpt-6.1-sol · medium', "project's"], ['claude-opus-5-5 · medium', "project's"]], 'a trial runs on the challenger and the project\'s reviewer and judge');
  assert.deepEqual(lines(trial, 'builder'), ['The Judge chose claude-opus-5-5 · high; the card does not run on it.', 'A wide change.']);
  assert.deepEqual(lines(trial, 'reviewer'), ['r', "Clamped: the pack allows the reviewer no model, so the project's reviewer stands"], 'a clamp with no model shows');
  assert.deepEqual(lines(card('landed', 81), 'reviewer'), ['One file to read.'], 'the Judge chose the seat the card runs on: no line says it does not');
  assert.deepEqual(parts(card('review', 82).querySelector('.board-seat[data-seat="builder"]')).slice(1), ['claude-opus-5-5 · medium', "project's"],
    "a builder the owner cleared runs on the project's");
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

// The judge replay study (#765) beside the pick table: the last replay, Estimate (no model called) and Run.
// Bugs this guards: the panel did not show how often the replay judge agreed, the findings where it differs or its
// cost against the recorded judge's; Run was sent before the owner saw the estimate, or on one click; an estimate or
// a run went out with another model or effort than the ones picked; one left-out review read "1 reviews were" (#856).
test('Cost: the judge replay shows the last result, and runs only after its estimate and a second click', async () => {
  const w = boot();
  const d = full();
  d.panels.cost.data.cards.replays = [{ repo: 'sample', judge: { choices: ['claude-haiku-5-5'], allowed: { claude: ['claude-haiku-5-5'] }, clis: { claude: { efforts: ['low', 'medium'] } } },
    last: { time: '2026-11-08T12:00:00Z', model: 'claude-haiku-5-5', effort: 'low', reviews: 3, skipped: 1, findings: 3, agree: 2, unanswered: 1, usd: 0.3, recordedUsd: 6,
      differ: [{ card: 'c1-7', issue: 7, n: 2, finding: '[P2] a.txt:1 F-two', recorded: 'decline', replay: 'accept', reason: 'the change causes it' }] } }];
  deliver(w, d);
  const box = () => panel(w, 'cost').querySelector('.replay[data-repo="sample"]');
  assert.match(box().querySelector('.replay-last').textContent, /agreed with the recorded judge on 2 of 3 findings of 3 reviews\. 1 got no answer\. 1 review was left out: it had no diff, or not the diff that its judge read\. Cost: \$0\.30; the recorded judge cost \$6\.00/);
  assert.match(box().querySelector('.replay-differ').textContent, /#7 \[P2\] a\.txt:1 F-two.*recorded judge: decline\. The replay: accept, the change causes it/);
  assert.equal(act(box(), 'replay-run'), null, 'no Run before an estimate');
  const e = act(box(), 'replay-effort');
  e.value = 'low'; e.dispatchEvent(new w.Event('change'));
  w.reply = { ok: true, status: 200, text: () => Promise.resolve('{"estimate":true,"model":"claude-haiku-5-5","effort":"low","reviews":3,"skipped":1,"findings":4,"usd":0.3,"recordedUsd":6}') };
  act(box(), 'replay-estimate').click();
  await settle(); await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'replay', args: ['claude-haiku-5-5', 'low', '--estimate'], repo: 'sample' }]);
  assert.match(box().querySelector('.replay-estimate').textContent, /About \$0\.30 to replay 4 findings of 3 reviews.* 1 review is left out: it has no diff, or not the diff that its judge read\./);
  // A second estimate with two left out keeps the plural.
  w.reply = { ok: true, status: 200, text: () => Promise.resolve('{"estimate":true,"model":"claude-haiku-5-5","effort":"low","reviews":3,"skipped":2,"findings":4,"usd":0.3,"recordedUsd":6}') };
  act(box(), 'replay-estimate').click();
  await settle(); await settle();
  w.posts.splice(0);
  assert.match(box().querySelector('.replay-estimate').textContent, /About \$0\.30 to replay 4 findings of 3 reviews.* 2 reviews are left out: they have no diff, or not the diff that their judge read\./);
  act(box(), 'replay-run').click();
  await settle();
  assert.deepEqual(w.posts, [], 'one click sends no run');
  act(box(), 'replay-run').click();
  await settle(); await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'replay', args: ['claude-haiku-5-5', 'low'], repo: 'sample' }]);
  assert.match(box().querySelector('.answer-note').textContent, /The replay started/);
});
