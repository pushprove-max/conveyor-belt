// SPDX-License-Identifier: Apache-2.0
// The Rules panel as indexed settings (#861): a search box and six groups on the left, the group's rules on the right,
// each rule's choices one segmented control, and the pinned issues one row a pin with its title, dragged or moved by
// its menu. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { boot, deliver, next, clone, settle, full, act, rulesP, record, css, cases, STORE } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };
const shown = (el) => !el.closest('[hidden]');
const shownRules = (w) => Array.from(rulesP(w).querySelectorAll('.rules-row'), (r) => r).filter(shown).map((r) => r.dataset.rule);
const shownSets = (w) => Array.from(rulesP(w).querySelectorAll('.rules-set')).filter(shown).map((s) => s.dataset.set);
const typeFind = (w, v) => { const f = act(rulesP(w), 'rules-find'); f.value = v; f.dispatchEvent(new w.Event('input')); };

// Bugs: the index did not list the six groups, or a group showed another group's rules, or the search missed a rule
// by its name or showed the groups with no match, so a rule could not be found or the pane stayed a long flat list.
test('Rules: the index lists six groups; Picking shows only its six rules; "push" shows only the matching rules of Landing and push', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  assert.deepEqual(Array.from(rulesP(w).querySelectorAll('.rules-index button'), (b) => [b.textContent, b.getAttribute('aria-pressed')]),
    [['Models', 'true'], ['Capacity', 'false'], ['Picking', 'false'], ['Landing and push', 'false'], ['Done without asking', 'false'], ['Issue order', 'false']]);
  assert.deepEqual(shownSets(w), ['models'], 'no search text: the group picked alone');
  act(rulesP(w), 'rules-set-picking').click();
  assert.equal(act(rulesP(w), 'rules-set-picking').getAttribute('aria-pressed'), 'true');
  assert.deepEqual(shownRules(w), ['build', 'never', 'start', 'dep-guard', 'split', 'pick']);
  typeFind(w, 'push');
  assert.deepEqual(shownSets(w), ['landing'], 'a group with no match hides');
  assert.ok(['push', 'push-check'].every((k) => shownRules(w).includes(k)), shownRules(w).join());
  assert.deepEqual(Array.from(rulesP(w).querySelectorAll('[data-rule="push"] .board-label, [data-rule="push-check"] .board-label'), (x) => x.textContent),
    ['Push on landing', 'Test before a push']);
  assert.equal(rulesP(w).querySelector('.rules-none').hidden, true);
  typeFind(w, 'Weekly');
  assert.deepEqual(shownRules(w), ['guard'], 'by its label, in any case');
  typeFind(w, 'nothing-like-this');
  assert.deepEqual(shownSets(w), []);
  assert.equal(rulesP(w).querySelector('.rules-none').textContent, 'No rule matches "nothing-like-this".');
  assert.equal(shown(rulesP(w).querySelector('.rules-none')), true);
});

