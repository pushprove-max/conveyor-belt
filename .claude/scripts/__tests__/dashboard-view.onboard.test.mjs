// SPDX-License-Identifier: Apache-2.0
// The setup of a repository not yet onboarded (issue 250): a modal over the Board, in five steps, that asks every
// project rule and opens on each Board load until Finish writes `onboarded` to the control record.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { clone, boot, deliver, next, settle, key, full, act, rulesP, record, pickProject, CONTROL, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const box = (w) => w.document.getElementById('onboard');
const shown = (w) => !!box(w) && !box(w).hidden;
const line = (w) => w.document.getElementById('onboard-line');
const step = (w) => box(w).querySelector('[aria-current="step"]').textContent;
const asked = (w) => Array.from(box(w).querySelectorAll('.onboard-body .rules-row'), (r) => r.dataset.rule);
const nextB = (w) => act(box(w), 'onboard-next');
const count = (w) => box(w).querySelector('.onboard-count').textContent;
const isSet = (w, k) => box(w).querySelector(`[data-rule="${k}"]`).dataset.set;
const pressed = (w, a) => act(box(w), a).getAttribute('aria-pressed');
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };
const pick = (w, a, value) => { const s = act(box(w), a); s.value = value; s.dispatchEvent(new w.Event('change', { bubbles: true })); };
// A project whose engine knows onboarding (its record has the key), with push, visible, the whole suite, Land as
// and Test before a push known too: 16 rules. The pack lands as one pull request. part: the Rules part's own fields
// over the fixture's.
function snap(onboarded = null, over = {}, part = {}) {
  const d = full(), c = d.panels.rules.data.control;
  d.panels.rules.data.control = { ...c, rules: { ...c.rules, push: false, visible: false }, landAs: null, onboarded, ...over };
  Object.assign(d.panels.rules.data, { repoUrl: 'https://github.com/example/sample-project', packLandAs: 'pr', pushCheck: true }, part);
  return d;
}
const ALL = ['build', 'never', 'land-as', 'push', 'push-check', 'dep-guard', 'start', 'builder', 'reviewer', 'judge', 'account', 'review-account', 'cap', 'guard', 'visible'];

// What a page keeps for the next visit: localStorage, sessionStorage and cookies.
const kept = (w) => JSON.stringify([w.localStorage, w.sessionStorage].map((st) => Array.from({ length: st.length }, (_, i) => [st.key(i), st.getItem(st.key(i))]).sort())
  .concat(w.document.cookie));
const leavesNothing = (w, fn, what) => { const before = kept(w); fn(); assert.equal(kept(w), before, `${what} keeps nothing for the next visit`); };

// Bug: a new repository's rules were left at whatever the defaults were, and nobody was asked. The modal opens over
// the tab shown (Overview here), Later shuts it for this visit only, and the line at the top stays to open it again.
// Bug: Later kept the setup shut on the next Board load too. Each load is a new page, so Later and Escape must leave
// nothing in what a page keeps for its next visit.
// The title names owner/repo from the repository's address, with no issue to read it from.
test('Setup: a project with no onboarded opens the modal; Later closes it for this visit only', () => {
  const w = boot();
  const none = (d) => ({ queue: [], held: [], open: { ...d.panels.rules.data.open, issues: [], held: [] } });
  deliver(w, snap(null, {}, none(full())));
  assert.ok(shown(w), 'the modal opens over the Overview tab');
  const dlg = box(w).querySelector('[role="dialog"]');
  assert.equal(dlg.getAttribute('aria-modal'), 'true');
  assert.equal(box(w).querySelector('.onboard-title').textContent, 'Set up Conveyor for example/sample-project');
  assert.deepEqual(Array.from(box(w).querySelectorAll('.onboard-step'), (s) => s.textContent), ['1. What to build', '2. Landing', '3. Models', '4. Limits', '5. Your yes']);
  assert.equal(step(w), '1. What to build');
  assert.deepEqual(asked(w), ['build', 'never']);
  assert.equal(count(w), '0 of 15 rules set');
  assert.ok(w.document.activeElement && dlg.contains(w.document.activeElement), 'the focus is in the modal');
  assert.equal(line(w).hidden, false);
  assert.match(line(w).textContent, /Conveyor is not set up for this repository yet/);
  leavesNothing(w, () => act(box(w), 'onboard-later').click(), 'Later');
  assert.ok(!shown(w), 'Later closes it');
  next(w, snap());
  assert.ok(!shown(w), 'a new snapshot in the same visit keeps it closed');
  assert.equal(line(w).hidden, false, 'the line stays while not onboarded');
  act(line(w), 'onboard-open').click();
  assert.ok(shown(w), 'Set up opens it again');
  // Escape is Later.
  leavesNothing(w, () => key(w, w.document.activeElement, 'Escape'), 'Escape');
  assert.ok(!shown(w), 'Escape closes it');
});

