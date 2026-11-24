// SPDX-License-Identifier: Apache-2.0
// The Board's per-card settings (#387): each card and queued issue shows its builder, reviewer and judge, marks those
// of its own, changes them (POST control card), and Pick for me asks the project's judge and changes nothing until
// Apply. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { css, boot, deliver, settle, full, bcard, act, cases, clone, pickProject } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

const PICK = { issue: 22, builder: { model: 'claude-fable-5-2', effort: 'high', why: 'a wide change' }, reviewer: { model: 'gpt-6-astra', effort: 'low', why: 'a small diff' },
  judge: { model: 'claude-sonnet-5-5', effort: 'medium', why: 'the cheapest that reads it well' }, model: 'claude-opus-5-5' };
const answer = (text) => ({ ok: true, status: 200, text: () => Promise.resolve(text), headers: { get: () => null } });
const seatLine = (w, n) => bcard(w, n).querySelector('.board-seats-line');
// Each seat's row as its parts: the seat name, the model and effort, and who chose it.
const seatRows = (w, n) => Array.from(seatLine(w, n).querySelectorAll('.board-seat-line'), (p) => Array.from(p.children, (c) => c.textContent).join(' | '));
const pickLines = (w, n) => Array.from(bcard(w, n).querySelectorAll('.board-seat-pick'), (p) => p.textContent);
function setTo(w, sel, v) { sel.value = v; sel.dispatchEvent(new w.Event('change')); }
async function settled() { for (let i = 0; i < 6; i += 1) await settle(); }

// Bug: a card showed no builder, reviewer or judge, did not mark the one it has of its own, or its Settings did not
// send the changed seats (a model with its effort, and Project's as clear) to the host.
test('Settings shows each seat, marks the card\'s own, and Save sends one control card a changed seat', async () => {
  const w = boot({ tab: 'control' });
  const d = full();
  d.panels.board.data.control.cards = { 20: { judge: { model: 'claude-sonnet-5-5', effort: 'low' } } };
  deliver(w, d);
  assert.deepEqual(seatRows(w, 20), ["Builder | claude-opus-5-5 · high | project's", "Reviewer | gpt-6.1-sol · medium | project's", 'Judge | claude-sonnet-5-5 · low | this card']);
  assert.deepEqual(Array.from(seatLine(w, 20).querySelectorAll('.is-own'), (x) => x.dataset.seat), ['judge'], 'only the judge is the card\'s own');
  assert.ok(act(bcard(w, 63), 'seats'), 'a card on the belt has Settings too');
  assert.equal(act(bcard(w, 5), 'seats'), null, 'a card of another project (widgetshop) is not set in this one\'s record');
  act(bcard(w, 20), 'seats').click();
  const form = () => bcard(w, 20).querySelector('.board-seats-form');
  assert.equal(act(form(), 'seat-model-judge').value, 'claude-sonnet-5-5', 'the form starts from the card\'s own seats');
  assert.equal(act(form(), 'seat-model-builder').value, '', 'a seat of the project\'s starts at Project\'s');
  setTo(w, act(form(), 'seat-model-builder'), 'claude-fable-5-2');
  setTo(w, act(form(), 'seat-effort-builder'), 'max');
  setTo(w, act(form(), 'seat-model-judge'), '');
  act(form(), 'seats-save').click();
  await settled();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [
    { action: 'card', args: ['20', 'builder', 'claude-fable-5-2', 'max'], repo: 'sample' },
    { action: 'card', args: ['20', 'judge', 'clear'], repo: 'sample' }]);
});

// Bug: the engine skips a card's own seat whose model the pack no longer allows the seat (percard), but the
// Board showed that model as "this card" while the card ran on the project's.
test('a card\'s own builder whose model the pack no longer allows shows the project\'s builder', () => {
  const w = boot({ tab: 'control' });
  const d = full();
  d.panels.board.data.control.cards = { 20: { builder: { model: 'claude-haiku-5-5', effort: 'low' } } };
  deliver(w, d);
  assert.equal(seatRows(w, 20)[0], "Builder | claude-opus-5-5 · high | project's", 'claude-haiku-5-5 is not in modelSettings.builder.choices');
  assert.equal(seatLine(w, 20).querySelector('.is-own'), null, 'no seat is marked the card\'s own');
});