// Bug: the redraw dropped a rule, moved one out of every group, showed another value than the record's, or changed
// the call a rule sends. Each rule the old flat pane had: its group, the value it shows and the call it sends.
test('Rules: every rule of the old pane is in a group, with the same value and the same save call', async () => {
  const w = boot({ tab: 'rules' });
  const d = full(), c = d.panels.rules.data.control;
  Object.assign(c, { order: [21], landAs: null, prMerge: null, account: null, reviewAccount: null });
  Object.assign(c.rules, { push: false, visible: false, split: 'shadow', pick: 'off' });
  Object.assign(d.panels.rules.data, { accounts: ['first'], pushCheck: true, standing: [], cores: { reserved: [], slots: 16, unavailable: null } });
  w.reply = record({ order: [21], landAs: null, prMerge: null, rules: c.rules });
  deliver(w, d);
  const row = (k) => rulesP(w).querySelector(`.rules-set [data-rule="${k}"]`);
  const setOf = (k) => row(k) && row(k).closest('.rules-set').dataset.set;
  const pressed = (k) => Array.from(row(k).querySelectorAll('[aria-pressed="true"]'), (b) => b.dataset.act);
  const pick = (a, v) => () => { const s = act(rulesP(w), a); s.value = v; s.dispatchEvent(new w.Event(s.tagName === 'INPUT' ? 'input' : 'change')); };
  const click = (a) => () => act(rulesP(w), a).click();
  const check = async (k, set, value, shows, go, body) => assert.deepEqual([setOf(k), value, await sent(w, go)], [set, shows, body.map((b) => ({ ...b, repo: 'sample' }))], k);
  await check('builder', 'models', act(rulesP(w), 'builder-model').value, 'claude-opus-5-5',
    () => { pick('builder-effort', 'low')(); click('builder-save')(); }, [{ action: 'model', args: ['claude', 'claude-opus-5-5', 'low'] }]);
  await check('reviewer', 'models', act(rulesP(w), 'reviewer-cli').value, '',
    () => { pick('reviewer-cli', 'codex')(); pick('reviewer-model', 'gpt-6-astra')(); click('reviewer-save')(); }, [{ action: 'reviewer', args: ['codex', 'gpt-6-astra'] }]);
  await check('judge', 'models', pressed('judge'), ['judge-off'], click('judge-on'), [{ action: 'judge', args: ['on'] }]);
  await check('judge-always', 'models', row('judge-always').querySelector('[data-list="judge-kinds"]').textContent, 'always accepts no kind',
    () => { pick('judge-kind', 'security')(); click('judge-kind-add')(); }, [{ action: 'judge', args: ['always', 'security'] }]);
  await check('account', 'models', act(rulesP(w), 'account').value, '', pick('account', 'first'), [{ action: 'account', args: ['first'] }]);
  await check('review-account', 'models', act(rulesP(w), 'review-account').value, '', pick('review-account', 'first'), [{ action: 'review-account', args: ['first'] }]);
  await check('cap', 'capacity', row('cap').querySelector('.board-value').textContent, '3', click('cards at once-up'), [{ action: 'cap', args: ['4'] }]);
  await check('guard', 'capacity', pressed('guard'), ['guard-90'], click('guard-95'), [{ action: 'guard', args: ['95'] }]);
  await check('cores', 'capacity', row('cores').querySelector('.rules-cores').textContent, 'None · 16 test slots', () => {}, []);
  await check('build', 'picking', pressed('build'), ['rule-P0', 'rule-P1', 'rule-P2', 'rule-P3', 'rule-followups'], click('rule-P0'), [{ action: 'rules', args: ['P0=off'] }]);
  await check('never', 'picking', row('never').querySelector('.chip').textContent, 'area:infra', click('area-on'), [{ action: 'rules', args: ['area:infra=on'] }]);
  await check('start', 'picking', pressed('start'), ['start-queue'], click('start-held'), [{ action: 'start', args: ['held'] }]);
  await check('dep-guard', 'picking', pressed('dep-guard'), ['dep-guard-on'], click('dep-guard-off'), [{ action: 'dep-guard', args: ['off'] }]);
  await check('split', 'picking', pressed('split'), ['split-shadow'], click('split-on'), [{ action: 'rules', args: ['split=on'] }]);
  await check('pick', 'picking', pressed('pick'), ['pick-off'], click('pick-shadow'), [{ action: 'rules', args: ['pick=shadow'] }]);
  await check('push', 'landing', pressed('push'), ['push-off'], click('push-on'), [{ action: 'rules', args: ['push=on'] }]);
  await check('land-as', 'landing', pressed('land-as'), ['land-as-main'], click('land-as-pr'), [{ action: 'land-as', args: ['pr'] }]);
  await check('pr-merge', 'landing', pressed('pr-merge'), ['pr-merge-button'], click('pr-merge-idle'), [{ action: 'pr-merge', args: ['idle'] }]);
  await check('push-check', 'landing', pressed('push-check'), ['push-check-on'], click('push-check-off'), [{ action: 'push-check', args: ['off'] }]);
  await check('visible', 'landing', pressed('visible'), ['visible-off'], click('visible-on'), [{ action: 'rules', args: ['visible=on'] }]);
  for (const k of ['asked-fix', 'review-followup', 'release-check', 'fixed-block', 'review-retry']) {
    await check(`standing-${k}`, 'standing', pressed(`standing-${k}`), [`standing-${k}-off`], click(`standing-${k}-on`), [{ action: 'standing', args: [k, 'on'] }]);
  }
  await check('held', 'order', act(rulesP(w), 'held-link').getAttribute('href'), '#rules-held', () => {}, []);
  await check('order', 'order', row('order').querySelector('.rules-pin').textContent, '#21 Later', click('unpin'), [{ action: 'unpin', args: ['21'] }]);
});

