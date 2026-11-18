// SPDX-License-Identifier: Apache-2.0
// The dashboard page's Tests page, its actions (#521), the second part: no Tests model, the issue preview, and
// Auto-file (the switch, the preview, the log, a rule's field). The first part is dashboard-view.tests-actions.test.mjs.
// Shared setup: dashboard-view.helpers.mjs (TESTS: three files; TA: the snapshot with the actions).
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, act, cases, iso, TA, T0 } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { MERGE, X, NO_RULES, rec, snap, opened, open, type, said, auto, reply } = TA;

// Bug it guards: a judge asked for with no Tests model, which the engine refuses, or a run of the file kept back
// though it needs no model; (#100) a disabled Judge or Explain whose click did nothing: a click says why in its box.
for (const [a, words] of [['judge', 'Judge this test'], ['explain', 'Explain the slowdown']]) {
  test(`Tests actions: with no Tests model, ${words} says why in its box on a click and sends nothing; Run this file now is not held back`, () => {
    const w = boot({ tab: 'tests' });
    deliver(w, snap({ model: null }));
    act(open(w, MERGE), 'more').click();
    const more = opened(w, MERGE);
    assert.match(more.querySelector('.tests-why').textContent, /Set the Tests model first\./);
    assert.equal(act(more, 'run').disabled, false);
    act(more, a).click();
    assert.equal(opened(w, MERGE).querySelector('.tests-box').textContent, `${words}Not started: Set the Tests model first.`);
    assert.deepEqual(w.posts, []);
  });
}

// Bug it guards: an issue filed on one click, with no look at its text; a Cancel that filed; a preview with a run
// count or time target as its Done-when; an Optimize issue the engine does not know as one (its title), or with no
// judge's text for its card to start from (a tab in the text, which the server refuses in a body, is a space).
test('Tests actions: Optimize shows the preview and files only on the second button; Cancel files nothing', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, snap({ acts: [rec({ state: 'done', end: iso(Date.now()), verdict: 'speed up', text: 'It waits on a sleep.\tCut it.\nVERDICT: speed up\n' })] }));
  act(open(w, MERGE), 'optimize').click();
  let more = opened(w, MERGE);
  const title = act(more, 'issue-title'), body = act(more, 'issue-body');
  assert.equal(title.value, `Optimize the test file ${MERGE}`);
  assert.match(body.value, /CPU s in its last run: 12\.0\n- Median of its runs: 6\.0 CPU s \(\+100% against its median\)/);
  assert.match(body.value, /The judge's verdict .*: speed up\.\n\nThe end of its text:\nIt waits on a sleep\. Cut it\.\nVERDICT: speed up$/, 'the verdict kept, with its text');
  assert.doesNotMatch(body.value, /done.when/i, 'no Done-when line');
  assert.deepEqual(w.posts, [], 'the preview files nothing');
  act(more, 'issue-cancel').click();
  assert.deepEqual(w.posts, []);
  assert.equal(opened(w, MERGE).querySelector('.tests-preview'), null);
  act(opened(w, MERGE), 'optimize').click();
  more = opened(w, MERGE);
  type(act(more, 'issue-title'), 'Make merge.test.sh fast again');
  w.reply = reply('https://github.com/example/sample/issues/600');
  act(more, 'issue-file').click();
  await settle();
  const posts = w.posts.splice(0);
  assert.equal(posts.length, 1);
  assert.equal(posts[0].body.action, 'test-issue');
  // The file goes too: the engine keeps the issue as the file's, for its row's Close its issue as done.
  assert.deepEqual([posts[0].body.args[0], posts[0].body.args[1], posts[0].body.args[2] === body.value.trim()], [MERGE, 'Make merge.test.sh fast again', true]);
  assert.match(said(w), /Filed: https:\/\/github\.com\/example\/sample\/issues\/600/);
});