// Bug guarded: a rule counted as set with nothing saved (a check that sent nothing, a refusal), a preselected choice
// sent nothing, a value in force that is not the default showed as preselected, and a choice made by keyboard left
// the focus outside the modal. Each choice is the Rules tab's command (P0_OFF, which the Rules tab's own case below
// checks the tab sends).
const stepSnap = () => snap(null, { rules: { ...CONTROL.rules, push: true, visible: false } });
const P0_OFF = [{ action: 'rules', args: ['P0=off'], repo: 'sample' }];
test('Setup: a rule is set only once saved; a preselected default sends it; each choice sends the Rules tab\'s command', async () => {
  const w = boot();
  deliver(w, stepSnap());
  // Bug: clicking the selected P0 turned it off, though a click on the selected choice keeps the default.
  assert.deepEqual(await sent(w, () => act(box(w), 'rule-P0').click()), [{ action: 'rules', args: ['P0=on', 'P1=on', 'P2=on', 'P3=on', 'followups=on'], repo: 'sample' }],
    'the selected P0 keeps the Build default');
  assert.equal(count(w), '1 of 15 rules set');
  assert.equal(pressed(w, 'rule-P0'), 'true');
  assert.deepEqual(await sent(w, () => act(box(w), 'rule-P0').click()), P0_OFF, 'once set, P0 off is the command the Rules tab sends');
  // Add with an empty field sends nothing: Never build is not set.
  assert.deepEqual(await sent(w, () => act(box(w), 'area-off').click()), []);
  assert.equal(isSet(w, 'never'), 'false', 'a check that sent nothing does not set the rule');
  // A change the host refuses does not set it either.
  w.reply = { ok: false, status: 409, text: () => Promise.resolve('refused') };
  const chip = act(box(w), 'onboard-default-never');
  assert.equal(chip.textContent, 'default: none');
  assert.deepEqual(await sent(w, () => chip.click()), [{ action: 'rules', args: ['area:infra=on'], repo: 'sample' }]);
  assert.equal(isSet(w, 'never'), 'false', 'a refused change does not set the rule');
  w.reply = null;
  await sent(w, () => act(box(w), 'onboard-default-never').click());
  assert.equal(nextB(w).disabled, false);
  nextB(w).click();
  assert.equal(step(w), '2. Landing');
  assert.deepEqual(asked(w), ['land-as', 'push', 'push-check', 'dep-guard', 'start']);
  // Bug: Land as and Test before a push, rules added after the setup was first built, went unasked. Their default is
  // the pack's value (here one pull request), and the preselected choice sends it.
  assert.equal(act(box(w), 'onboard-default-land-as').textContent, 'default: Pull request');
  assert.equal(pressed(w, 'land-as-pr'), 'true');
  assert.deepEqual(await sent(w, () => act(box(w), 'land-as-pr').click()), [{ action: 'land-as', args: ['pr'], repo: 'sample' }]);
  assert.equal(isSet(w, 'land-as'), 'true');
  assert.deepEqual(await sent(w, () => act(box(w), 'push-check-off').click()), [{ action: 'push-check', args: ['off'], repo: 'sample' }]);
  // Push is on in the record, but the default, Off, is shown selected until the rule is set.
  assert.equal(pressed(w, 'push-off'), 'true');
  assert.equal(pressed(w, 'push-on'), 'false');
  // A preselected choice sends its command and sets the rule.
  assert.equal(pressed(w, 'start-queue'), 'true');
  assert.deepEqual(await sent(w, () => act(box(w), 'start-queue').click()), [{ action: 'start', args: ['queue'], repo: 'sample' }]);
  assert.equal(isSet(w, 'start'), 'true');
  // By keyboard: the focus stays in the modal while the change is out, and comes back to the control after it.
  const dlg = box(w).querySelector('[role="dialog"]');
  act(box(w), 'push-on').focus();
  act(box(w), 'push-on').click();
  assert.ok(dlg.contains(w.document.activeElement), 'the focus is in the modal while the change is out');
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'rules', args: ['push=on'], repo: 'sample' }]);
  assert.equal(w.document.activeElement.dataset.act, 'push-on', 'the focus comes back to the control');
  key(w, w.document.activeElement, 'Escape');
  assert.ok(!shown(w), 'Escape still reaches the modal');
  act(line(w), 'onboard-open').click();
  assert.equal(act(box(w), 'onboard-default-dep-guard').textContent, 'default: On');
  assert.deepEqual(await sent(w, () => act(box(w), 'onboard-default-dep-guard').click()), [{ action: 'dep-guard', args: ['on'], repo: 'sample' }]);
  assert.equal(count(w), '7 of 15 rules set');
});