// Bugs: a pin showed its number alone, so the pinned list read as a wall of numbers; a drag sent another order than
// Move down, or none; pins past the first rows were lost instead of behind "View remaining"; View remaining took the
// keyboard focus away with it (the redraw removed the focused button), so Tab started again from the top of the page.
test('Rules: a pinned row shows its title; dragging the first pin onto the second sends what Move down sends', async () => {
  const w = boot({ tab: 'rules' });
  const d = full(), order = [21, 23, 20, 22, 24, 76, 99];
  d.panels.rules.data.control.order = order;
  w.reply = record({ order });
  deliver(w, d);
  const pins = () => Array.from(rulesP(w).querySelectorAll('[data-rule="order"] .rules-pin-row'));
  assert.deepEqual(pins().map((p) => p.querySelector('.rules-pin').textContent), ['#21 Later', '#23 Infra thing', '#20 Next up', '#22 Last', '#24 Second half'],
    'the first five, each with its title (#23 is only in the skipped and open issues)');
  // With the search box empty the panel shows one group at a time, and a control in a hidden group cannot take the focus: open the group that holds the pins.
  act(rulesP(w), 'rules-set-order').click();
  const more = act(rulesP(w), 'pins-all');
  more.focus();
  more.click();
  assert.equal(w.document.activeElement, pins()[5].querySelector('.rules-menu > summary'), 'the focus goes to the menu of the first pin View remaining shows');
  assert.deepEqual(pins().slice(5).map((p) => p.querySelector('.rules-pin').textContent), ['#76 Split the PROD stack', '#99'], 'View remaining shows the rest; no title known: the number');
  // Bug (issue 1430): the menu's summary had no data-act, so the redraw of the next snapshot lost the focus to the body.
  const again = clone(d);
  again.panels.rules.data.control.cap = 7;
  next(w, again);
  assert.equal(w.document.activeElement, pins()[5].querySelector('.rules-menu > summary'), 'a new snapshot leaves the focus on that pin\'s menu');
  const down = await sent(w, () => pins()[0].querySelector('[data-act="pin-down"]').click());
  assert.deepEqual(down, [{ action: 'order', args: ['23', '21', '20', '22', '24', '76', '99'], repo: 'sample' }]);
  const drag = await sent(w, () => {
    const [a, b] = pins();
    a.dispatchEvent(new w.Event('dragstart', { bubbles: true }));
    b.dispatchEvent(new w.Event('dragover', { bubbles: true, cancelable: true }));
    b.dispatchEvent(new w.Event('drop', { bubbles: true, cancelable: true }));
  });
  assert.deepEqual(drag, down, 'the drag sends the order Move down sends');
  const far = await sent(w, () => {
    pins()[0].dispatchEvent(new w.Event('dragstart', { bubbles: true }));
    pins()[3].dispatchEvent(new w.Event('drop', { bubbles: true, cancelable: true }));
  });
  assert.deepEqual(far, [{ action: 'order', args: ['23', '20', '22', '21', '24', '76', '99'], repo: 'sample' }], 'a drop further down moves the one pin there');
});

