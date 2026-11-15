// SPDX-License-Identifier: Apache-2.0
// The Board audit's UX22 and UX24: Needs you cannot be hidden and Customize says its layout is this browser's only;
// and what was said only on hover (a step pill, a fix's reason, a line cut to fit, a cost figure's mark, the loop's
// controls) is open to a phone, which shows no hover text.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, panel, deliver, next, tick, key, full, trackOf, tile, tabBtn, STORE, $, css, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const tipEl = (w) => w.document.getElementById('tip');
const shown = (w) => (tipEl(w) && !tipEl(w).hidden ? tipEl(w).textContent : null);

// Bug (UX22): Needs you had the same hide control (an ×) as every other panel, and its box in Customize, so a browser
// could hide what stops the loop for the owner, and a layout kept with it hidden kept it hidden.
test('Needs you cannot be hidden: no hide control, a fixed ticked box in Customize, and a kept layout that hid it shows it', () => {
  const w = boot();
  deliver(w, full());
  assert.equal(panel(w, 'needs').querySelector('.tool.hide'), null, 'Needs you has no hide control');
  w.document.getElementById('customize-open').click();
  assert.equal(w.document.getElementById('show-queue').disabled, false, 'every other panel can be hidden from Customize (issue 408: no panel head has a hide control)');
  const box = w.document.getElementById('show-needs');
  assert.ok(box.checked && box.disabled, 'its box in Customize is ticked and cannot be changed');
  assert.equal(box.closest('label').textContent, 'Needs you (always shown)');
  box.click();
  assert.equal(panel(w, 'needs').hidden, false);
  assert.equal(w.localStorage.getItem(STORE), null, 'nothing was kept');

  const kept = boot({ store: { [STORE]: JSON.stringify({ tabs: { overview: { hidden: ['needs', 'queue'] } } }) } });
  assert.equal(panel(kept, 'needs').hidden, false, 'a layout kept with Needs you hidden shows it');
  assert.equal(panel(kept, 'queue').hidden, true, 'and still hides what it may');
  assert.equal($(kept, '#customize-open .label').textContent, 'Customize (1 hidden)');
});

// Bug (UX22): the layout is kept per browser, so the Mac and the phone differ; Restore did not say it puts back only
// this browser's layout.
test('Restore default layout says beside it that it is this browser only', () => {
  const w = boot();
  w.document.getElementById('customize-open').click();
  const restore = w.document.getElementById('restore-layout');
  assert.equal(restore.nextElementSibling.textContent, 'this browser only');
  assert.equal(restore.parentElement.className, 'sheet-restore', 'on one row with the button');
});

// Bug (UX24): a step pill's state and time (the time is not drawn at phone width), a fix's reason, the cut "now:" line
// and a cut push failure were only in hover text, which a phone never shows: "now: Bash…" read as "no…" with no way
// to open it. A tap now opens the words under the item; a second tap, a tap elsewhere or Escape closes them.
test('a step pill, a fix label, a cut "now:" line and a push failure open their full words on a tap, and close again', () => {
  const w = boot();
  const data = full(), action = `Bash timeout 600 node --test ${'.claude/scripts/__tests__/dashboard-view.layout.test.mjs '.repeat(4)}`;
  const card = data.panels.belt.data.cards[0];
  card.live = { turns: 4, lastOutputAt: new Date(w.clock - 4000).toISOString(), action };
  card.track.reason = 'exit 1 (124 is the timeout, so the push hook ran past its limit)';
  const WHY = "main moved since the card's change was made, and the change no longer applied to it";
  data.panels.landed.data.cards[0].track = trackOf('++++++', '', { at: null, since: null, records: [{ name: 'building', state: 'done', sec: 600 },
    { name: 'fix 1', state: 'done', sec: 200, reason: WHY }, { name: 'tests passed', state: 'done', sec: 60 }] });
  deliver(w, data);
  const row = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]');
  const pill = row.querySelector('.track6 .step6[data-state="now"]');
  assert.equal(shown(w), null, 'nothing is open before a tap');
  pill.click();
  assert.equal(shown(w), pill.getAttribute('aria-label'), 'a tap on a step pill opens its words');
  assert.equal(shown(w), 'Review 2 of 3: in progress');
  assert.equal(pill.getAttribute('aria-describedby'), 'tip');
  pill.click();
  assert.equal(shown(w), null, 'a second tap closes them');
  const now = row.querySelector('.track-now .live-action');
  now.click();
  assert.equal(shown(w), action, 'the cut "now:" line opens in full');
  w.document.body.click();
  assert.equal(shown(w), null, 'a tap elsewhere closes it');
  assert.equal(now.hasAttribute('aria-describedby'), false);
  row.querySelector('.track-now .failed').click();
  assert.equal(shown(w), `Push failed: ${card.track.reason}`, 'a cut push failure opens in full');
  key(w, w.document.body, 'Escape');
  assert.equal(shown(w), null, 'Escape closes it');
  const fix = Array.from(panel(w, 'landed').querySelectorAll('.timeline .tl-label')).find((l) => /^Fix 1/.test(l.textContent));
  fix.click();
  assert.equal(shown(w), WHY, 'a fix label opens its reason');
  // The line drawn again (the next action streamed in) takes the item it was opened from away: the words close.
  const d2 = JSON.parse(JSON.stringify(data));
  d2.panels.belt.data.cards[0].live.action = 'Reading belt.js';
  row.querySelector('.track-now .live-action').click();
  next(w, d2);
  tick(w, 1000);
  assert.equal(shown(w), null, 'words of an item drawn again are closed, not left showing old text');
});

