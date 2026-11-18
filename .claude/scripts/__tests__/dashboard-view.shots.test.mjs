// SPDX-License-Identifier: Apache-2.0
// Needs you: the project's own screenshots of a visible change, beside its Approve (#308). Shared setup:
// dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, panel, deliver, next, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const A = 'a'.repeat(40), B = 'b'.repeat(40), PNG = `${'c'.repeat(40)}.png`;
// The waiting card c1-12 with its kept patch's hash and the screenshots kept for the patch <kept>.
function data(kept) {
  const d = full();
  Object.assign(d.panels.needs.data.cards.waiting[0], { patch: A, shots: { patch: kept, shots: [{ file: PNG, caption: 'pay/button.png' }] } });
  return d;
}
const row = (w) => panel(w, 'needs').querySelector('li[data-key="waiting:c1-12"]');

// Bugs this guards: the owner approved a visible change from text alone, though the project's run had made
// screenshots of it; an image kept for an older patch of the card was shown as the change being approved, or stayed
// on the row once the card's patch was no longer the one it was made from.
test('Needs you: a waiting card shows its screenshots above Approve, and none kept for another patch', () => {
  const w = boot();
  deliver(w, data(B));
  assert.ok(row(w).querySelector('.yes button[data-act="approve"]'), 'the approval is there');
  assert.equal(row(w).querySelector('img'), null, 'no screenshot of an older patch is shown');
  next(w, data(A));
  const img = row(w).querySelector('.yes-shots img');
  assert.ok(img, 'the screenshot is shown');
  assert.equal(img.getAttribute('src'), `shot?repo=sample&card=c1-12&file=${PNG}`, 'read from the page\'s own server, by card and content name');
  assert.equal(img.alt, 'pay/button.png');
  assert.equal(row(w).querySelector('.yes-shots figcaption').textContent, 'pay/button.png');
  assert.equal(row(w).querySelector('.yes-shots').nextElementSibling, row(w).querySelector('.yes'), 'beside the approval, just above it');
  next(w, data(B));
  assert.equal(row(w).querySelector('.yes-shots'), null, 'a screenshot of another patch goes from the kept row');
});