// Bug (issue 402): Next stayed disabled until every rule of the step was set, so a user who took the defaults of Build
// and Never build without clicking them could not go on. Next is on, sends the default of each rule not set yet
// (both here, so a Next that set only the first would fail), as its "default:" button does, counts them as set and
// shows the next step.
test('Setup: Next with Build and Never build unset writes both defaults and shows step 2', async () => {
  const w = boot();
  deliver(w, stepSnap());
  assert.equal(isSet(w, 'build'), 'false');
  assert.equal(isSet(w, 'never'), 'false');
  assert.equal(nextB(w).disabled, false, 'Next is on with Build and Never build unset');
  assert.deepEqual(await sent(w, () => nextB(w).click()), [{ action: 'rules', args: ['P0=on', 'P1=on', 'P2=on', 'P3=on', 'followups=on'], repo: 'sample' },
    { action: 'rules', args: ['area:infra=on'], repo: 'sample' }],
    'the defaults of both, as their default: buttons send them');
  assert.equal(step(w), '2. Landing');
  assert.equal(count(w), '2 of 15 rules set');
});

// Bug (issue 402): Finish stayed disabled with a rule of the last step unset. It writes that rule's default, then
// onboarded, and the dialog closes.
test('Setup: Finish with a rule unset writes its default and closes the dialog', async () => {
  const w = boot();
  deliver(w, snap({ at: '2026-11-01T00:00:00Z', rules: ALL.filter((k) => k !== 'visible') }));
  assert.equal(nextB(w).textContent, 'Finish');
  assert.equal(nextB(w).disabled, false, 'Finish is on with Visible changes unset');
  const done = record({ rules: { ...CONTROL.rules, push: false, visible: false }, onboarded: { at: '2026-11-09T17:00:00.000Z', rules: ALL } });
  // The host's answer to onboarded is the record that says so; the default before it is answered as sent.
  Object.defineProperty(w, 'reply', { configurable: true, get: () => (w.posts.at(-1).body.action === 'onboarded' ? done : null) });
  assert.deepEqual(await sent(w, () => nextB(w).click()), [{ action: 'rules', args: ['visible=off'], repo: 'sample' },
    { action: 'onboarded', args: ALL.filter((k) => k !== 'visible').concat(['visible']), repo: 'sample' }]);
  await settle();
  assert.ok(!shown(w), 'the dialog closes');
});

// Bug guarded: the setup's P0 off differed from the Rules tab's. The case above compares the setup's to P0_OFF;
// this one proves P0_OFF is what the Rules tab sends on the same snapshot, the setup shut with Later.
test('Setup: the Rules tab sends P0_OFF for P0 on the setup\'s snapshot', async () => {
  const tab = boot({ tab: 'rules' });
  deliver(tab, stepSnap());
  act(box(tab), 'onboard-later').click();
  assert.deepEqual(await sent(tab, () => act(rulesP(tab), 'rule-P0').click()), P0_OFF);
});