// Bug (review of UX24): a step pill is kept in its place and only its words change, so a pill opened while Review was
// in progress went on saying "in progress" after Review was done; tick() closes only items taken out of the page.
test('an open step pill kept in its place shows its new words when its step changes', () => {
  const w = boot();
  const data = full();
  deliver(w, data);
  const pill = () => panel(w, 'belt').querySelector('li[data-key="sample:c3-63"] .track6 .step6:nth-child(2)');
  const before = pill();
  before.click();
  assert.equal(shown(w), 'Review 2 of 3: in progress');
  const d2 = JSON.parse(JSON.stringify(data)), t = d2.panels.belt.data.cards[0].track;
  t.steps[1].state = 'done'; t.steps[1].sec = 90; t.steps[3].state = 'now'; t.at = 3;
  next(w, d2);
  assert.equal(pill(), before, 'the same pill, kept in its place');
  assert.notEqual(pill().getAttribute('aria-label'), 'Review 2 of 3: in progress');
  assert.equal(shown(w), pill().getAttribute('aria-label'), 'its open words are its new ones');
  tick(w, 1000);
  assert.equal(shown(w), pill().getAttribute('aria-label'), 'and stay open');
});

// Bug (review of UX24): a head tile's mark is kept and hidden when its figure no longer leaves anything out; its open
// words stayed showing what was left out before.
test('an open head mark closes when its figure no longer leaves anything out, and shows new words when they change', () => {
  const w = boot({ tab: 'control' });
  const data = full();
  Object.assign(data.panels.cost.data.cards, { unpricedSteps: 2, todayLeftOut: 2 });
  deliver(w, data);
  const mark = tile(w, 'today').querySelector('.stat-mark');
  mark.click();
  assert.equal(shown(w), '2 steps have no price');
  const d2 = JSON.parse(JSON.stringify(data));
  Object.assign(d2.panels.cost.data.cards, { unpricedSteps: 3, todayLeftOut: 3 });
  next(w, d2);
  assert.equal(tile(w, 'today').querySelector('.stat-mark'), mark, 'the same mark, kept in its place');
  assert.equal(shown(w), '3 steps have no price', 'its open words are its new ones');
  const d3 = JSON.parse(JSON.stringify(data));
  Object.assign(d3.panels.cost.data.cards, { unpricedSteps: 0, todayLeftOut: 0 });
  next(w, d3);
  assert.equal(mark.hidden, true);
  assert.equal(shown(w), null, 'a mark with nothing to say closes its words');
  assert.equal(mark.hasAttribute('data-tip'), false, 'and a tap on the hidden mark has nothing to open');
});

// Bug (UX24): a cost figure that leaves out steps with no price said so only on hover over its mark; and the mark sits
// in a link, so a tap went to the Cost panel's tab and never showed the words.
test('a head tile\'s mark opens its words on a tap and does not follow the tile\'s link; the rest of the tile still does', () => {
  const w = boot({ tab: 'control' });
  const data = full();
  Object.assign(data.panels.cost.data.cards, { unpricedSteps: 2, todayLeftOut: 2 });
  deliver(w, data);
  const today = tile(w, 'today'), mark = today.querySelector('.stat-mark');
  assert.equal(mark.hidden, false);
  mark.click();
  assert.equal(shown(w), '2 steps have no price', 'the mark opens what the figure leaves out');
  assert.equal(tabBtn(w, 'control').getAttribute('aria-selected'), 'true', 'and the tab did not change');
  today.querySelector('.stat-label').click();
  assert.equal(shown(w), null);
  // Issue 408: the tile's first tap says its gap under the figure; the next opens its panel.
  assert.equal(today.querySelector('.stat-gap').textContent, '2 steps have no price');
  today.querySelector('.stat-label').click();
  assert.equal(tabBtn(w, 'overview').getAttribute('aria-selected'), 'true', 'the tile itself still opens its panel');
});

// Bug (UX24): what Pause after current and Stop now do, and what pausing the machine or a project does, was only in
// hover text. At phone width it is printed under the controls; wider, the hover text stays and nothing is printed.
test('the loop\'s controls print what they do under them at phone width only', () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  const note = panel(w, 'board-loop').querySelector('.board-bar .phone-note');
  assert.equal(note.textContent, 'Pause after current: the cards in progress finish, and Conveyor picks nothing new. Stop now: the cards in progress end and go back to the queue.');
  assert.match(panel(w, 'machine').querySelector('.project-acts .phone-note').textContent, /^sample picks no new card; its cards running finish/);
  assert.match(w.document.querySelector('#machine-head .phone-note').textContent, /^No project starts a new card; cards running finish/);
  assert.match(css, /\n\.phone-note \{ display: none; \}/, 'hidden by default');
  const phone = /@media \(max-width: 700px\) \{([\s\S]*?)\n\}/.exec(css)[1];
  assert.match(phone, /\.phone-note \{ display: block;/, 'shown at phone width');
});