// Bug (#1359): a pin stayed in Pinned issues after its issue closed (the record's order is cleaned only at the next read
// of the open issues), so a finished issue looked pinned. With no list of open issues every pin shows (as the case above).
test('Rules: Pinned issues shows only the pins whose issue is still open in the snapshot', () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.control.order = [21, 98, 20];
  d.panels.rules.data.open = { ...d.panels.rules.data.open, issues: [20, 21, 22].map((issue) => ({ issue, title: `Open ${issue}`, labels: [] })) };
  deliver(w, d);
  assert.deepEqual(Array.from(rulesP(w).querySelectorAll('[data-rule="order"] .rules-pin-row'), (p) => p.dataset.issue), ['21', '20'], '#98 is closed: not pinned');
});

// Bugs: an On/Off rule's state was not the pressed part of one control, or it waited for a Save; a seat's pick was sent
// before its Save, or the seat said its model again beside the selects that show it.
test('Rules: an On/Off rule is one control with its state pressed and saves at once; a seat saves only on its Save', async () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.control.rules.push = false;
  w.reply = record({ rules: { ...d.panels.rules.data.control.rules, push: true } });
  deliver(w, d);
  const push = rulesP(w).querySelector('[data-rule="push"] .rules-seg');
  assert.equal(push.getAttribute('role'), 'group');
  assert.deepEqual(Array.from(push.querySelectorAll('button'), (b) => [b.textContent, b.getAttribute('aria-pressed')]), [['On', 'false'], ['Off', 'true']]);
  assert.deepEqual(await sent(w, () => act(push, 'push-on').click()), [{ action: 'rules', args: ['push=on'], repo: 'sample' }], 'sent at once');
  assert.equal(act(rulesP(w), 'push-on').getAttribute('aria-pressed'), 'true');
  const seat = rulesP(w).querySelector('[data-rule="builder"]'), inForce = () => rulesP(w).querySelector('[data-rule="builder"] .rules-in-force');
  assert.equal(shown(inForce()), false, 'saved: the selects alone show the model');
  const eff = act(seat, 'builder-effort');
  eff.value = 'low'; eff.dispatchEvent(new w.Event('change'));
  await settle();
  assert.deepEqual(w.posts, [], 'a pick sends nothing');
  assert.equal(shown(inForce()), true, 'unsaved: what is in force is said');
  assert.equal(inForce().textContent, 'In force: claude claude-opus-5-5 · high');
  w.reply = record({ model: { cli: 'claude', model: 'claude-opus-5-5', effort: 'low' } });
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'builder-save').click()), [{ action: 'model', args: ['claude', 'claude-opus-5-5', 'low'], repo: 'sample' }]);
});

// Bug: the segmented control hides what overflows it, so the focus outline, drawn 2px outside each part, was cut
// at its top and bottom. A stylesheet test: jsdom draws no layout, so the rule itself is what can be checked.
test('Rules: a part of a segmented control draws its focus outline inside the control', () => {
  assert.match(css, /\.rules-seg \{[^}]*overflow: hidden;/);
  assert.match(css, /\.rules-seg > \.rules-tog:focus-visible \{ outline-offset: -2px; \}/);
});

