// SPDX-License-Identifier: Apache-2.0
// The dashboard page's Rules tab: the Builder, Reviewer and Judge rows (CLI, model and effort), picked from lists and
// sent by Save. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, record, rulesP, heldP, ruled, CLAUDE4, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const DRAFT_KEY = 'conveyor-board-rules-drafts';
const row = (w, k) => ruled(w).querySelector(`[data-rule="${k}"]`);
const values = (w, k, a) => Array.from(act(row(w, k), a).options, (o) => o.value);
const set = (w, k, a, v) => { const s = act(row(w, k), a); s.value = v; s.dispatchEvent(new w.Event('change')); };
const unsaved = (w, k) => ['Unsaved', 'Save', 'Cancel'].every((t) => Array.from(row(w, k).querySelectorAll('.chip, .btn'), (x) => (x.hidden ? '' : x.textContent)).includes(t));

// Bug: Claude Code lists no models (clis.claude is null), so the Builder's model was a text box while the Judge's was
// a list. A CLI that lists none is offered the pack's models for it, then Other… for a name not listed.
test('Rules: a Claude Builder picks its model from the pack\'s four Claude models plus Other…, like the Judge', () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.control = { ...d.panels.rules.data.control, judge: { cli: 'claude', model: 'claude-sonnet-5-5', effort: null } };
  Object.assign(d.panels.rules.data.modelSettings.judge, { model: 'claude-sonnet-5-5', modelFrom: 'control' });
  deliver(w, d);
  assert.equal(d.panels.rules.data.modelSettings.builder.clis.claude.models, null, 'Claude Code lists no models');
  assert.equal(act(row(w, 'builder'), 'builder-model').tagName, 'SELECT', 'the Builder\'s model is a dropdown');
  assert.deepEqual(values(w, 'builder', 'builder-model'), ['', ...CLAUDE4, '*other'], 'the pack\'s four Claude models, then Other…');
  assert.equal(act(row(w, 'builder'), 'builder-model').selectedOptions[0].textContent, 'claude-opus-5-5', 'the model in force is picked');
  assert.equal(act(row(w, 'builder'), 'builder-model').options[5].textContent, 'Other…');
  assert.equal(act(row(w, 'judge'), 'judge-model').tagName, 'SELECT', 'the Judge\'s too');
  assert.deepEqual(values(w, 'judge', 'judge-model'), ['', 'claude-opus-5-5', 'claude-sonnet-5-5', '*other']);
  assert.equal(act(row(w, 'builder'), 'builder-model-other'), null, 'no text box until Other… is picked');
  // A model set that the pack does not list shows under Other…, in its text box.
  const odd = full();
  odd.panels.rules.data.control.model = { cli: 'claude', model: 'claude-sonnet-9-0[1m]', effort: 'high' };
  odd.panels.rules.data.modelSettings.builder.model = 'claude-sonnet-9-0[1m]';
  next(w, odd);
  assert.equal(act(row(w, 'builder'), 'builder-model').value, '*other');
  assert.equal(act(row(w, 'builder'), 'builder-model-other').value, 'claude-sonnet-9-0[1m]');
  // A CLI with neither a list of its own nor the pack's keeps the text box.
  const none = boot({ tab: 'rules' });
  const n = full();
  n.panels.rules.data.modelSettings.builder.allowed = { claude: [] };
  deliver(none, n);
  assert.equal(act(row(none, 'builder'), 'builder-model').tagName, 'INPUT');
});

