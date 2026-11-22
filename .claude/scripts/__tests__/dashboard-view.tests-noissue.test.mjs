// SPDX-License-Identifier: Apache-2.0
// The rule of the Tests page's cards with no GitHub issue (#1330, the control record's rules.testissues): its switch
// Tests page actions in the Rules tab's Done without asking, group Cards with no GitHub issue (#1346: On is
// testissues=off), sent as `control rules testissues=on|off`, and, with it On, the Tests page's actions that make a
// card, which start the card at once (test-issue: `conveyor.sh testissue` starts a card of no issue when the rule is
// off) in place of the issue preview. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, cases, iso, T0, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { MERGE, X, snap, opened, open, tp, rowOf } = TA;
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// The Rules part with the rule as given; 'none' leaves it out (an engine before the rule).
function rulesData(v) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, rules: { ...r.control.rules, ...(v === 'none' ? {} : { testissues: v }) } };
  return d;
}
const row = (w) => rulesP(w).querySelector('.rules-set [data-rule="testissues"]');
const pressed = (w) => ['noissue-tests-on', 'noissue-tests-off'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed'));

// Bugs this guards (#1346 D3, D7): the switch stayed under Picking, or was not in Done without asking's group Cards
// with no GitHub issue; its On kept the old meaning (files an issue), so a project that had set testissues=off saw it
// Off and one with the default saw it On; On or Off sent nothing or the opposite rule; the row did not say what Off
// does; an engine before the rule was sent a rule it refuses.
test('Rules: Tests page actions, under Done without asking in Cards with no GitHub issue, is On for testissues off and sends the rule turned', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, rulesData(true));
  const group = row(w).closest('.rules-group');
  assert.equal(row(w).closest('.rules-set').dataset.set, 'standing', 'the switch is in Done without asking');
  assert.equal(rulesP(w).querySelector('.rules-set[data-set="picking"] [data-rule="testissues"]'), null, 'the switch is no longer under Picking');
  assert.ok(group && group.dataset.group === 'noissue' && group.querySelector('.rules-group-name').textContent === 'Cards with no GitHub issue', 'the switch is in its group');
  assert.match(row(w).textContent, /Tests page actions/);
  assert.deepEqual(pressed(w), ['false', 'true'], 'testissues true (the default: issues filed) shows Off');
  assert.match(row(w).textContent, /off: an action on the Tests page files a GitHub issue, and the belt builds that issue as a card/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'noissue-tests-on').click()), [{ action: 'rules', args: ['testissues=off'], repo: 'sample' }]);
  next(w, rulesData(false));
  assert.deepEqual(pressed(w), ['true', 'false'], 'a project that had set testissues=off shows On');
  assert.doesNotMatch(row(w).textContent, /off:/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'noissue-tests-off').click()), [{ action: 'rules', args: ['testissues=on'], repo: 'sample' }]);
  next(w, rulesData('none'));
  assert.ok(act(rulesP(w), 'noissue-tests-on').disabled && act(rulesP(w), 'noissue-tests-off').disabled, 'an older engine is sent neither');
  assert.match(row(w).textContent, /needs a newer Conveyor/);
});

// Bugs this guards: with the rule off, an action still opened the issue preview, so a card started only once the owner
// filed an issue they had turned off; or it sent another title or file than the action's, so the engine held the card
// to another check. Optimize (its own button) and Fix hollow cases (one of the other fix actions) each send their
// draft at once, with no preview, and the row says what the build machine answered.
test('Tests: with Tests page issues off, Optimize and Fix hollow cases start their card at once, with no issue preview', async () => {
  const d = snap(), t = d.panels.tests.data;
  t.control = { ...t.control, rules: { testissues: false } };
  t.tests.files.find((f) => f.file === X).hollow = [{ case: 'loads', kind: 'no-assert', reason: 'no expect or assert call' }];
  const w = boot({ tab: 'tests' });
  deliver(w, d);
  for (const [file, how, title] of [[MERGE, 'optimize', `Optimize the test file ${MERGE}`], [X, 'fix-hollow', `Fix the hollow cases of the test file ${X}`]]) {
    w.reply = TA.reply(`Card queued with no GitHub issue: ${title}`);
    const b = act(open(w, file), how);
    assert.match(b.getAttribute('aria-label'), /start a card with no GitHub issue about/, `${how} of ${file} says it starts a card`);
    b.click();
    await settle();
    const posts = w.posts.splice(0).map((p) => p.body);
    assert.deepEqual(posts.map((p) => [p.action, p.args[0], p.args[1]]), [['test-issue', file, title]], `${how} of ${file} sent its card at once`);
    assert.match(posts[0].args[2], /\S/, `${how} of ${file} sent its draft's text`);
    assert.equal(act(opened(w, file), 'issue-title'), null, `${how} of ${file} opened no issue preview`);
    assert.match(opened(w, file).textContent, new RegExp(`Card queued with no GitHub issue: ${title.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&')}`), `${how} of ${file}: the row says the card is queued`);
  }
});

// Bug this guards: the Tests page dropped the Optimize history entry of a card with no issue (the snapshot's optimize
// entry of issue null, named "No issue", testfiles.sh), so its landed result was not shown, and a file it deleted
// showed under Removed by Optimize with no word of the card that removed it.
test('Tests history: an Optimize card of no issue shows in its row\'s Timeline and under Removed by Optimize, as "No issue"', () => {
  const d = snap(), files = d.panels.tests.data.tests.files, GONE = 'conveyor/tests/gone.test.sh';
  const local = (o) => ({ issue: null, card: 'c20261109T120000-sample-0', name: 'No issue', time: iso(T0 - 5 * 3600000), state: 'landed', reason: null, sha: 'abc1234def5678',
    landed: iso(T0 - 4 * 3600000), into: [], after: null, since: null, sinceRuns: 0, ...o });
  files.find((f) => f.file === MERGE).optimize = [local({ fix: 'sped up', before: 11, after: 6 })];
  files.push({ file: GONE, cpu: 5, median: 6, change: null, runs: [], timedRuns: 3, removed: true, optimize: [local({ fix: 'deleted', into: [X], before: 6 })] });
  const w = boot({ tab: 'tests' });
  deliver(w, d);
  const items = Array.from(open(w, MERGE).querySelectorAll('.tests-tl .tests-opt'));
  assert.deepEqual(items.map((i) => i.querySelector('.tests-tl-what').textContent), ['No issue · landed as abc1234 · sped up · 11.0 → 6.0 CPU s (-45%) Helped']);
  assert.equal(rowOf(w, GONE), undefined, 'the deleted file is not in the table');
  assert.match(tp(w).querySelector('.tests-removed .tests-gone').textContent, new RegExp(`^${GONE} · .+ · No issue · deleted .+ · its cases are now in ${X}$`));
});