// Bug: the inset outline of the pressed part was in --focus, the same color as its --accent fill in each theme, so
// the focus on it could not be seen. A stylesheet test (jsdom draws no layout): the pressed part's outline is
// --on-accent, and no theme makes --on-accent the --accent color.
test('Rules: the pressed part of a segmented control draws its focus outline in a color apart from its fill', () => {
  assert.match(css, /\.rules-seg > \.rules-tog\[aria-pressed="true"\]:focus-visible \{ outline-color: var\(--on-accent\); \}/);
  const themes = Array.from(css.matchAll(/--accent: (#[0-9a-f]+); --on-accent: (#[0-9a-f]+);/gi));
  assert.ok(themes.length >= 2, 'the themes are read');
  for (const [, accent, on] of themes) assert.notEqual(on.toLowerCase(), accent.toLowerCase());
});

// Bug: a Build issues part armed for its second click is pressed and has board-danger, so its fill is --bad-bg, but
// its outline stayed --on-accent: #ffffff on #fde6e4 in the light theme, near unseen. A stylesheet test (jsdom draws no
// layout): the armed part's outline is --bad, set after the pressed rule of the same weight so it wins, and --bad
// stands 3:1 apart from --bad-bg in each theme.
test('Rules: an armed part of a segmented control draws its focus outline in a color apart from its fill', () => {
  const armed = css.indexOf('.rules-seg > .rules-tog.board-danger:focus-visible { outline-color: var(--bad); }');
  assert.ok(armed > css.indexOf('.rules-seg > .rules-tog[aria-pressed="true"]:focus-visible {'), 'the armed rule comes after the pressed one');
  const lum = (hex) => { const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
  const themes = Array.from(css.matchAll(/--bad: (#[0-9a-f]{6}); --bad-bg: (#[0-9a-f]{6});/gi));
  assert.ok(themes.length >= 2, 'the themes are read');
  for (const [, bad, bg] of themes) {
    const [hi, lo] = [lum(bad), lum(bg)].sort((x, y) => y - x);
    assert.ok((hi + 0.05) / (lo + 0.05) >= 3, `--bad ${bad} on --bad-bg ${bg}`);
  }
});

// Bug: docs/board.md put "Last change here" at the top of the Rules panel and the save line under it, while the panel
// draws the save line first, so a user read the two lines in the wrong order. The panel is drawn and the page's
// Rules section must name its two top lines in the order they are drawn.
test('Rules: docs/board.md names the two lines at the top of the panel in the order the panel draws them', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  const drawn = Array.from(rulesP(w).querySelector('.rules-top').children, (c) => c.textContent);
  const saves = drawn.findIndex((t) => t.startsWith('The Board saves a rule')), last = drawn.findIndex((t) => t.startsWith('Last change here'));
  assert.ok(saves >= 0 && last >= 0, drawn.join(' | '));
  const doc = readFileSync(new URL('../../../docs/board.md', import.meta.url), 'utf8');
  const top = doc.split(/^## Rules$/m)[1].split(/\n\n/)[1];
  const dSaves = top.indexOf('when each change is saved'), dLast = top.indexOf('last change you made here');
  assert.ok(dSaves >= 0 && dLast >= 0, top);
  assert.equal(dSaves < dLast, saves < last, `the page: ${top}`);
});

// Bug (#1038): the Rules panel took two of three columns, beside What these rules produce, and a layout kept with it
// at that width kept it there; its group list and label columns then left a rule's help a word a line.
// One case a width and layout, so each Board fixture runs in its own case.
const keptWide = JSON.stringify({ tabs: { rules: { order: ['rules', 'rules-produce'], sizes: { rules: 'wide', 'rules-produce': 'small' }, lengths: {}, collapsed: [], hidden: [] } } });
for (const [width, cols] of [[1440, 3], [900, 2]]) {
  for (const [layout, store] of [['the default layout', {}], ['a kept narrower width', { [STORE]: keptWide }]]) {
    test(`Rules: at ${cols} grid columns the Rules panel spans every column, with ${layout}`, () => {
      const w = boot({ tab: 'rules', width, store });
      deliver(w, full());
      assert.equal(w.document.getElementById('grid').dataset.cols, String(cols));
      assert.equal(rulesP(w).style.gridColumn, `1 / span ${cols}`);
      assert.deepEqual(Array.from(w.document.getElementById('size-rules').options, (o) => o.value), ['full'], 'no narrower width is offered');
    });
  }
}