// Bug (#441): a CLI that lists its own models (Codex here) offered no Other…, so a model it does not list could not be
// set for any role. Each role offers it; the name typed is saved, and the model in force says it is not listed.
test('Rules: Builder, Reviewer and Judge each offer Other… for a CLI that lists its own models; a typed name is saved and shown as not listed', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  const ctl = {};
  for (const [k, action] of [['builder', 'model'], ['reviewer', 'reviewer'], ['judge', 'judge']]) {
    set(w, k, `${k}-cli`, 'codex');
    assert.deepEqual(values(w, k, `${k}-model`).slice(-2), ['gpt-6.1-terra', '*other'], `${k}: Codex's models, then Other…`);
    set(w, k, `${k}-model`, '*other');
    const typed = act(row(w, k), `${k}-model-other`);
    typed.value = 'gpt-9-unlisted'; typed.dispatchEvent(new w.Event('input'));
    ctl[action] = { cli: 'codex', model: 'gpt-9-unlisted', effort: null };
    w.reply = record({ ...ctl });
    act(row(w, k), `${k}-save`).click();
    await settle();
    assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action, args: ['codex', 'gpt-9-unlisted'], repo: 'sample' }], `${k}: the typed name is sent`);
    assert.equal(act(row(w, k), `${k}-model-other`).value, 'gpt-9-unlisted', `${k}: the saved name stays under Other…`);
    assert.match(row(w, k).textContent, /codex gpt-9-unlisted \(not listed\) · /, `${k}: in force, said to be not listed`);
  }
});

