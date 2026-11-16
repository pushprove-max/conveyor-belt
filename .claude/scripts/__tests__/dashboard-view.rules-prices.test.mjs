// SPDX-License-Identifier: Apache-2.0
// The Rules tab's Model prices: the built-in prices and the pack's prices, added models and aliases, grouped and
// searched, each changed in its row through `conveyor.sh prices` (POST control). Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { boot, deliver, settle, full, act, panel, pricesP, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const type = (el, v) => { el.value = v; el.dispatchEvent(new el.ownerDocument.defaultView.Event('input')); };
const pick = (el, v) => { el.value = v; el.dispatchEvent(new el.ownerDocument.defaultView.Event('change')); };
const prices = pricesP;
// The line of the Model prices panel: what a change there did.
const said = (w) => panel(w, 'rules-prices').querySelector('.rules-note');
const rowOf = (w, m) => Array.from(prices(w).querySelectorAll('.rules-price')).find((r) => r.dataset.model === m);
const groupOf = (w, k) => prices(w).querySelector(`[data-price-group="${k}"]`);
const modelsIn = (el) => Array.from(el.querySelectorAll('.rules-price')).map((r) => r.dataset.model);
const shown = (el) => Array.from(el.querySelectorAll('.rules-price')).filter((r) => !r.hidden).map((r) => r.dataset.model);
// A row's cells, its first lines (a fast mode is each cell's second line).
const cells = (r) => Array.from(r.children).slice(1, 6).map((td) => td.firstChild.textContent);
const fastLine = (r) => Array.from(r.querySelectorAll('.rules-price-fastline'), (x) => x.textContent);
const chips = (r) => Array.from(r.querySelectorAll('.chip'), (x) => x.textContent);
const posted = (w) => w.posts.splice(0).map((p) => p.args || p.body.args);
const row = (model, input, output, cacheRead) => ({ model, input, output, cacheRead, cacheWrite: input * 1.25 });
const PRICES = {
  builtIn: [row('claude-opus-5-5', 4, 20, 0.2), row('claude-opus-4-8', 5, 25, 0.5), row('claude-sonnet-5-5', 2, 10, 0.1), row('claude-sonnet-4-6', 3, 15, 0.3),
    row('claude-haiku-5-5', 0.1, 0.5, 0.01), row('claude-opus-5-5:fast', 8, 40, 0.4), row('claude-sonnet-5-5:fast', 4, 20, 0.2), row('gpt-6.1-sol', 2, 10, 0.1), row('gpt-6-astra', 10, 50, 1)],
  overrides: { 'claude-opus-5-5': { input: 1, output: 5, cacheRead: 0.1 }, 'claude-sonnet-5-5': { aliases: ['proxy/sonnet'] } },
  names: { 'claude-opus-5-5': 'Opus 5.5', 'claude-opus-4-8': 'Opus 4.8', 'claude-sonnet-5-5': 'Sonnet 5.5', 'claude-sonnet-4-6': 'Sonnet 4.6', 'claude-haiku-5-5': 'Haiku 5.5',
    'gpt-6.1-sol': 'GPT-6.1 Sol', 'gpt-6-astra': 'GPT-6 Astra' },
  seen: [{ model: 'claude-sonnet-4.6', sessions: 3, routes: ['proxy'], as: null }, { model: 'proxy/sonnet', sessions: 2, routes: [], as: 'claude-sonnet-5-5' },
    { model: 'opencode:prov/m-2', sessions: 1, routes: [], as: null }],
};
// The Rules tab with these prices; the Tests seat runs Haiku 5.5 (the builder and judge Opus 5.5, the reviewer Sol).
function open(over = {}) {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.prices = Object.assign(JSON.parse(JSON.stringify(PRICES)), over);
  d.panels.rules.data.control.tests = { cli: 'claude', model: 'claude-haiku-5-5', effort: 'low' };
  deliver(w, d);
  return w;
}