// Bug: Pick for me changed the card's settings on its own, showed no reason for a choice, or its Apply did not send
// the picked seats; Discard left them to be applied later.
test('Pick for me shows the judge\'s settings with a reason each, sends nothing more until Apply, and Apply sets them', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  w.reply = answer(JSON.stringify(PICK));
  act(bcard(w, 22), 'seats-pick').click();
  assert.equal(bcard(w, 22).querySelector('.board-seats-picked').textContent, 'Asking the judge…');
  await settled();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'card', args: ['22', 'pick'], repo: 'sample' }]);
  assert.deepEqual(pickLines(w, 22), ['Builder: claude-fable-5-2 at high. a wide change', 'Reviewer: gpt-6-astra at low. a small diff',
    'Judge: claude-sonnet-5-5 at medium. the cheapest that reads it well']);
  assert.match(bcard(w, 22).querySelector('.board-seats-picked').textContent, /Nothing changed yet/);
  act(bcard(w, 22), 'seats-discard').click();
  assert.deepEqual(pickLines(w, 22), [], 'Discard drops the picked settings');
  assert.deepEqual(w.posts, [], 'showing and discarding a pick sends nothing');
  act(bcard(w, 22), 'seats-pick').click();
  await settled();
  w.posts.splice(0);
  w.reply = answer('sent to main');
  act(bcard(w, 22), 'seats-apply').click();
  await settled();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['22', 'builder', 'claude-fable-5-2', 'high'], ['22', 'reviewer', 'gpt-6-astra', 'low'], ['22', 'judge', 'claude-sonnet-5-5', 'medium']]);
  assert.deepEqual(pickLines(w, 22), [], 'an applied pick leaves the card');
});

// Bug (#461): Save compared the open form with the card's settings as they stood at Save, so after Pick for me and
// Apply, the reviewer and judge the form still showed as Project's were sent as clear, undoing the Apply.
test('Save after an Apply in the open form sends only the seat changed in the form', async () => {
  const w = boot({ tab: 'control' });
  const d = full();
  deliver(w, d);
  act(bcard(w, 22), 'seats').click();
  w.reply = answer(JSON.stringify(PICK));
  act(bcard(w, 22), 'seats-pick').click();
  await settled();
  const seat = (k) => ({ model: PICK[k].model, effort: PICK[k].effort });
  w.reply = answer(JSON.stringify({ ...clone(d.panels.board.data.control), cards: { 22: { builder: seat('builder'), reviewer: seat('reviewer'), judge: seat('judge') } } }));
  act(bcard(w, 22), 'seats-apply').click();
  await settled();
  assert.equal(w.posts.splice(0).length, 4, 'the pick and the three seats of the Apply');
  assert.equal(seatLine(w, 22).querySelectorAll('.is-own').length, 3, 'the applied seats are the card\'s own');
  const form = bcard(w, 22).querySelector('.board-seats-form');
  setTo(w, act(form, 'seat-model-builder'), 'claude-opus-5-5');
  act(form, 'seats-save').click();
  await settled();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['22', 'builder', 'claude-opus-5-5']]);
});

// Bugs: a blocked card, or one waiting for a yes, had no Settings or Pick for me, so its seats could not be set before
// its Retry; and a card's own seat with no effort of its own showed the project's effort where the card's CLI does not
// take it (a Codex judge under a Claude judge at max), not the medium its session runs at (cardfit, lib/control.sh).
test('Needs you cards have Settings and Pick for me, and an own seat shows the effort its session runs at', () => {
  const w = boot({ tab: 'control' });
  const d = full();
  d.panels.board.data.modelSettings.judge.effort = 'max';
  d.panels.board.data.control.cards = { 20: { judge: { model: 'gpt-6.1-sol' } } };
  deliver(w, d);
  for (const n of [12, 13]) assert.ok(act(bcard(w, n), 'seats') && act(bcard(w, n), 'seats-pick'), `#${n} in Needs you has Settings and Pick for me`);
  assert.equal(seatRows(w, 20)[2], 'Judge | gpt-6.1-sol · medium | this card');
  assert.equal(seatRows(w, 21)[2], "Judge | claude-opus-5-5 · max | project's", 'a card on the project\'s judge shows its effort');
});