// Bug guarded: the setup reopened for ever, or not when the engine added a rule; a model picked stayed a draft until
// Save; the Judge's default left its always-accepted kinds in force. Finish writes onboarded with every rule's key;
// the modal and the line go (the case after it proves a later load does not open it).
test('Setup: Finish writes onboarded and the modal stops opening', async () => {
  const w = boot();
  deliver(w, snap(null, { guard: 98, judgeAlways: ['security'] }, { cap: null }));
  for (let i = 0; i < 5; i += 1) {
    for (const k of asked(w)) {
      if (k === 'judge-always') continue;  // part of the Judge's rule, set with it (the case after this one)
      if (k === 'builder') {
        // A model picked is saved at once, with no Save.
        pick(w, 'builder-cli', 'codex');
        await settle();
        assert.deepEqual(w.posts.splice(0), [], 'a CLI with no model picked sends nothing');
        assert.equal(isSet(w, 'builder'), 'false');
        assert.deepEqual(await sent(w, () => pick(w, 'builder-model', 'gpt-6-astra')), [{ action: 'model', args: ['codex', 'gpt-6-astra'], repo: 'sample' }]);
        assert.equal(isSet(w, 'builder'), 'true');
        continue;
      }
      if (k === 'reviewer') {
        // Bug: Codex, then Default before a model was picked, came back to the role in force: no command, not set.
        pick(w, 'reviewer-cli', 'codex');
        await settle();
        assert.deepEqual(await sent(w, () => pick(w, 'reviewer-cli', '')), [{ action: 'reviewer', args: ['default'], repo: 'sample' }]);
        assert.equal(isSet(w, 'reviewer'), 'true');
        continue;
      }
      if (k === 'cap') {
        // Bug: with no cap in the snapshot, both steps were off ('–') until the default was saved first.
        const up = act(box(w), 'cards at once-up');
        assert.equal(up.previousSibling.textContent, '6', 'the default cap, control-defaults.json\'s');
        assert.equal(act(box(w), 'onboard-default-cap').textContent, 'default: 6');
        assert.deepEqual(await sent(w, () => up.click()), [{ action: 'cap', args: ['7'], repo: 'sample' }]);
        continue;
      }
      const posts = await sent(w, () => act(box(w), `onboard-default-${k}`).click());
      if (k === 'judge') {
        assert.deepEqual(posts.map((p) => [p.action, p.args]), [['judge', ['on']], ['judge', ['default']], ['judge', ['always']]],
          'the Judge default is on, on its default model, accepting no kind always');
      }
    }
    if (i < 4) { assert.equal(nextB(w).textContent, 'Next'); nextB(w).click(); }
  }
  assert.equal(step(w), '5. Your yes');
  assert.equal(count(w), '15 of 15 rules set');
  assert.equal(nextB(w).textContent, 'Finish');
  const on = { at: '2026-11-09T17:00:00.000Z', rules: ALL };
  w.reply = record({ rules: { ...CONTROL.rules, push: false, visible: false }, onboarded: on });
  assert.deepEqual(await sent(w, () => nextB(w).click()), [{ action: 'onboarded', args: ALL, repo: 'sample' }]);
  await settle();
  assert.ok(!shown(w), 'the modal closes');
  assert.equal(line(w).hidden, true, 'the line goes');
});

// Bug guarded: the Models step drew the Judge without the kinds it always accepts, once their row was apart from the
// Judge's on the Rules tab, so the setup could not set them. Their row comes with the Judge, not as a rule to confirm.
// Bug guarded: Add set only the Always accept row, so Next still sent the Judge's defaults, `judge always` with no
// kind among them, and cleared the kinds just added. Add sets the Judge's rule.
test('Setup: the Judge step shows Always accept; Add sends the kinds and sets the Judge, so Next keeps them', async () => {
  const w = boot();
  deliver(w, snap({ at: '2026-11-01T00:00:00Z', rules: ALL.filter((k) => k !== 'judge') }));
  assert.deepEqual(asked(w), ['judge', 'judge-always']);
  assert.equal(count(w), '0 of 1 rules set', 'Always accept is not a rule of its own to confirm');
  const kind = act(box(w), 'judge-kind');
  kind.value = 'security';
  kind.dispatchEvent(new w.Event('input'));
  w.reply = record({ judgeAlways: ['security'], onboarded: { at: '2026-11-01T00:00:00Z', rules: ALL.filter((k) => k !== 'judge') } });
  assert.deepEqual(await sent(w, () => act(box(w), 'judge-kind-add').click()), [{ action: 'judge', args: ['always', 'security'], repo: 'sample' }]);
  assert.equal(count(w), '1 of 1 rules set', 'Add set the Judge');
  assert.deepEqual(await sent(w, () => nextB(w).click()), [{ action: 'onboarded', args: ALL.filter((k) => k !== 'judge').concat('judge'), repo: 'sample' }],
    'Finish sends no Judge default over the kinds');
});

// Bug guarded: the setup reopened on every load after Finish.
test('Setup: an onboarded project does not open the modal on a Board load', () => {
  const w = boot();
  deliver(w, snap({ at: '2026-11-09T17:00:00.000Z', rules: ALL }));
  assert.ok(!shown(w), 'an onboarded project does not open it');
  assert.equal(line(w).hidden, true);
});