// Bug: one flat list of every model, old and current mixed, nothing marking the ones this project uses, and a fast
// mode as a row of its own. Models in use come first with their marks (a role, or sessions through an alias), then
// Claude and OpenAI by family, newest first, the older versions folded; a fast mode is its model's second line.
test('Rules: Model prices groups the models, in use first with its marks, older ones folded, a fast mode as a second line', () => {
  const w = open();
  assert.deepEqual(Array.from(prices(w).querySelectorAll('[data-price-group]'), (g) => g.dataset.priceGroup), ['use', 'claude', 'openai', 'opencode']);
  assert.deepEqual(modelsIn(groupOf(w, 'use')), ['claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5', 'gpt-6.1-sol']);
  assert.deepEqual([chips(rowOf(w, 'claude-opus-5-5')), chips(rowOf(w, 'claude-sonnet-5-5')), chips(rowOf(w, 'claude-haiku-5-5')), chips(rowOf(w, 'gpt-6.1-sol'))],
    [['builder', 'judge'], ['2 sessions in 30 days'], ['Tests'], ['reviewer']]);
  const claude = groupOf(w, 'claude'), older = claude.querySelector('details.rules-price-older');
  assert.deepEqual(modelsIn(claude).filter((m) => !older.contains(rowOf(w, m))), [], 'every current Claude model is in use');
  assert.equal(older.querySelector('summary').textContent, 'Older Claude models (2)');
  assert.deepEqual(modelsIn(older), ['claude-opus-4-8', 'claude-sonnet-4-6']);
  assert.deepEqual(modelsIn(groupOf(w, 'openai')), ['gpt-6-astra']);
  // The name shown bold, its ID and other IDs under it; the price in force and where it is from.
  const sonnet = rowOf(w, 'claude-sonnet-5-5');
  assert.equal(sonnet.querySelector('strong').textContent, 'Sonnet 5.5');
  assert.equal(sonnet.querySelector('.board-from').textContent, 'claude-sonnet-5-5 · also: proxy/sonnet');
  assert.deepEqual(cells(sonnet), ['$2', '$10', '$0.1', '$2.5', 'built in']);
  assert.ok(!act(sonnet, 'price-reset'), 'a built-in price has nothing to reset');
  // Opus 5.5 is priced from the pack: its fast mode, which the pack does not price, is twice that price (the engine's).
  const opus = rowOf(w, 'claude-opus-5-5');
  assert.deepEqual(cells(opus), ['$1', '$5', '$0.1', '$1.25', 'Saved, from the pack']);
  assert.deepEqual(fastLine(opus), [':fast', '$2', '$10', '$0.2', '$2.5', 'twice your price']);
  assert.ok(!rowOf(w, 'claude-opus-5-5:fast'), 'a fast mode is no row of its own');
  assert.ok(act(opus, 'price-reset').textContent.startsWith('Reset to built-in ($4 / $20 / $0.2 / $5)'));
});

// Bug: no way to find a model in a long list. The search matches an ID, a name or an alias as it is typed, and opens a
// folded group with a match.
test('Rules: the Model prices search filters by ID, name or alias and opens a folded match', () => {
  const w = open();
  type(act(prices(w), 'price-search'), 'proxy/sonnet');
  assert.deepEqual(shown(prices(w)), ['claude-sonnet-5-5']);
  assert.ok(groupOf(w, 'openai').hidden, 'a group with no match hides');
  type(act(prices(w), 'price-search'), 'opus 4.8');
  assert.deepEqual(shown(prices(w)), ['claude-opus-4-8']);
  assert.equal(groupOf(w, 'claude').querySelector('details').open, true);
});