// Bug: a pick, or an open Settings, of one project stayed on screen after a switch to another project with the same
// issue number, where its Apply or Save wrote the first project's choice into the other project's record.
test('a project switch drops every pick and open Settings, one still being asked too', async () => {
  const w = boot({ tab: 'control' });
  const d = full(), b = d.panels.board.data;
  const wb = { ...clone(b), repo: 'widgetshop', queue: b.queue.map((x) => ({ ...x, repo: 'widgetshop' })) };
  Object.assign(b, { repos: ['sample', 'widgetshop'], others: { widgetshop: wb } });
  Object.assign(d.panels.rules.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: { ...clone(d.panels.rules.data), repo: 'widgetshop' } } });
  d.panels.machine.data.repos = ['sample', 'widgetshop'];
  deliver(w, d);
  pickProject(w, 'sample');
  w.reply = answer(JSON.stringify(PICK));
  act(bcard(w, 22), 'seats-pick').click();
  await settled();
  act(bcard(w, 20), 'seats').click();
  assert.equal(pickLines(w, 22).length, 3);
  pickProject(w, 'widgetshop');
  assert.deepEqual(pickLines(w, 22), [], 'the other project\'s #22 shows no pick of sample\'s');
  assert.equal(bcard(w, 20).querySelector('.board-seats-form'), null, 'nor its Settings form');
  // A pick asked in widgetshop whose answer comes after the switch back to sample is not shown on sample's #22.
  let give;
  w.reply = { ok: true, status: 200, text: () => new Promise((r) => { give = r; }), headers: { get: () => null } };
  act(bcard(w, 22), 'seats-pick').click();
  await settled();
  pickProject(w, 'sample');
  give(JSON.stringify(PICK));
  await settled();
  assert.equal(bcard(w, 22).querySelector('.board-seats-picked'), null, 'widgetshop\'s answer is not sample\'s pick');
  assert.equal(bcard(w, 20).querySelector('.board-seats-form'), null);
});

// jsdom does no layout, so widths are checked by the computed styles of app.css, loaded into the page here.
function openForm() {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  const st = w.document.createElement('style'); st.textContent = css; w.document.head.append(st);
  act(bcard(w, 20), 'seats').click();
  return { w, form: bcard(w, 20).querySelector('.board-seats-form') };
}
const chosen = (m) => m.options[m.selectedIndex].textContent;