// Bug it guards (#519: 37 issues in one burst): auto-file shown as on, or turned on by one click with no look at what
// it would file.
test('Tests actions: Auto-file shows Off for a snapshot with no rules; Turn on posts nothing before the second click', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, snap({ rules: NO_RULES }));
  const sw = () => auto(w).querySelector('[data-limit="auto-switch"]');
  assert.equal(sw().querySelector('.board-value').textContent, 'Off');
  act(sw(), 'auto-on').click();
  assert.deepEqual(w.posts, [], 'the first click sends nothing');
  assert.ok(auto(w).querySelector('.tests-auto-preview'), 'the preview shows');
  act(auto(w), 'auto-on-confirm').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'testrules', args: ['on'], repo: 'sample' } }]);
});

// Bug it guards: a preview without the result of each match, or a log the owner cannot see.
test('Tests actions: the preview table shows each match with its guard result, and the log shows its lines', () => {
  const w = boot({ tab: 'tests' });
  deliver(w, snap());
  const rows = Array.from(auto(w).querySelectorAll('.tests-auto-match'), (r) => Array.from(r.children, (td) => td.textContent));
  assert.deepEqual(rows, [['over usual', MERGE, 'cpu 11.0, 11.5, 12.0; usual 6', 'Stopped by off: the switch is off'], ['over usual', X, 'cpu 9.0, 9.0, 9.0; usual 4', 'Would file']]);
  const log = Array.from(auto(w).querySelectorAll('.tests-auto-line'), (l) => l.textContent);
  assert.equal(log.length, 2);
  assert.match(log[0], /Filed #480 · rule over usual · conveyor\/tests\/merge\.test\.sh$/);
  assert.match(log[1], /Stopped by perDay · rule over usual · .*x\.test\.mjs · 3 issues filed today$/);
});

// Bug it guards: a rule changed by a typed value alone, or saved by a command the engine does not take.
test('Tests actions: a rule field shows Unsaved when changed, and Save posts the engine rule command', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, snap());
  const rule = () => auto(w).querySelector('[data-rule="over usual"]');
  assert.ok(act(rule(), 'rule-limit-save').hidden);
  type(act(rule(), 'rule-limit-field'), '1.5');
  assert.ok(!act(rule(), 'rule-limit-save').hidden && rule().textContent.includes('Unsaved'));
  assert.deepEqual(w.posts, []);
  act(rule(), 'rule-limit-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'testrules', args: ['set', 'over usual', 'limit', '1.5'], repo: 'sample' } }]);
});

// Bug it guards: a value saved here stood until a snapshot named it, so when another Board saved 4 just after this
// one's 2, every snapshot said 4 and the field said 2 for good. A snapshot begun before the Save was answered did not
// read it, and one the live feed republishes with a new time still names the value replaced: neither undoes the Save; one begun
// after the answer that names another value shows that value.
test('Tests actions: a saved guard stands against a snapshot begun before the answer or republished, and gives way to one changed elsewhere since', async () => {
  const w = boot({ tab: 'tests' });
  const at = (perDay, t) => snap({ rules: { ...TA.RULES, perDay }, at: t });
  const field = () => act(auto(w), 'guard-perDay-field');
  deliver(w, at(3, T0));
  type(field(), '2');
  w.reply = { ok: true, status: 200, headers: { get: (k) => (k === 'X-Answered-At' ? String(T0 / 1000) : null) }, text: () => Promise.resolve('conveyor: perDay is 2') };
  act(auto(w), 'guard-perDay-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'testrules', args: ['guard', 'perDay', '2'], repo: 'sample' } }]);
  // Begun before the answer (updatedAt T0 - 10 s) and naming 5, not the replaced 3: only the time keeps the Save.
  next(w, at(5, T0 + 10000));
  assert.equal(field().value, '2', 'a snapshot begun before the answer did not read the change, whatever value it names');
  next(w, at(3, T0 + 30000));
  assert.equal(field().value, '2', 'a republished snapshot still naming the value replaced does not undo the Save');
  next(w, at(4, T0 + 40000));
  assert.equal(field().value, '4', 'one begun after it shows the value saved elsewhere since');
});