// Bug: Change filled a form at the bottom, far from the row, with no units and nothing saying the price was saved.
// Edit opens the row in place, with $ and "/ M tokens"; Save sends each change (a refusal says why and keeps what
// was typed); the saved row then says it is from the pack, by its new name.
test('Rules: a model row edits in place; Save sends its price, name and other IDs and the row says it is saved', async () => {
  const w = open();
  act(rowOf(w, 'claude-sonnet-5-5'), 'price-edit').click();
  const ed = rowOf(w, 'claude-sonnet-5-5');
  assert.ok(ed.classList.contains('rules-price-editing'));
  assert.deepEqual(['input', 'output', 'cacheRead', 'cacheWrite'].map((k) => act(ed, `price-${k}`).value), ['2', '10', '0.1', '']);
  assert.match(act(ed, 'price-input').closest('label').textContent, /^Input\$\/ M tokens$/);
  type(act(ed, 'price-input'), '-1');
  w.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: prices set: the input price is dollars per million tokens, a number of 0 or more (such as 3 or 0.25), not "-1"; nothing changed') };
  act(ed, 'price-save').click();
  await settle();
  assert.deepEqual(posted(w), [['set', 'claude-sonnet-5-5', '-1', '10', '0.1']]);
  assert.match(said(w).textContent, /^Not done: .*the input price is dollars per million tokens/);
  assert.equal(act(rowOf(w, 'claude-sonnet-5-5'), 'price-input').value, '-1', 'refused: the value typed stays, in the row');
  w.reply = null;
  const row2 = rowOf(w, 'claude-sonnet-5-5');
  type(act(row2, 'price-input'), '2.5');
  type(act(row2, 'price-name'), 'Sonnet (proxy)');
  type(act(row2, 'price-alias-new'), 'other/sonnet');
  act(row2, 'price-alias-add').click();
  act(rowOf(w, 'claude-sonnet-5-5'), 'price-save').click();
  await settle(); await settle(); await settle();
  assert.deepEqual(posted(w), [['set', 'claude-sonnet-5-5', '2.5', '10', '0.1'], ['name', 'claude-sonnet-5-5', 'Sonnet (proxy)'], ['alias', 'claude-sonnet-5-5', 'add', 'other/sonnet']]);
  const saved = rowOf(w, 'claude-sonnet-5-5');
  assert.deepEqual([saved.querySelector('strong').textContent, saved.querySelector('.board-from').textContent, cells(saved)],
    ['Sonnet (proxy)', 'claude-sonnet-5-5 · also: proxy/sonnet, other/sonnet', ['$2.5', '$10', '$0.1', '$3.125', 'Saved, from the pack']]);
  assert.ok(act(saved, 'price-reset'), 'a saved row offers Reset to built-in');
});

// Bug: a changed price could not be put back to the built-in one. Reset to built-in sends the clear, the row is built
// in again at once, and its Undo puts the price back.
test('Rules: Reset to built-in removes the override, and its Undo puts it back', async () => {
  const w = open();
  act(rowOf(w, 'claude-opus-5-5'), 'price-reset').click();
  await settle();
  assert.deepEqual(posted(w), [['clear', 'claude-opus-5-5']]);
  assert.deepEqual(cells(rowOf(w, 'claude-opus-5-5')), ['$4', '$20', '$0.2', '$5', 'built in']);
  act(said(w), 'undo').click();
  await settle();
  assert.deepEqual(posted(w), [['set', 'claude-opus-5-5', '1', '5', '0.1']]);
});

// Bug: a fast mode's price could not be changed or reset: Edit and Reset acted only on the model's own ID. Edit :fast
// starts at the price shown (twice the pack's price here) and saves it under <model>:fast; that row then has its own
// Reset :fast, which clears only the fast price.
test('Rules: a fast mode price edits in its row and resets to built-in on its own', async () => {
  const w = open();
  act(rowOf(w, 'claude-opus-5-5'), 'price-fast-edit').click();
  const ed = rowOf(w, 'claude-opus-5-5');
  assert.deepEqual(['input', 'output', 'cacheRead'].map((k) => act(ed, `price-${k}`).value), ['2', '10', '0.2']);
  type(act(ed, 'price-input'), '3');
  act(ed, 'price-save').click();
  await settle();
  assert.deepEqual(posted(w), [['set', 'claude-opus-5-5:fast', '3', '10', '0.2']]);
  const r = rowOf(w, 'claude-opus-5-5');
  assert.deepEqual(fastLine(r).slice(1, 2), ['$3']);
  // Bug: Reset :fast promised the built-in $8 input, but with Opus 5.5 at your $1 the cleared fast mode costs twice
  // that, $2: the button names the price clearing gives.
  assert.equal(act(r, 'price-fast-reset').textContent, 'Reset :fast to twice your price ($2 / $10 / $0.2 / $2.5)');
  act(r, 'price-fast-reset').click();
  await settle();
  assert.deepEqual(posted(w), [['clear', 'claude-opus-5-5:fast']]);
});