// Bug (#441 review): a reviewer saved back to Default fell back to the snapshot's reviewer, the Claude one just
// cleared, so the Claude judge was still said to be of its family though the default reviewer runs on another CLI.
test('Rules: a reviewer cleared to Default stops the Judge row saying it is of the reviewer\'s family until the snapshot names the new one', async () => {
  const w = boot({ tab: 'rules' });
  const d = full(), data = d.panels.rules.data;
  const reviewer = { cli: 'claude', model: 'claude-sonnet-5-5', effort: null }, judge = { cli: 'claude', model: 'claude-opus-5-5', effort: null };
  data.control = { ...data.control, reviewer, judge };
  Object.assign(data.modelSettings.reviewer, { model: 'claude-sonnet-5-5', agent: 'claude', modelFrom: 'control' });
  Object.assign(data.modelSettings.judge, { modelFrom: 'control' });
  deliver(w, d);
  assert.match(row(w, 'judge').textContent, /same family as the reviewer/, 'a Claude judge beside a Claude reviewer');
  set(w, 'reviewer', 'reviewer-cli', '');
  w.reply = record({ model: data.control.model, reviewer: null, judge });
  act(row(w, 'reviewer'), 'reviewer-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'reviewer', args: ['default'], repo: 'sample' }]);
  assert.doesNotMatch(row(w, 'judge').textContent, /same family/, 'the default reviewer is not the cleared Claude one');
});

// Bug (#441 review): the default judge is of another family than the reviewer's, so it moves when the reviewer does.
// With a Codex reviewer and the default Claude judge, a reviewer saved as Claude kept the snapshot's Claude judge, and
// the row said "same family" though the default judge is now a Codex one.
test('Rules: a reviewer saved onto the default judge\'s CLI does not make the Judge row say it is of the reviewer\'s family', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  assert.equal(row(w, 'judge').textContent.includes('same family'), false, 'a default Claude judge beside a Codex reviewer');
  set(w, 'reviewer', 'reviewer-cli', 'claude');
  // The pack allows the review no Claude model, so its name is typed in.
  const typed = act(row(w, 'reviewer'), 'reviewer-model');
  typed.value = 'claude-sonnet-5-5'; typed.dispatchEvent(new w.Event('input'));
  w.reply = record({ reviewer: { cli: 'claude', model: 'claude-sonnet-5-5', effort: null } });
  act(row(w, 'reviewer'), 'reviewer-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['claude', 'claude-sonnet-5-5']]);
  assert.match(row(w, 'reviewer').textContent, /claude claude-sonnet-5-5 · /, 'the Claude reviewer is in force');
  assert.doesNotMatch(row(w, 'judge').textContent, /same family/, 'the default judge now runs on another CLI than Claude');
});

// Bug (#441 review): a judge on the reviewer's CLI cleared to Default kept that CLI until the next snapshot, so the row
// still said "same family" though the default judge runs on another family than the reviewer's.
test('Rules: a judge on the reviewer\'s CLI cleared to Default stops saying it is of the reviewer\'s family', async () => {
  const w = boot({ tab: 'rules' });
  const d = full(), data = d.panels.rules.data;
  data.control = { ...data.control, judge: { cli: 'codex', model: 'gpt-6-astra', effort: null } };
  Object.assign(data.modelSettings.judge, { model: 'gpt-6-astra', agent: 'codex', modelFrom: 'control' });
  deliver(w, d);
  assert.match(row(w, 'judge').textContent, /same family as the reviewer/, 'a Codex judge beside the Codex reviewer');
  set(w, 'judge', 'judge-cli', '');
  w.reply = record({ judge: null });
  act(row(w, 'judge'), 'judge-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['default']]);
  assert.doesNotMatch(row(w, 'judge').textContent, /same family/, 'the default judge is not the cleared Codex one');
});

// Bug: each pick of a CLI, model or effort was sent at once, so a half-made choice (a model before its effort) ran the
// next card. A pick sends nothing: the row says Unsaved; Save sends the role whole, once; Cancel puts it back.
test('Rules: a Builder, Reviewer or Judge change sends nothing until Save, which sends one action with CLI, model and effort; Cancel puts back what is in force', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  // Builder: a model and an effort, both kept unsent.
  assert.equal(unsaved(w, 'builder'), false, 'nothing unsaved at first');
  set(w, 'builder', 'builder-model', 'claude-sonnet-5-5');
  set(w, 'builder', 'builder-effort', 'medium');
  // Reviewer: a CLI, then its model. Judge: a CLI, its model and an effort.
  set(w, 'reviewer', 'reviewer-cli', 'codex');
  set(w, 'reviewer', 'reviewer-model', 'gpt-6-astra');
  set(w, 'judge', 'judge-cli', 'claude');
  set(w, 'judge', 'judge-model', 'claude-sonnet-5-5');
  set(w, 'judge', 'judge-effort', 'low');
  await settle();
  assert.deepEqual(w.posts, [], 'no pick sends anything');
  for (const k of ['builder', 'reviewer', 'judge']) assert.equal(unsaved(w, k), true, `${k}: Unsaved, with Save and Cancel`);
  assert.match(row(w, 'builder').textContent, /claude claude-opus-5-5 · high/, 'what is in force is still said');
  // Save: the role whole, once, and the result said.
  w.reply = record({ model: { cli: 'claude', model: 'claude-sonnet-5-5', effort: 'medium' } });
  act(row(w, 'builder'), 'builder-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'model', args: ['claude', 'claude-sonnet-5-5', 'medium'], repo: 'sample' } }]);
  assert.equal(rulesP(w).querySelector('.rules-note').textContent, 'Saved: builder now claude-sonnet-5-5 · medium');
  assert.equal(unsaved(w, 'builder'), false, 'saved: no longer unsaved');
  assert.match(row(w, 'builder').textContent, /claude claude-sonnet-5-5 · medium/, 'the host\'s record is in force at once');
  w.reply = record({ model: { cli: 'claude', model: 'claude-sonnet-5-5', effort: 'medium' }, judge: { cli: 'claude', model: 'claude-sonnet-5-5', effort: 'low' } });
  act(row(w, 'judge'), 'judge-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'judge', args: ['claude', 'claude-sonnet-5-5', 'low'], repo: 'sample' }]);
  assert.equal(rulesP(w).querySelector('.rules-note').textContent, 'Saved: judge now claude-sonnet-5-5 · low');
  // Cancel: the reviewer goes back to the default in force, and sends nothing.
  act(row(w, 'reviewer'), 'reviewer-cancel').click();
  await settle();
  assert.deepEqual(w.posts, []);
  assert.deepEqual([act(row(w, 'reviewer'), 'reviewer-cli').value, act(row(w, 'reviewer'), 'reviewer-model').value], ['', ''], 'what is in force');
  assert.equal(unsaved(w, 'reviewer'), false);
  // A pick that comes back to what is in force is nothing to save.
  set(w, 'builder', 'builder-effort', 'high');
  assert.equal(unsaved(w, 'builder'), true);
  set(w, 'builder', 'builder-effort', 'medium');
  assert.equal(unsaved(w, 'builder'), false);
  // Default clears the role, by Save too.
  set(w, 'builder', 'builder-cli', '');
  await settle();
  assert.deepEqual(w.posts, []);
  w.reply = record({ model: null });
  act(row(w, 'builder'), 'builder-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['default']]);
  // A model the host would refuse is not sent.
  set(w, 'builder', 'builder-cli', 'claude');
  act(row(w, 'builder'), 'builder-save').click();
  await settle();
  assert.deepEqual(w.posts, [], 'no model picked: nothing sent');
  assert.match(rulesP(w).querySelector('.rules-note').textContent, /Pick the Builder's model first/);
});

// Bug: a Save said "Saved" in the panel last typed in when the host answered, so a search typed in Held issues while
// the Save was out took the line, and the Rules panel's own line was emptied.
test('Rules: a role\'s Saved line shows in the Rules panel even when Held issues is typed in before the host answers', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  set(w, 'builder', 'builder-model', 'claude-sonnet-5-5');
  let answer;
  const late = new Promise((r) => { answer = r; });
  const rec = record({ model: { cli: 'claude', model: 'claude-sonnet-5-5', effort: 'high' } });
  w.reply = { ...rec, text: () => late.then(() => rec.text()) };
  act(row(w, 'builder'), 'builder-save').click();
  await settle();
  const search = act(heldP(w), 'held-search');
  search.value = '35';
  search.dispatchEvent(new w.Event('input', { bubbles: true }));
  answer();
  await settle();
  assert.equal(rulesP(w).querySelector('.rules-note').textContent, 'Saved: builder now claude-sonnet-5-5 · high');
  assert.equal(heldP(w).closest('.panel').querySelector('.rules-note').textContent, '', 'Held issues does not say Saved');
});

// Bug (owner): a choice made and not saved must be neither lost nor sent by a redraw, a tab change or a reload.
test('Rules: a refresh during an edit keeps the edit, still marked unsaved, and sends nothing; a refused Save keeps it too', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  set(w, 'builder', 'builder-model', 'claude-haiku-5-5');
  set(w, 'reviewer', 'reviewer-cli', 'codex');
  // A snapshot redraws the tab.
  const d = full();
  d.panels.rules.data.queue.shift();
  next(w, d);
  assert.equal(act(row(w, 'builder'), 'builder-model').value, 'claude-haiku-5-5');
  assert.equal(unsaved(w, 'builder'), true);
  // A reload: a new page with what this one kept in the browser.
  const again = boot({ tab: 'rules', store: { [DRAFT_KEY]: w.localStorage.getItem(DRAFT_KEY) } });
  deliver(again, full());
  assert.equal(act(row(again, 'builder'), 'builder-model').value, 'claude-haiku-5-5', 'the edit is kept');
  assert.equal(act(row(again, 'reviewer'), 'reviewer-cli').value, 'codex');
  assert.equal(unsaved(again, 'builder'), true, 'still marked unsaved');
  assert.equal(unsaved(again, 'reviewer'), true);
  await settle();
  assert.deepEqual([w.posts, again.posts], [[], []], 'nothing is sent');
  // Refused: the pick stays, unsaved, with the host's refusal beside it.
  again.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: the record is locked') };
  act(row(again, 'builder'), 'builder-save').click();
  await settle();
  assert.equal(again.posts.splice(0).length, 1);
  assert.equal(row(again, 'builder').querySelector('.rules-refused').textContent, 'Not saved: conveyor: the record is locked');
  assert.equal(act(row(again, 'builder'), 'builder-model').value, 'claude-haiku-5-5');
  assert.equal(unsaved(again, 'builder'), true);
  assert.match(row(again, 'builder').textContent, /claude claude-opus-5-5 · high/, 'the setting in force is unchanged');
  // Cancel clears what was kept: a later reload shows what is in force.
  act(row(again, 'builder'), 'builder-cancel').click();
  act(row(again, 'reviewer'), 'reviewer-cancel').click();
  const third = boot({ tab: 'rules', store: { [DRAFT_KEY]: again.localStorage.getItem(DRAFT_KEY) } });
  deliver(third, full());
  assert.equal(act(row(third, 'builder'), 'builder-model').value, 'claude-opus-5-5');
  assert.equal(unsaved(third, 'builder'), false);
});