// Bug: on a queue card the model menus and Save ran past the card's edge.
test('each model menu is held to the card\'s width with its text cut, and Save is no wider than its text', () => {
  const { w, form } = openForm();
  for (const k of ['builder', 'reviewer', 'judge']) {
    const m = act(form, `seat-model-${k}`), c = w.getComputedStyle(m);
    assert.equal(c.maxWidth, '100%');
    assert.match(c.minWidth, /^0(px)?$/);
    assert.equal(c.textOverflow, 'ellipsis');
    assert.equal(c.overflow, 'hidden');
    assert.match(m.title, /^Project's: /);
    assert.equal(m.title, chosen(m), 'the title holds the full text');
  }
  const save = w.getComputedStyle(act(form, 'seats-save'));
  assert.ok(save.width === 'auto' || save.width === '', 'Save keeps the width its text needs');
  assert.equal(save.justifySelf, 'start', 'Save is not stretched across the grid');
});

// Bug: the effort menu sat greyed out with no reason while the model was the project's.
test('the effort menu is hidden while the model is the project\'s, and shown, enabled and labelled Effort once one is chosen', () => {
  const { w, form } = openForm();
  const row = form.querySelector('[data-seat="builder"]'), eff = row.querySelector('.board-seat-effort'), same = row.querySelector('.board-seat-same');
  assert.equal(eff.hidden, true);
  assert.equal(same.hidden, false);
  assert.equal(same.textContent, 'the project\'s effort');
  const m = act(form, 'seat-model-builder');
  setTo(w, m, 'claude-fable-5-2');
  assert.equal(eff.hidden, false);
  assert.equal(same.hidden, true);
  assert.equal(act(form, 'seat-effort-builder').disabled, false);
  assert.equal(eff.querySelector('.board-label').textContent, 'Effort');
  assert.equal(m.title, chosen(m), 'the title follows the chosen model');
});

// Bug (issue 1430): the row shows the seat the Judge picked (seats.run), but the form's empty option said
// "Project's: <the project's model>", so the form read as if the card ran on the project's seat.
test('Settings on a card whose builder is the Judge\'s pick at high: the builder\'s empty option names that pick', () => {
  const w = boot({ tab: 'control' });
  const d = full();
  d.panels.board.data.queue[0].seats = { mode: 'on', run: { builder: { model: 'claude-fable-5-2', effort: 'high', by: 'judge' } } };
  deliver(w, d);
  act(bcard(w, 20), 'seats').click();
  const form = bcard(w, 20).querySelector('.board-seats-form'), m = act(form, 'seat-model-builder');
  assert.deepEqual([m.value, chosen(m)], ['', 'Judge\'s pick: claude-fable-5-2 at high']);
  assert.equal(form.querySelector('[data-seat="builder"] .board-seat-same').textContent, 'the effort it names');
  assert.match(chosen(act(form, 'seat-model-reviewer')), /^Project's: /, 'a seat the rule did not set is the project\'s');
});

// Bug: a card's saved model that left the allowed list made Settings throw (no selected option for the title).
test('Settings opens on a card whose saved model is no longer allowed, showing the project\'s', () => {
  const w = boot({ tab: 'control' });
  const d = full();
  d.panels.board.data.control.cards = { 20: { builder: { model: 'claude-gone-9', effort: 'high' } } };
  deliver(w, d);
  act(bcard(w, 20), 'seats').click();
  const m = act(bcard(w, 20).querySelector('.board-seats-form'), 'seat-model-builder');
  assert.equal(m.value, '');
  assert.match(m.title, /^Project's: /);
});

// Bug: Save on that form, with no edit, sent "builder clear" and deleted the saved setting.
test('Save with no edit does not clear a saved model that is no longer allowed', async () => {
  const w = boot({ tab: 'control' });
  const d = full();
  d.panels.board.data.control.cards = { 20: { builder: { model: 'claude-gone-9', effort: 'high' } } };
  deliver(w, d);
  act(bcard(w, 20), 'seats').click();
  act(bcard(w, 20).querySelector('.board-seats-form'), 'seats-save').click();
  await settled();
  assert.deepEqual(w.posts.splice(0), [], 'nothing is sent');
});

// Bug: on that form, choosing another model and then Project's, Save said "Nothing changed." and kept the saved model.
test('an explicit choice of Project\'s clears a saved model that is no longer allowed', async () => {
  const w = boot({ tab: 'control' });
  const d = full();
  d.panels.board.data.control.cards = { 20: { builder: { model: 'claude-gone-9', effort: 'high' } } };
  deliver(w, d);
  act(bcard(w, 20), 'seats').click();
  const form = () => bcard(w, 20).querySelector('.board-seats-form');
  setTo(w, act(form(), 'seat-model-builder'), 'claude-fable-5-2');
  setTo(w, act(form(), 'seat-model-builder'), '');
  act(form(), 'seats-save').click();
  await settled();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'card', args: ['20', 'builder', 'clear'], repo: 'sample' }]);
});

// Bug: a queue card showed the raw "next: 1".
test('queue cards read Next in the queue, then #2 in the queue', () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  const line = (n) => Array.from(bcard(w, n).querySelectorAll('.board-from'), (x) => x.textContent).find((x) => /in the queue/.test(x));
  assert.equal(line(20), 'Next in the queue');
  assert.equal(line(21), '#2 in the queue');
});