// Bug: no way to price a model the table does not know. Add model takes its ID, name, provider and prices ("Same price
// as" copies a known model's), refuses an ID that is priced already, and the model shows in its group, marked added.
test('Rules: Add model sends the ID, name, provider and prices, and the model shows as added', async () => {
  const w = open();
  act(prices(w), 'price-add').click();
  const f = () => prices(w).querySelector('.rules-price-addform');
  type(act(f(), 'price-add-model'), 'claude-opus-5-5');
  type(act(f(), 'price-add-name'), 'Mine');
  pick(act(f(), 'price-add-same'), 'claude-sonnet-5-5');
  assert.deepEqual(['input', 'output', 'cacheRead', 'cacheWrite'].map((k) => act(f(), `price-add-${k}`).value), ['2', '10', '0.1', '']);
  act(f(), 'price-add-save').click();
  await settle();
  assert.deepEqual(posted(w), []);
  assert.match(said(w).textContent, /claude-opus-5-5 is priced already/);
  type(act(f(), 'price-add-model'), 'my-model');
  pick(act(f(), 'price-add-provider'), 'other');
  type(act(f(), 'price-add-cacheWrite'), '3');
  act(f(), 'price-add-save').click();
  await settle();
  assert.deepEqual(posted(w), [['add', 'my-model', 'other', 'Mine', '2', '10', '0.1', '3']]);
  assert.ok(!f(), 'saved: the form closes');
  const added = rowOf(w, 'my-model');
  assert.ok(groupOf(w, 'other').contains(added));
  assert.deepEqual([chips(added), cells(added)], [['added'], ['$2', '$10', '$0.1', '$3', 'Saved, from the pack']]);
  act(added, 'price-remove').click();
  await settle();
  assert.deepEqual(posted(w), [['remove', 'my-model']]);
});

// Bug: a session through a proxy whose model ID differs is priced at nothing, with no way to say which model it is.
// Each such ID is listed with its count and route; This is… (the likely model picked first) adds it as an alias, and
// Add as new model opens Add model with its ID.
test('Rules: an ID seen but not priced is listed, and This is… adds it as an alias of the likely model', async () => {
  const w = open();
  const box = prices(w).querySelector('.rules-prices-unpriced');
  const line = box.querySelector('.rules-unpriced');
  assert.equal(line.firstChild.textContent, 'claude-sonnet-4.6 (3 sessions, through the API proxy)');
  assert.equal(box.querySelectorAll('.rules-unpriced').length, 1, 'an ID an alias prices, or OpenCode reports, is not listed');
  assert.equal(act(line, 'price-this-model').value, 'claude-sonnet-4-6');
  act(line, 'price-new').click();
  assert.equal(act(prices(w).querySelector('.rules-price-addform'), 'price-add-model').value, 'claude-sonnet-4.6');
  act(prices(w).querySelector('.rules-unpriced'), 'price-this').click();
  await settle();
  assert.deepEqual(posted(w), [['alias', 'claude-sonnet-4-6', 'add', 'claude-sonnet-4.6']]);
  assert.ok(!prices(w).querySelector('.rules-prices-unpriced'), 'priced now: the ID is no longer listed');
  assert.match(rowOf(w, 'claude-sonnet-4-6').querySelector('.board-from').textContent, /also: claude-sonnet-4\.6$/);
});

// Bug: a model ID that is an alias, or a model the pack renames, shown as the raw ID elsewhere on the Board. A running
// card on an alias shows the display name of the model it means; Metrics' cost by model shows the name the pack gives.
test('Board: a card running on an alias ID, and the cost by model, show the model\'s display name', () => {
  const w = boot();
  const d = full();
  d.panels.rules.data.prices = { builtIn: PRICES.builtIn, overrides: { 'gpt-6.1-sol': { aliases: ['gpt-x'] }, 'claude-sonnet-5-5': { name: 'Sonnet (proxy)' } },
    names: PRICES.names, seen: [] };
  deliver(w, d);
  const meta = Array.from(panel(w, 'belt').querySelectorAll('.live-cost'), (x) => x.parentNode.textContent);
  assert.ok(meta.some((t) => t.includes('GPT-6.1 Sol')), meta.join(' | '));
  assert.ok(!meta.some((t) => t.includes('gpt-x')), meta.join(' | '));
  const models = panel(w, 'metrics').querySelector('[data-chart="models"]').textContent;
  assert.ok(models.includes('Sonnet (proxy)') && !models.includes('claude-sonnet-5-5'), models);
});