// Bug guarded: a rule the engine added later went unasked, or every rule was asked again. A record whose
// onboarded.rules lacks one opens at that rule's step alone.
test('Setup: a record whose onboarded.rules lacks one rule opens with only that rule\'s step', async () => {
  const w = boot();
  deliver(w, snap({ at: '2026-11-01T00:00:00Z', rules: ALL.filter((k) => k !== 'visible') }));
  assert.ok(shown(w));
  assert.deepEqual(Array.from(box(w).querySelectorAll('.onboard-step'), (s) => s.textContent), ['1. Your yes']);
  assert.deepEqual(asked(w), ['visible']);
  assert.equal(count(w), '0 of 1 rules set');
  assert.equal(nextB(w).textContent, 'Finish');
  assert.deepEqual(await sent(w, () => act(box(w), 'visible-on').click()), [{ action: 'rules', args: ['visible=on'], repo: 'sample' }]);
  assert.deepEqual(await sent(w, () => nextB(w).click()), [{ action: 'onboarded', args: ALL.filter((k) => k !== 'visible').concat(['visible']), repo: 'sample' }],
    'the rules confirmed before are kept');
});

// Bug guarded: a project on an engine with no onboarding was asked to set up, and its Finish had nowhere to go.
test('Setup: a record with no onboarded key is never asked', () => {
  const w = boot();
  deliver(w, full());
  assert.ok(!shown(w) && (!line(w) || line(w).hidden), 'a record with no onboarded key (an older engine) is never asked');
});

// Bug guarded: after another project was picked under Show on Overview, with no new snapshot, Set up still sent to
// the project picked before.
test('Setup: a project picked under Show is the one Set up sends to', async () => {
  const w = boot();
  const d = snap();
  const other = { ...clone(d.panels.rules.data), repo: 'widgetshop', repoUrl: 'https://github.com/example/WidgetShop' };
  Object.assign(d.panels.rules.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: other } });
  d.panels.machine.data.repos = ['sample', 'widgetshop'];
  deliver(w, d);
  act(box(w), 'onboard-later').click();
  pickProject(w, 'widgetshop');
  act(line(w), 'onboard-open').click();
  assert.ok(shown(w));
  assert.equal(box(w).querySelector('.onboard-title').textContent, 'Set up Conveyor for example/WidgetShop');
  assert.deepEqual(await sent(w, () => act(box(w), 'rule-P0').click()), [{ action: 'rules', args: ['P0=on', 'P1=on', 'P2=on', 'P3=on', 'followups=on'], repo: 'widgetshop' }]);
});

// Bug guarded (issue 1430): Show at All projects clears ?project= and keeps ?repo=, so on a reload the setup of the
// project left in ?repo= opened over the Rules tab's project choice, though no project is in view. Also: a switch to
// the Rules tab (key 4) from a tab where that setup was open drew no overlay, so the box stayed over the choice.
test('Setup: with every project shown, the setup of the project left in ?repo= does not open over the project choice', () => {
  const w = boot({ query: '?tab=overview&repo=widgetshop' });
  const d = snap({ at: '2026-11-01T00:00:00Z', rules: ALL });
  const other = { ...clone(d.panels.rules.data), repo: 'widgetshop', repoUrl: 'https://github.com/example/WidgetShop' };
  other.control = { ...other.control, onboarded: null };
  Object.assign(d.panels.rules.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: other } });
  d.panels.machine.data.repos = ['sample', 'widgetshop'];
  deliver(w, d);
  assert.ok(shown(w), 'on Overview, which shows no project choice, widgetshop\'s setup opens');
  key(w, act(box(w), 'onboard-next') || w.document.activeElement, '4');
  assert.deepEqual(Array.from(rulesP(w).querySelectorAll('[data-act="pick-project"]'), (b) => b.dataset.project), ['sample', 'widgetshop'], 'the Rules tab shows the project choice');
  assert.ok(!shown(w), 'no setup opens over the choice');
  pickProject(w, 'widgetshop');
  assert.ok(shown(w), 'picked, widgetshop\'s setup opens');
});

// Bug guarded: a switch to an onboarded project left the box of the one before open, its controls sending to the
// project now shown.
test('Setup: a switch to an onboarded project shuts the box of the one before', async () => {
  const w = boot();
  const d = snap();
  const other = { ...clone(d.panels.rules.data), repo: 'widgetshop', repoUrl: 'https://github.com/example/WidgetShop' };
  other.control = { ...other.control, onboarded: { at: '2026-11-01T00:00:00Z', rules: ALL } };
  Object.assign(d.panels.rules.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: other } });
  d.panels.machine.data.repos = ['sample', 'widgetshop'];
  deliver(w, d);
  assert.ok(shown(w), 'the box opens for sample');
  pickProject(w, 'widgetshop');
  assert.ok(!shown(w), 'the box of sample is shut once widgetshop shows');
  assert.equal(line(w).hidden, true);
});
