// The Rules tab's Model prices: the built-in prices and the pack's overrides, each override saved or removed through
// `conveyor.sh prices` (POST control). Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, settle, full, act, rulesP, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const type = (el, v) => { el.value = v; el.dispatchEvent(new el.ownerDocument.defaultView.Event('input')); };
const prices = (w) => rulesP(w).querySelector('.rules-prices');
const rowOf = (w, m) => Array.from(prices(w).querySelectorAll('.rules-price')).find((r) => r.dataset.model === m);
const cells = (r) => Array.from(r.children, (td) => td.textContent).slice(0, 5);
const PRICES = { builtIn: [{ model: 'claude-opus-5-5', input: 4, output: 20, cacheRead: 0.2 }, { model: 'claude-sonnet-5-5', input: 2, output: 10, cacheRead: 0.1 },
  { model: 'claude-opus-5-5:fast', input: 8, output: 40, cacheRead: 0.4 }, { model: 'claude-sonnet-5-5:fast', input: 4, output: 20, cacheRead: 0.2 }],
  overrides: { 'claude-opus-5-5': { input: 1, output: 5, cacheRead: 0.1 }, 'claude-new-9': { input: 3, output: 15, cacheRead: 0.3 } } };

// Bug: a model newer than the release stayed unpriced with no way to price it, or the panel showed the built-in price
// of a model the pack overrides. Each model is listed once, at the price it is priced at, and says where that is from.
test('Rules: Model prices lists each model at the price in force, an override over its built-in row, and says OpenCode keeps its own cost', () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.prices = PRICES;
  deliver(w, d);
  assert.deepEqual(['claude-new-9', 'claude-opus-5-5', 'claude-sonnet-5-5'].map((m) => cells(rowOf(w, m))), [
    ['claude-new-9', '$3', '$15', '$0.3', 'your override'], ['claude-opus-5-5', '$1', '$5', '$0.1', 'your override'],
    ['claude-sonnet-5-5', '$2', '$10', '$0.1', 'built in']]);
  // Bug: a fast row showed its built-in price after its model's override, which the engine no longer uses (it prices
  // the fast mode at twice the override); a fast mode of a model with no override keeps its built-in row.
  assert.deepEqual(['claude-opus-5-5:fast', 'claude-sonnet-5-5:fast'].map((m) => cells(rowOf(w, m))), [
    ['claude-opus-5-5:fast', '$2', '$10', '$0.2', 'twice your override of claude-opus-5-5'], ['claude-sonnet-5-5:fast', '$4', '$20', '$0.2', 'built in']]);
  assert.ok(prices(w).textContent.includes('OpenCode steps keep the cost OpenCode reports.'));
  assert.ok(!act(rowOf(w, 'claude-sonnet-5-5'), 'price-clear'), 'a built-in row has no override to remove');
});

// Bug: a price sent as typed with a field left empty, a refusal shown as saved, or Remove override reaching no command.
test('Rules: Save sends the model and its three prices; a refusal says why; Remove override sends the clear', async () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.prices = PRICES;
  deliver(w, d);
  act(rowOf(w, 'claude-sonnet-5-5'), 'price-edit').click();
  assert.deepEqual(['model', 'input', 'output', 'cacheRead'].map((k) => act(prices(w), `price-${k}`).value), ['claude-sonnet-5-5', '2', '10', '0.1'], 'Change fills the form');
  type(act(prices(w), 'price-input'), '');
  act(prices(w), 'price-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [], 'a price left empty is not sent');
  type(act(prices(w), 'price-input'), '-1');
  w.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: prices set: the input price is dollars per million tokens, a number of 0 or more (such as 3 or 0.25), not "-1"; nothing changed') };
  act(prices(w), 'price-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'prices', args: ['set', 'claude-sonnet-5-5', '-1', '10', '0.1'], repo: 'sample' }]);
  assert.match(rulesP(w).querySelector('.rules-note').textContent, /^Not done: .*the input price is dollars per million tokens/);
  assert.equal(act(prices(w), 'price-input').value, '-1', 'refused: the value typed stays');
  w.reply = null;
  type(act(prices(w), 'price-input'), '2.5');
  act(prices(w), 'price-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'prices', args: ['set', 'claude-sonnet-5-5', '2.5', '10', '0.1'], repo: 'sample' }]);
  assert.equal(act(prices(w), 'price-model').value, '', 'saved: the form is empty again');
  act(rowOf(w, 'claude-new-9'), 'price-clear').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'prices', args: ['clear', 'claude-new-9'], repo: 'sample' }]);
  // Its Undo puts the override back as it was.
  act(rulesP(w).querySelector('.rules-note'), 'undo').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'prices', args: ['set', 'claude-new-9', '3', '15', '0.3'], repo: 'sample' }]);
});