// Bug: a finished step on an alias is recorded as the model it means (pricedAs), and Metrics showed that model's raw ID
// when the pack gives aliases but no name: proxy/sonnet's cost read claude-sonnet-5-5, not Sonnet 5.5.
test('Board: the cost by model shows the display name of a model the pack gives aliases but no name', () => {
  const w = boot();
  const d = full();
  d.panels.rules.data.prices = { builtIn: PRICES.builtIn, overrides: { 'claude-sonnet-5-5': { aliases: ['proxy/sonnet'] } }, names: PRICES.names, seen: [] };
  deliver(w, d);
  const models = panel(w, 'metrics').querySelector('[data-chart="models"]').textContent;
  assert.ok(models.includes('Sonnet 5.5') && !models.includes('claude-sonnet-5-5'), models);
});

// Bug: an OpenCode model could only keep OpenCode's cost. Each OpenCode model says where its price is from; Set my
// price sends a price of its own; one not in use and not priced is folded.
test('Rules: an OpenCode model keeps OpenCode\'s cost until Set my price sends one', async () => {
  const w = open();
  const g = groupOf(w, 'opencode'), m2 = rowOf(w, 'opencode:prov/m-2');
  assert.deepEqual([g.querySelector('summary').textContent, modelsIn(g.querySelector('details'))], ['All OpenCode models (1)', ['opencode:openrouter/vendor/m-1']]);
  assert.equal(m2.children[5].textContent, 'as OpenCode reports');
  act(m2, 'price-oc-set').click();
  const ed = rowOf(w, 'opencode:prov/m-2');
  assert.ok(!act(ed, 'price-name'), 'its own price only: no name or other IDs');
  ['input', 'output', 'cacheRead'].forEach((k) => type(act(ed, `price-${k}`), '0'));
  act(ed, 'price-save').click();
  await settle();
  assert.deepEqual(posted(w), [['set', 'opencode:prov/m-2', '0', '0', '0']]);
  assert.equal(rowOf(w, 'opencode:prov/m-2').children[5].textContent, 'your price');
  assert.ok(act(rowOf(w, 'opencode:prov/m-2'), 'price-oc-back'));
});

// Bug: a model added with provider OpenCode was drawn as a bare OpenCode ID, its display name lost and no Edit or
// Remove. It is a model's row: its name, the added mark, Edit and Remove.
test('Rules: an added OpenCode model shows its name, and has Edit and Remove', async () => {
  const w = open({ overrides: { 'opencode:p/m': { provider: 'opencode', name: 'My model', input: 1, output: 2, cacheRead: 0.1 } } });
  const r = rowOf(w, 'opencode:p/m');
  assert.ok(groupOf(w, 'opencode').contains(r));
  assert.deepEqual([r.querySelector('strong').textContent, chips(r)], ['My model', ['added']]);
  assert.ok(act(r, 'price-edit'));
  act(r, 'price-remove').click();
  await settle();
  assert.deepEqual(posted(w), [['remove', 'opencode:p/m']]);
});

// Bug: the research lane's model had no in-use mark: only the builder, reviewer, judge and Tests were read.
test('Rules: the research lane model is in use, with its mark', () => {
  const w = open({ research: 'claude-sonnet-4-6' });
  const r = rowOf(w, 'claude-sonnet-4-6');
  assert.ok(groupOf(w, 'use').contains(r));
  assert.deepEqual(chips(r), ['research lane']);
});

// Bug: the page head covered the section as it scrolled. jsdom has no layout, so this reads the rule that keeps a part
// the page scrolls to below the head.
test('Board: a part the page scrolls to stops below the page head', () => {
  const css = readFileSync(new URL('../../dashboard/app.css', import.meta.url), 'utf8');
  assert.match(css, /html \{ scroll-padding-top: calc\(var\(--head-h, 64px\) \+ var\(--sp-2\)\); \}/);
});
