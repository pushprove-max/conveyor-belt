// SPDX-License-Identifier: Apache-2.0
// The dashboard page's Rules tab: the rules, what they produce, and the held issues, each its own panel.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, clone, boot, state, deliver, next, settle, P, CONTROL, MODELS, CLIS, full, act, record,
  rulesP, rulesAll, rulesText, ruled, produced, figure, nextUp, heldP, groupsOf, groupEl, rowsOf, heldMany, cases, pickProject } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

test('Rules: one row a rule on the left, what the snapshot says they produce on the right', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  assert.deepEqual(Array.from(ruled(w).querySelectorAll('.rules-row'), (r) => r.dataset.rule), ['builder', 'reviewer', 'judge', 'judge-always', 'account', 'review-account', 'cap', 'guard', 'atonce', 'suite', 'cores',
    'build', 'never', 'start', 'dep-guard', 'split', 'pick', 'push', 'land-as', 'pr-merge', 'push-check', 'lint', 'visible',
    'standing-asked-fix', 'standing-review-followup', 'standing-release-check', 'standing-fixed-block', 'standing-review-retry', 'testissues', 'held', 'order']);
  assert.deepEqual(['start-queue', 'start-held'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed')), ['true', 'false'], 'New issues start in: Queue, the default');
  assert.match(ruled(w).querySelector('[data-rule="start"]').textContent, /New issues start in/);
  for (const r of ruled(w).querySelectorAll('.rules-row')) assert.ok(r.querySelector('.rules-what').textContent, `${r.dataset.rule} says what it does`);
  const tog = (k) => act(rulesP(w), `rule-${k}`).getAttribute('aria-pressed');
  assert.deepEqual(['P0', 'P1', 'P2', 'followups'].map(tog), ['true', 'true', 'true', 'true']);
  assert.deepEqual(['guard-off', 'guard-90', 'guard-95', 'guard-98'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed')), ['false', 'true', 'false', 'false'], 'Pause at: Off and three choices');
  assert.match(ruled(w).querySelector('[data-rule="guard"]').textContent, /44% used/);
  assert.doesNotMatch(ruled(w).querySelector('[data-rule="guard"]').textContent, /no guard set/);
  assert.equal(act(rulesP(w), 'builder-cli').value, 'claude');
  assert.equal(act(rulesP(w), 'builder-model').value, 'claude-opus-5-5');
  assert.equal(act(rulesP(w), 'reviewer-cli').value, '', 'the reviewer is the seed\'s');
  assert.equal(act(rulesP(w), 'reviewer-cli').options[0].textContent, 'Default (gpt-6.1-sol)', 'the default names the seed\'s model, never routing.json');
  // The four counts, and Next up in pick order: the queue, then the issue that waits on another card, marked so.
  assert.deepEqual(['ready', 'waiting', 'held', 'skipped'].map((k) => figure(w, k)), ['3', '1', '2', '1']);
  assert.deepEqual(nextUp(w), [[21, 'ready'], [20, 'ready'], [22, 'ready'], [24, 'waits on #20']], 'the snapshot\'s order, never re-sorted here');
  assert.equal(produced(w).querySelector('[data-figure="usd"]').textContent, 'Forecast for the queue: about $2.85.');
  // No limit after the queue; no time to empty the queue.
  assert.doesNotMatch(rulesText(w), /limit after the queue/i);
  assert.equal(produced(w).querySelector('[data-figure="after"], [data-figure="minutes"]'), null);
  assert.doesNotMatch(produced(w).textContent, /to empty the queue/);
  assert.deepEqual(Array.from(produced(w).querySelectorAll('.rules-skip'), (x) => [Number(x.dataset.issue), x.lastChild.textContent]), [[23, 'Conveyor never builds area:infra']]);
  // The overrides of before are gone: no chip a held issue, no Overrides heading; a pin is one line among the rules.
  assert.doesNotMatch(rulesText(w), /Overrides|: held/);
  assert.equal(ruled(w).querySelector('[data-rule="order"]').textContent.includes('#21 Later'), true);
  assert.ok(Number(rulesP(w).dataset.rows) > 0, `the Rules panel counts its rows: ${rulesP(w).dataset.rows}`);
  // A waiting issue pinned first keeps its pin's place in Next up.
  const pinned = full();
  pinned.panels.rules.data.control = { ...pinned.panels.rules.data.control, order: [24, 21] };
  next(w, pinned);
  assert.deepEqual(nextUp(w), [[24, 'waits on #20'], [21, 'ready'], [20, 'ready'], [22, 'ready']], 'the pinned order holds for an issue that waits');
  // More than five: five shown; figures the snapshot did not give are not known, never 0.
  const long = full();
  long.panels.rules.data.queue = Array.from({ length: 8 }, (_, i) => ({ repo: 'sample', card: null, issue: 40 + i, title: `Q${i}`, url: `${P}/${40 + i}` }));
  long.panels.rules.data.forecast = { cards: 8, usd: null, perCard: { usd: null, pct: null }, guard: 90, reading: null, pausesAt: null };
  long.panels.rules.data.skipped = [{ issue: 50, title: 'P2 one', rule: 'P2' }, { issue: 51, title: 'A follow-up', rule: 'follow-ups' }];
  long.panels.rules.data.waits = [];
  long.panels.rules.data.limit = null;
  long.panels.rules.data.control.guard = null;
  next(w, long);
  assert.deepEqual(nextUp(w).map((x) => x[0]), [40, 41, 42, 43, 44]);
  assert.equal(figure(w, 'ready'), '8');
  assert.equal(produced(w).querySelector('[data-figure="usd"]').textContent, 'Forecast for the queue: not known.');
  assert.deepEqual(Array.from(produced(w).querySelectorAll('.rules-skip'), (x) => x.lastChild.textContent), ['P2 is off', 'follow-ups are off']);
  assert.match(ruled(w).querySelector('[data-rule="guard"]').textContent, /the Board does not know the use now.*no guard set/, 'no guard set is marked');
  assert.equal(act(rulesP(w), 'guard-off').getAttribute('aria-pressed'), 'true');
  // Nothing queued, and the issues not listed.
  const none = full();
  Object.assign(none.panels.rules.data, { queue: [], skipped: [], held: [], waits: [], open: { ...none.panels.rules.data.open, held: [] }, building: 0,
    control: { ...CONTROL, held: [], order: [], rules: { ...CONTROL.rules, never: [] } }, forecast: { ...none.panels.rules.data.forecast, cards: 0, usd: 0 } });
  next(w, none);
  assert.equal(state(w, 'rules'), 'ready', 'no queue is still rules to set');
  assert.ok(produced(w).textContent.includes('Nothing to build under these rules.'));
  assert.equal(produced(w).querySelector('.rules-skipped'), null);
  assert.equal(ruled(w).querySelector('[data-rule="never"] .rules-list').textContent, 'none');
  assert.equal(ruled(w).querySelector('[data-rule="order"]'), null, 'no pin: no line for it');
  assert.ok(heldP(w).textContent.includes('Nothing holds an issue.'));
  const unlisted = full();
  Object.assign(unlisted.panels.rules.data, { held: null, queue: null, skipped: null, waits: null, open: null, issuesError: 'GitHub did not list the open issues on buildhost.' });
  next(w, unlisted);
  assert.equal(produced(w).querySelector('.warn-note').textContent, 'GitHub did not list the open issues on buildhost.');
  assert.equal(produced(w).querySelector('.rules-stats'), null, 'never shown as an empty queue');
  // The held issues are not known either: never "Nothing holds an issue" or a count of 0 while the control record holds some.
  assert.doesNotMatch(heldP(w).textContent, /Nothing holds an issue|· 0/);
  assert.match(heldP(w).querySelector('.warn-note').textContent, /GitHub did not list the open issues on buildhost\. Not known: .*\(1 issue held by you\)/);
  assert.equal(heldP(w).querySelector('.rules-groups'), null);
  assert.match(ruled(w).querySelector('[data-rule="held"]').textContent, /Not known/);
  assert.doesNotMatch(ruled(w).querySelector('[data-rule="held"]').textContent, /0 held issues|No issue is held/);
  assert.ok(act(rulesP(w), 'rule-P0'), 'the rules can still be set');
});

test('Rules: a new snapshot keeps where "What these rules produce" was scrolled to', () => {
  // The box, its own panel, scrolls inside when taller than the window (app.css .rules-produce); a snapshot rebuilds it,
  // and without carrying its place over every live update threw it back to its top.
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  const was = produced(w);
  assert.ok(was.classList.contains('rules-produce'), 'the box carries the class its scrolling hangs on');
  assert.ok(!ruled(w).classList.contains('rules-produce'), 'the rules do not scroll inside a box');
  was.scrollTop = 120;
  const after = full(T0 + 60000);
  after.panels.rules.data.queue = after.panels.rules.data.queue.filter((x) => x.issue !== 20);
  next(w, after);
  assert.notEqual(produced(w), was, 'the snapshot rebuilt the box');
  assert.equal(produced(w).scrollTop, 120);
});

test('Rules: with 183 held issues the rules list none, and the held section is one line a group, largest first and closed', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, heldMany());
  assert.equal(ruled(w).querySelectorAll('[data-issue], .issue').length, 0, 'no issue among the rules');
  assert.match(ruled(w).querySelector('[data-rule="held"]').textContent, /View 183 held issues/);
  assert.equal(ruled(w).querySelector('[data-act="held-link"]').getAttribute('href'), '#rules-held');
  assert.equal(heldP(w).id, 'rules-held');
  assert.equal(heldP(w).querySelector('.board-head').textContent, 'Held by you or a label · 183');
  assert.equal(figure(w, 'held'), '183');
  assert.deepEqual(groupsOf(w), [['web', 52, '31 ux-change'], ['No area', 41, ''], ['backend', 33, ''], ['infra', 21, '9 dormant'], ['tooling', 19, ''], ['console', 11, ''], ['site', 6, '']]);
  assert.equal(heldP(w).querySelectorAll('.rules-held-row').length, 0, 'every group starts closed');
  assert.ok(Array.from(heldP(w).querySelectorAll('.rules-group-toggle')).every((b) => b.getAttribute('aria-expanded') === 'false'));
  // A group opens to five issues, then "Show 5 more" and "Show all (52)": the page's shared long list.
  groupEl(w, 'web').querySelector('[data-act="group"]').click();
  const web = groupEl(w, 'web');
  assert.equal(web.querySelector('[data-act="group"]').getAttribute('aria-expanded'), 'true');
  assert.equal(rowsOf(web).length, 5);
  assert.deepEqual(Array.from(web.querySelectorAll('.show-more button'), (b) => b.textContent), ['Show 5 more', 'Show all (52)']);
  const row = web.querySelector('.rules-held-row');
  assert.ok(row.querySelector('.issue') && row.querySelector('.board-title') && row.querySelector('.rules-prio') && row.querySelector('[data-act="queue"]'), 'number, title, priority and Queue');
  act(web, 'list-more').click();
  assert.equal(rowsOf(groupEl(w, 'web')).length, 10);
  act(groupEl(w, 'web'), 'list-all').click();
  assert.equal(rowsOf(groupEl(w, 'web')).length, 52);
  assert.equal(groupEl(w, 'web').querySelector('.show-more').hidden, true, 'all shown: no control');
  assert.ok(Array.from(groupEl(w, 'web').querySelectorAll('.rules-held-row')).some((r) => r.textContent.includes('ux-change')), 'and its holding label');
  // Group by priority, or by holding label.
  const by = act(heldP(w), 'held-by');
  assert.deepEqual(Array.from(by.options, (o) => o.textContent), ['Area', 'Priority', 'Label']);
  by.value = 'priority'; by.dispatchEvent(new w.Event('change'));
  assert.deepEqual(groupsOf(w).map((g) => [g[0], g[1]]), [['P2', 120], ['P1', 63]], 'every third issue of an area is P1');
  const by2 = act(heldP(w), 'held-by');
  by2.value = 'label'; by2.dispatchEvent(new w.Event('change'));
  assert.deepEqual(groupsOf(w).map((g) => [g[0], g[1]]), [['No label: held by you', 143], ['ux-change', 31], ['dormant', 9]]);
});

test('Rules: the search narrows the groups to their matches, by number or title, and opens them', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, heldMany());
  const search = act(heldP(w), 'held-search');
  search.value = 'console thing 1'; search.dispatchEvent(new w.Event('input'));
  assert.deepEqual(groupsOf(w).map((g) => [g[0], g[1]]), [['console', 2]], 'console thing 1 and 10');
  assert.equal(rowsOf(groupEl(w, 'console')).length, 2, 'a group with matches opens');
  assert.equal(w.document.activeElement === search || act(heldP(w), 'held-search') === search, true, 'the field is the same one: typing goes on');
  search.value = '#100000'; search.dispatchEvent(new w.Event('input'));
  assert.deepEqual(groupsOf(w).map((g) => g[0]), ['web']);
  assert.deepEqual(rowsOf(groupEl(w, 'web')), [100000]);
  assert.deepEqual(groupsOf(w), [['web', 1, '1 ux-change']], 'the label mark counts only the matches');
  search.value = '#100031'; search.dispatchEvent(new w.Event('input'));
  assert.deepEqual(groupsOf(w), [['web', 1, '']], 'a match no label holds shows no label mark');
  search.value = 'no such thing'; search.dispatchEvent(new w.Event('input'));
  assert.ok(heldP(w).textContent.includes('No held issue matches the search.'));
  search.value = ''; search.dispatchEvent(new w.Event('input'));
  assert.equal(groupsOf(w).length, 7);
  assert.equal(heldP(w).querySelectorAll('.rules-held-row').length, 0, 'closed again');
});

test('Rules: Queue releases an issue the record holds; on one a label holds it says so first, then removes the label', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  assert.deepEqual(groupsOf(w), [['infra', 1, ''], ['web', 1, '1 ux-change']]);
  groupEl(w, 'infra').querySelector('[data-act="group"]').click();
  groupEl(w, 'infra').querySelector('[data-issue="76"] [data-act="queue"]').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'release', args: ['76'], repo: 'sample' } }]);
  // Issue 407: a queue is undone by a hold, from the line that says it was done.
  act(rulesP(w), 'undo').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'hold', args: ['76'], repo: 'sample' } }]);
  groupEl(w, 'web').querySelector('[data-act="group"]').click();
  const q = () => groupEl(w, 'web').querySelector('[data-issue="35"] [data-act="queue"]');
  q().click();
  await settle();
  assert.deepEqual(w.posts, [], 'nothing is sent on the first click');
  assert.match(heldP(w).closest('.panel').querySelector('.rules-note').textContent, /The label ux-change holds #35\. Click once more to remove it on GitHub for good and queue #35/);
  assert.equal(q().textContent, 'Click again: remove the label ux-change on GitHub');
  q().click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'unlabel', args: ['35', 'ux-change'], repo: 'sample' } }], 'the Board\'s "Remove the label and queue it"');
  assert.match(groupEl(w, 'web').querySelector('[data-issue="35"]').textContent, /Label removed/);
});

test('Rules: Queue all asks once, naming the count and the labelled ones, and leaves those out unless asked', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, heldMany());
  act(groupEl(w, 'web'), 'queue-all').click();
  await settle();
  assert.deepEqual(w.posts, [], 'it asks first');
  const ask = groupEl(w, 'web').querySelector('.rules-ask');
  assert.match(ask.textContent, /Queue all 52 issues of web\? A label holds 31 of them \(31 ux-change\): if you do not include them, Conveyor leaves them out\./);
  assert.equal(act(ask, 'queue-all-yes').textContent, 'Queue 21');
  act(ask, 'queue-all-no').click();
  assert.equal(groupEl(w, 'web').querySelector('.rules-ask'), null, 'Cancel sends nothing');
  act(groupEl(w, 'web'), 'queue-all').click();
  act(groupEl(w, 'web'), 'queue-all-yes').click();
  await settle();
  const sent = w.posts.splice(0);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].body.action, 'release');
  assert.deepEqual(sent[0].body.args.map(Number).sort((a, b) => a - b), Array.from({ length: 21 }, (_, i) => 100031 + i), 'the 21 the record holds, none a label holds');
  // Asked to include them: the labels are removed too, one issue at a time.
  act(groupEl(w, 'web'), 'queue-all').click();
  const box = act(groupEl(w, 'web'), 'queue-all-labels');
  box.checked = true; box.dispatchEvent(new w.Event('change'));
  assert.equal(act(groupEl(w, 'web'), 'queue-all-yes').textContent, 'Queue 52');
  act(groupEl(w, 'web'), 'queue-all-yes').click();
  await settle();
  const all = w.posts.splice(0);
  assert.deepEqual(all.map((p) => p.body.action), ['release'].concat(Array(31).fill('unlabel')));
  assert.deepEqual(all.slice(1).map((p) => p.body.args).sort((a, b) => a[0] - b[0]), Array.from({ length: 31 }, (_, i) => [String(100000 + i), 'ux-change']));
  // A group of more than 50 is released in batches the host takes.
  const big = heldMany();
  big.panels.rules.data.open.held.forEach((x) => { x.labels = x.labels.filter((l) => !l.startsWith('area:')); x.reasons = [{ kind: 'you' }]; });
  big.panels.rules.data.control.held = big.panels.rules.data.open.held.map((x) => x.issue);
  next(w, big);
  act(groupEl(w, 'No area'), 'queue-all').click();
  act(groupEl(w, 'No area'), 'queue-all-yes').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args.length), [50, 50, 50, 33]);
});

test('Rules: turning a Build choice off, or a Never build label, says how many queued issues it would skip before it is made', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  assert.equal(ruled(w).querySelector('[data-rule="build"] .rules-would').textContent,
    'Turning P2 off would skip 2 of the 3 queued issues. Turning Follow-ups off would skip 1 of the 3 queued issues.');
  assert.match(act(rulesP(w), 'rule-P2').getAttribute('aria-label'), /turning it off would skip 2 queued/);
  const field = act(rulesP(w), 'area-name'), note = ruled(w).querySelector('[data-would="area"]');
  field.value = 'web'; field.dispatchEvent(new w.Event('input'));
  assert.equal(note.textContent, 'Never building area:web would skip 2 of the 3 queued issues.');
  field.value = 'area:tenant'; field.dispatchEvent(new w.Event('input'));
  assert.equal(note.textContent, '', 'one that skips nothing says nothing');
  assert.deepEqual(w.posts, [], 'nothing is sent while it is typed');
});

test('Rules: P3 is a Build switch like P2, on when the record has no P3 key, and the Board never says P3 is never built', async () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  assert.equal(Object.prototype.hasOwnProperty.call(d.panels.rules.data.control.rules, 'P3'), false, 'the record is one saved before P3 had a switch');
  d.panels.rules.data.queue.push({ repo: 'example', card: null, issue: 25, title: 'Lowest', url: null, priority: 'P3', followup: false, retried: false, areas: [] });
  deliver(w, d);
  const build = ruled(w).querySelector('[data-rule="build"]');
  assert.doesNotMatch(build.textContent, /never built/);
  const p3 = act(rulesP(w), 'rule-P3');
  assert.equal(p3.getAttribute('aria-pressed'), 'true', 'a record with no P3 key reads as P3 on');
  assert.match(p3.getAttribute('aria-label'), /^Build P3: on; turning it off would skip 1 queued$/);
  assert.match(build.querySelector('.rules-would').textContent, /Turning P3 off would skip 1 of the 4 queued issues\./);
  p3.click();
  act(rulesP(w), 'rule-P3').click();  // it skips a queued issue: the second click turns it off
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'rules', args: ['P3=off'], repo: 'sample' } }]);
});

test('Rules: an area rule is the pack\'s area prefix and a name', async () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.areaPrefix = 'team/';
  d.panels.rules.data.control.rules.never = ['team/infra'];
  deliver(w, d);
  assert.equal(act(rulesP(w), 'area-name').placeholder, 'team/infra');
  act(rulesP(w), 'area-on').click(); await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'rules', args: ['team/infra=on'], repo: 'sample' } }]);
  const field = act(rulesP(w), 'area-name');
  field.value = 'billing'; field.dispatchEvent(new w.Event('input'));
  act(rulesP(w), 'area-off').click(); await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'rules', args: ['team/billing=off'], repo: 'sample' } }]);
});

test('Rules: each rule sends its one change through POST control; the host\'s record shows at once, the forecast with the next snapshot', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  const sends = async (fn, body) => { fn(); await settle(); assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { ...body, repo: 'sample' } }]); };
  assert.equal(rulesP(w).querySelector('.rules-top').textContent, 'The Board saves a rule when you change it. It saves the Builder, Reviewer and Judge models when you press Save.Last change here: none yet', 'no change made here yet');
  // P2 and Follow-ups each skip queued issues: the first click arms, the second sends.
  const twice = (a) => () => { act(rulesP(w), a).click(); act(rulesP(w), a).click(); };
  await sends(twice('rule-P2'), { action: 'rules', args: ['P2=off'] });
  // Issue 407: a switch is easily undone, so the line that says it was done has Undo, which sends the opposite; the
  // wait is said as everywhere, "in about a minute".
  assert.equal(rulesP(w).querySelector('.rules-note').textContent, 'Done. What the rules produce updates in about a minute. Undo');
  await sends(() => act(rulesP(w).querySelector('.rules-note'), 'undo').click(), { action: 'rules', args: ['P2=on'] });
  assert.equal(act(rulesP(w), 'rule-P2').getAttribute('aria-pressed'), 'true', 'undone, the switch shows on again');
  assert.equal(act(rulesP(w), 'rule-P2').dataset.guard, undefined, 'a switch is not a spend or final guard');
  await sends(twice('rule-followups'), { action: 'rules', args: ['followups=off'] });
  await sends(() => act(rulesP(w), 'area-on').click(), { action: 'rules', args: ['area:infra=on'] });
  const field = act(rulesP(w), 'area-name');
  field.value = 'tenant'; field.dispatchEvent(new w.Event('input'));
  await sends(() => act(rulesP(w), 'area-off').click(), { action: 'rules', args: ['area:tenant=off'] });
  assert.equal(act(rulesP(w), 'area-name').value, '', 'the field is cleared once the host took it');
  const bad = act(rulesP(w), 'area-name');
  bad.value = 'two words'; bad.dispatchEvent(new w.Event('input'));
  act(rulesP(w), 'area-off').click();
  await settle();
  assert.deepEqual(w.posts, [], 'a label the host would refuse is not sent');
  assert.match(rulesP(w).querySelector('.rules-note').textContent, /area label/);
  await sends(() => act(rulesP(w), 'cards at once-up').click(), { action: 'cap', args: ['4'] });
  await sends(() => act(rulesP(w), 'guard-95').click(), { action: 'guard', args: ['95'] });
  act(rulesP(w), 'guard-95').click();
  await settle();
  assert.deepEqual(w.posts, [], 'the choice in force, the one just made, sends nothing');
  await sends(() => act(rulesP(w), 'guard-off').click(), { action: 'guard', args: ['off'] });
  // A role is sent by its Save, whole: the effort in force goes with the new model.
  const model = act(rulesP(w), 'builder-model');
  model.value = 'claude-fable-5-2'; model.dispatchEvent(new w.Event('change'));
  await sends(() => act(rulesP(w), 'builder-save').click(), { action: 'model', args: ['claude', 'claude-fable-5-2', 'high'] });
  const cli = act(rulesP(w), 'reviewer-cli');
  cli.value = 'codex'; cli.dispatchEvent(new w.Event('change'));
  const effort = act(rulesP(w), 'reviewer-model');
  effort.value = 'gpt-6-astra'; effort.dispatchEvent(new w.Event('change'));
  await sends(() => act(rulesP(w), 'reviewer-save').click(), { action: 'reviewer', args: ['codex', 'gpt-6-astra'] });
  // Unpin takes the one issue out of the order on the host: a pin set elsewhere since this record was read stays.
  await sends(() => act(rulesP(w), 'unpin').click(), { action: 'unpin', args: ['21'] });
  // The host's answer is the record: the left shows it at once; the right is the snapshot's until the next one.
  w.reply = record({ rules: { ...CONTROL.rules, P1: false }, order: [21] });
  await sends(() => act(rulesP(w), 'rule-P1').click(), { action: 'rules', args: ['P1=off'] });
  assert.equal(act(rulesP(w), 'rule-P1').getAttribute('aria-pressed'), 'false');
  assert.equal(rulesP(w).querySelector('.rules-last-what').textContent, 'Last change here: P1 off, 12:00 PM', 'the head shows the last change, what and when');
  assert.deepEqual(nextUp(w).map((x) => x[0]), [21, 20, 22, 24], 'the queue is not recomputed here');
  assert.match(produced(w).textContent, /shows it in about a minute/);
  await sends(() => act(rulesP(w), 'rule-P1').click(), { action: 'rules', args: ['P1=on'] });
  w.reply = undefined;
  const after = full(T0 + 60000);  // begun after the host's answer
  after.panels.rules.data.control.rules.P1 = false;
  after.panels.rules.data.queue = after.panels.rules.data.queue.filter((x) => x.issue !== 20);
  next(w, after);
  assert.deepEqual(nextUp(w).map((x) => x[0]), [21, 22, 24], 'the next snapshot shows what the change produced');
  assert.doesNotMatch(produced(w).textContent, /shows it in about a minute/);
  // One change at a time; the searches, the grouping and the rules' index change nothing and stay on.
  let answer;
  w.reply = { ok: true, status: 200, text: () => new Promise((r) => { answer = r; }) };
  act(rulesP(w), 'rule-P0').click();
  await settle();
  assert.equal(w.posts.splice(0).length, 1);
  for (const b of rulesAll(w).flatMap((p) => Array.from(p.querySelectorAll('.rules button, .rules input, .rules select')))) {
    assert.equal(b.disabled, !['held-search', 'held-by', 'rules-find', 'rules-set-models', 'rules-set-capacity', 'rules-set-picking', 'rules-set-landing',
      'rules-set-standing', 'rules-set-order'].includes(b.dataset.act),`${b.dataset.act} is ${b.disabled ? 'off' : 'on'} while the change is out`);
  }
  answer(JSON.stringify(CONTROL));
  await settle();
  assert.equal(act(rulesP(w), 'rule-P0').disabled, false);
  w.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: the record is locked') };
  act(rulesP(w), 'rule-P0').click();
  await settle();
  assert.match(rulesP(w).querySelector('.rules-note').textContent, /^Not done: conveyor: the record is locked/);
  // New issues start in. The choice in force sends nothing; the host's record shows at once.
  w.posts.splice(0);
  act(rulesP(w), 'start-queue').click();
  await settle();
  assert.deepEqual(w.posts, [], 'Queue, in force, sends nothing');
  w.reply = record({ start: 'held', startHeld: [{ from: 3940, to: null }] });
  await sends(() => act(rulesP(w), 'start-held').click(), { action: 'start', args: ['held'] });
  assert.deepEqual(['start-queue', 'start-held'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed')), ['false', 'true'], 'the host\'s record shows Held');
  assert.match(rulesP(w).querySelector('.rules-last-what').textContent, /new issues start in Held/);
  w.reply = undefined;
  await sends(() => act(rulesP(w), 'start-queue').click(), { action: 'start', args: ['queue'] });
});

// The account a project's cards use, and its reviews': one of the host file's accounts, or the default login.
test('Rules: the account and review account are chosen from the host\'s accounts', async () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.accounts = ['first', 'second'];
  deliver(w, d);
  const pick = async (sel, value, body) => {
    const s = act(rulesP(w), sel); s.value = value; s.dispatchEvent(new w.Event('change')); await settle();
    assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { ...body, repo: 'sample' } }]);
  };
  assert.deepEqual(Array.from(act(rulesP(w), 'account').options, (o) => [o.value, o.selected]), [['', true], ['first', false], ['second', false]], 'none set: the default login');
  assert.match(act(rulesP(w), 'account').options[0].textContent, /own login/);
  w.reply = record({ account: 'second' });
  await pick('account', 'second', { action: 'account', args: ['second'] });
  assert.equal(act(rulesP(w), 'account').value, 'second', 'the host\'s record shows at once');
  w.reply = record({ account: 'second', reviewAccount: 'first' });
  await pick('review-account', 'first', { action: 'review-account', args: ['first'] });
  w.reply = record({ account: null });
  // The default is sent as no name: no word stands for it, so an account named default can be chosen too.
  await pick('account', '', { action: 'account', args: [] });
  // A host file with no accounts: nothing to choose, and it says so.
  const none = boot({ tab: 'rules' });
  deliver(none, full());
  assert.equal(act(rulesP(none), 'account'), null);
  assert.match(rulesP(none).textContent, /The build machine has no other account, so cards use the build machine's own login\./);
});

// The review's judge was set in the pack (on or off, the kinds) and by a command (its model): the owner could not see
// or change it here. Each project has its own. Bug (#441): the reviewer's CLI was never offered, so with a Codex
// reviewer the owner could not pick a Codex judge; one picked is said to be of the reviewer's family.
test('Rules: the Judge row shows each project\'s judge (on or off, CLI, model, effort, kinds), offers every CLI, the reviewer\'s too, and saves to that project\'s control record', async () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  // sample: a Codex reviewer and a judge never set. widgetshop: a Claude reviewer, so a Codex judge; on, with a
  // model and an effort named and two kinds always accepted.
  const wctl = { ...clone(CONTROL), reviewer: { cli: 'claude', model: 'claude-sonnet-5-5', effort: null }, judge: { cli: 'codex', model: 'gpt-6-astra', effort: 'high' }, judgeOn: true, judgeAlways: ['security', 'data'] };
  const wmodels = { ...clone(MODELS),
    reviewer: { model: 'claude-sonnet-5-5', effort: 'medium', agent: 'claude', modelFrom: 'control', effortFrom: 'seed', choices: ['gpt-6.1-sol', 'gpt-6-astra', 'claude-opus-5-5', 'claude-sonnet-5-5'], efforts: ['low', 'medium', 'high', 'xhigh', 'max'], clis: CLIS, missing: null },
    judge: { model: 'gpt-6-astra', effort: 'high', agent: 'codex', modelFrom: 'control', effortFrom: 'control', choices: ['gpt-6.1-sol', 'gpt-6-astra'], efforts: ['minimal', 'low', 'medium', 'high', 'xhigh'], default: 'gpt-6.1-sol',
      clis: CLIS, missing: null } };
  Object.assign(d.panels.rules.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: { ...clone(d.panels.rules.data), repo: 'widgetshop', control: wctl, modelSettings: wmodels } } });
  d.panels.machine.data.repos = ['sample', 'widgetshop'];
  deliver(w, d);
  const row = () => ruled(w).querySelector('[data-rule="judge"]'), kindRow = () => ruled(w).querySelector('[data-rule="judge-always"]');
  const shown = () => ({
    on: ['judge-on', 'judge-off'].map((a) => act(row(), a).getAttribute('aria-pressed')).join(' '),
    cli: act(row(), 'judge-cli').value, model: act(row(), 'judge-model').value, effort: act(row(), 'judge-effort').value,
    offered: Array.from(act(row(), 'judge-cli').options, (o) => o.textContent),
    kinds: Array.from(kindRow().querySelectorAll('[data-list="judge-kinds"] .rules-item .chip'), (c) => c.textContent),
  });
  const sends = async (fn, body, repo) => { fn(); await settle(); assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { ...body, repo } }]); };
  const set = (a, v) => { const s = act(row(), a); s.value = v; s.dispatchEvent(new w.Event('change')); };
  const type = (v) => { const f = act(kindRow(), 'judge-kind'); f.value = v; f.dispatchEvent(new w.Event('input')); act(kindRow(), 'judge-kind-add').click(); };
  // sample: off, at the default, which names the model the judge would run on; every installed CLI is offered.
  assert.deepEqual(shown(), { on: 'false true', cli: '', model: '', effort: '', offered: ['Default (claude-opus-5-5)', 'claude', 'codex', 'opencode'], kinds: [] });
  assert.match(row().textContent, /claude-opus-5-5 · medium/, 'the model and effort in force');
  assert.match(kindRow().textContent, /always accepts no kind/);
  assert.doesNotMatch(row().textContent, /same family/, 'a Claude judge is not of the Codex reviewer\'s family');
  act(row(), 'judge-off').click(); await settle();
  assert.deepEqual(w.posts, [], 'the choice in force sends nothing');
  w.reply = record({ judgeOn: true });
  await sends(() => act(row(), 'judge-on').click(), { action: 'judge', args: ['on'] }, 'sample');
  assert.equal(shown().on, 'true false', 'the host\'s record shows at once');
  assert.match(rulesP(w).querySelector('.rules-last-what').textContent, /Last change here: judge on/);
  // Claude Code lists no models: its models are the pack's for the review, and each is sent by Save.
  set('judge-cli', 'claude');
  w.reply = record({ judgeOn: true, judge: { cli: 'claude', model: 'claude-sonnet-5-5', effort: null } });
  set('judge-model', 'claude-sonnet-5-5');
  await sends(() => act(row(), 'judge-save').click(), { action: 'judge', args: ['claude', 'claude-sonnet-5-5'] }, 'sample');
  assert.deepEqual([shown().cli, shown().model], ['claude', 'claude-sonnet-5-5']);
  assert.equal(act(row(), 'judge-cli').options[0].textContent, 'Default (claude-opus-5-5)', 'the default still names the model it would run on');
  w.reply = record({ judgeOn: true, judge: { cli: 'claude', model: 'claude-sonnet-5-5', effort: 'high' } });
  set('judge-effort', 'high');
  await sends(() => act(row(), 'judge-save').click(), { action: 'judge', args: ['claude', 'claude-sonnet-5-5', 'high'] }, 'sample');
  assert.equal(shown().effort, 'high');
  // The Codex reviewer's CLI: offered, saved, and the row says the judge is of the reviewer's family.
  w.reply = record({ judgeOn: true, judge: { cli: 'codex', model: 'gpt-6-astra', effort: null } });
  set('judge-cli', 'codex');
  set('judge-model', 'gpt-6-astra');
  await sends(() => act(row(), 'judge-save').click(), { action: 'judge', args: ['codex', 'gpt-6-astra'] }, 'sample');
  assert.deepEqual([shown().cli, shown().model], ['codex', 'gpt-6-astra']);
  assert.match(row().textContent, /codex gpt-6-astra · /, 'the Codex judge is in force');
  assert.match(row().textContent, /same family as the reviewer/);
  w.reply = record({ judgeOn: true, judge: null });
  set('judge-cli', '');
  await sends(() => act(row(), 'judge-save').click(), { action: 'judge', args: ['default'] }, 'sample');
  assert.deepEqual([shown().cli, shown().model], ['', '']);
  assert.match(row().textContent, /claude-opus-5-5 · medium/);
  // The kinds are saved whole: one more, and one that is no word is not sent.
  w.reply = record({ judgeOn: true, judgeAlways: ['security'] });
  await sends(() => type('security'), { action: 'judge', args: ['always', 'security'] }, 'sample');
  assert.deepEqual(shown().kinds, ['security']);
  assert.equal(act(kindRow(), 'judge-kind').value, '','the field is cleared once the host took it');
  type('two words'); await settle();
  assert.deepEqual(w.posts, [], 'a kind the host would refuse is not sent');
  assert.match(rulesP(w).querySelector('.rules-note').textContent, /finding kind/);
  // widgetshop: its own judge, and a change there is sent for it alone.
  pickProject(w, 'widgetshop');
  assert.deepEqual(shown(), { on: 'true false', cli: 'codex', model: 'gpt-6-astra', effort: 'high', offered: ['Default (gpt-6.1-sol)', 'claude', 'codex', 'opencode'], kinds: ['security', 'data'] });
  w.reply = record({ ...wctl, judgeAlways: ['security'] });
  await sends(() => kindRow().querySelectorAll('[data-act="judge-kind-remove"]')[1].click(), { action: 'judge', args: ['always', 'security'] }, 'widgetshop');
  assert.deepEqual(shown().kinds, ['security']);
  w.reply = record({ ...wctl, judgeAlways: [] });
  await sends(() => act(kindRow(), 'judge-kind-remove').click(), { action: 'judge', args: ['always'] }, 'widgetshop');
  assert.deepEqual(shown().kinds, [], 'none clears them');
  w.reply = record({ ...wctl, judgeAlways: [], judgeOn: false });
  await sends(() => act(row(), 'judge-off').click(), { action: 'judge', args: ['off'] }, 'widgetshop');
  assert.equal(shown().on, 'false true');
});

test('Rules: a control keeps the keyboard focus through the change it sends', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  let answer;
  w.reply = { ok: true, status: 200, text: () => new Promise((r) => { answer = r; }) };
  // The panel shows one group at a time and a control in a hidden group cannot take the focus: open the toggle's group.
  act(rulesP(w), 'rules-set-picking').click();
  act(rulesP(w), 'rule-P2').focus();
  act(rulesP(w), 'rule-P2').click();
  assert.equal(w.document.activeElement, act(rulesP(w), 'rule-P2'), 'armed for its second click, it keeps the focus');
  act(rulesP(w), 'rule-P2').click();
  await settle();
  assert.equal(act(rulesP(w), 'rule-P2').disabled, true, 'off while the change is out');
  answer(JSON.stringify({ ...CONTROL, rules: { ...CONTROL.rules, P2: false } }));
  await settle();
  assert.equal(w.document.activeElement, act(rulesP(w), 'rule-P2'), 'the toggle has the focus again once the host answers');
  assert.equal(act(rulesP(w), 'rule-P2').getAttribute('aria-pressed'), 'false');
  // A control on an issue gets it back on the same issue's row.
  const twice = full();
  twice.panels.rules.data.control.order = [21, 22];
  twice.panels.rules.data.control.rules.P2 = false;  // it read the change the host took
  next(w, twice);
  act(rulesP(w), 'rules-set-order').click();  // the group that holds the pins
  const unpin22 = rulesP(w).querySelector('.rules-item[data-issue="22"] [data-act="unpin"]');
  unpin22.focus();
  w.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: the record is locked') };
  unpin22.click();
  await settle();
  assert.equal(w.document.activeElement, rulesP(w).querySelector('.rules-item[data-issue="22"] [data-act="unpin"]'), 'a refused unpin leaves the focus on its own row');
});

// The owner pressed Judge On; the record held it, but the page went back to Off: a snapshot begun before the host
// took the change was drawn over it, so the setting looked unsaved and was pressed again.
test('Rules: a changed setting shows its new value at once and keeps it until a snapshot begun after the host took it', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  const judge = () => ['judge-on', 'judge-off'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed')).join(' ');
  const cap = () => act(rulesP(w), 'cards at once-up').previousSibling.textContent;
  let answer;
  w.reply = { ...record({}), text: () => new Promise((r) => { answer = r; }) };
  act(rulesP(w), 'judge-on').click();
  assert.equal(judge(), 'true false', 'On shows the moment it is pressed');
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'judge', args: ['on'], repo: 'sample' } }]);
  next(w, full(T0 - 5000));
  assert.equal(judge(), 'true false', 'a feed arriving while the change is out does not draw Off over it');
  answer(JSON.stringify({ ...CONTROL, judgeOn: true }));
  await settle();
  assert.equal(judge(), 'true false');
  // The host took it at T0. A snapshot begun before then, however late it arrives, leaves On.
  w.clock += 180000;
  next(w, full(T0 - 1000 + 20000));
  assert.equal(judge(), 'true false', 'a feed older than the change leaves the control on the new value');
  assert.match(produced(w).textContent, /shows it in about a minute/, 'the right still waits for a snapshot that has the change');
  // The live feed republishes the record it last read with a new time: stamped after the change, it still holds Off,
  // so it did not read the change and leaves On.
  next(w, full(T0 + 10000));
  assert.equal(judge(), 'true false', 'a feed stamped after the change that still holds the old value leaves the new one');
  // One begun at or after it that holds the new value keeps it, and is the record from then on.
  const newer = full(T0 + 20000); newer.panels.rules.data.control.judgeOn = true;
  next(w, newer);
  assert.equal(judge(), 'true false', 'a feed newer than the change that holds it keeps the new value');
  assert.doesNotMatch(produced(w).textContent, /shows it in about a minute/);
  next(w, full(T0 - 3000));
  assert.equal(judge(), 'true false', 'a feed older than the change arriving after that is turned away');
  // A raised cap: an older snapshot never shows 3 again, so the next raise is from the 4 shown.
  w.reply = record({ judgeOn: true, cap: 4 }, w.clock);
  act(rulesP(w), 'cards at once-up').click();
  assert.equal(cap(), '4', 'the raise shows at once');
  await settle();
  w.posts.splice(0);
  const before = full(w.clock - 1000 + 20000); before.panels.rules.data.control.judgeOn = true;
  next(w, before);
  assert.equal(cap(), '4', 'a feed begun a second before the answer leaves 4');
  w.reply = record({ judgeOn: true, cap: 5 }, w.clock);
  act(rulesP(w), 'cards at once-up').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'cap', args: ['5'], repo: 'sample' } }], 'the next raise is from 4, not 3');
});

// Bug: a role's one list was the pack's models.allowed, so a CLI the loop's host has (OpenCode) was offered nowhere
// unless its models were written into the pack, and the role's CLI was guessed from the model's name. Each role is a
// CLI the host has, then one of the models that CLI lists there (a typed name for one that lists none); a role the host
// can no longer start says so.
test('Rules: each role picks a CLI the host has, then one of its models; picking a CLI refills the list, and both are sent and shown in force', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  const row = (k) => ruled(w).querySelector(`[data-rule="${k}"]`);
  const values = (k, a) => Array.from(act(row(k), a).options, (o) => o.value);
  const set = (k, a, v) => { const s = act(row(k), a); s.value = v; s.dispatchEvent(new w.Event('change')); };
  assert.deepEqual(values('reviewer', 'reviewer-cli'), ['', 'claude', 'codex', 'opencode'], 'the CLIs installed on the host');
  assert.equal(act(row('reviewer'), 'reviewer-model').disabled, true, 'at the default, no model is picked');
  set('reviewer', 'reviewer-cli', 'opencode');
  await settle();
  assert.deepEqual(w.posts, [], 'a CLI alone sends nothing');
  assert.deepEqual(values('reviewer', 'reviewer-model'), ['', ...CLIS.opencode.models, '*other'], 'the models OpenCode lists, then Other…');
  assert.deepEqual(values('reviewer', 'reviewer-effort'), ['', ...CLIS.opencode.efforts], 'the efforts OpenCode takes');
  set('reviewer', 'reviewer-cli', 'codex');
  assert.deepEqual(values('reviewer', 'reviewer-model'), ['', ...CLIS.codex.models, '*other'], 'another CLI refills the list with its own models');
  w.reply = record({ reviewer: { cli: 'codex', model: 'gpt-6.1-terra', effort: null } });
  set('reviewer', 'reviewer-model', 'gpt-6.1-terra');
  act(row('reviewer'), 'reviewer-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'reviewer', args: ['codex', 'gpt-6.1-terra'], repo: 'sample' } }], 'the CLI and the model are sent');
  assert.deepEqual([act(row('reviewer'), 'reviewer-cli').value, act(row('reviewer'), 'reviewer-model').value], ['codex', 'gpt-6.1-terra'], 'the host\'s record shows at once');
  assert.match(row('reviewer').textContent, /codex gpt-6\.1-terra · /, 'in force');
  w.reply = record({ reviewer: { cli: 'codex', model: 'gpt-6.1-terra', effort: 'high' } });
  set('reviewer', 'reviewer-effort', 'high');
  act(row('reviewer'), 'reviewer-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'reviewer', args: ['codex', 'gpt-6.1-terra', 'high'], repo: 'sample' } }], 'an effort is sent with its CLI and model');
  // Claude Code lists no models: a name the pack does not list is typed in under Other…, and sent by Save.
  set('builder', 'builder-model', '*other');
  const typed = act(row('builder'), 'builder-model-other');
  typed.value = 'claude-sonnet-9-0[1m]'; typed.dispatchEvent(new w.Event('input'));
  act(row('builder'), 'builder-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['claude', 'claude-sonnet-9-0[1m]', 'high']]);
  // The OpenCode builder takes no effort.
  set('builder', 'builder-cli', 'opencode');
  assert.deepEqual(values('builder', 'builder-effort'), [''], 'the OpenCode builder is offered no effort');
  // A role set to a CLI the host no longer has: shown as set, marked not installed, and said to be unable to start.
  const gone = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.control.reviewer = { cli: 'opencode', model: 'prov/m-2', effort: null };
  d.panels.rules.data.modelSettings.reviewer = { ...clone(MODELS.reviewer), model: 'opencode:prov/m-2', agent: 'opencode', modelFrom: 'control',
    efforts: CLIS.opencode.efforts, clis: { claude: CLIS.claude, codex: CLIS.codex }, missing: 'opencode is not installed on this host (not on PATH)' };
  deliver(gone, d);
  const r = ruled(gone).querySelector('[data-rule="reviewer"]');
  assert.deepEqual([act(r, 'reviewer-cli').value, act(r, 'reviewer-cli').selectedOptions[0].textContent, act(r, 'reviewer-model').value], ['opencode', 'opencode (not installed)', 'prov/m-2']);
  assert.match(r.textContent, /cannot start: opencode is not installed on this host/);
  // Bug: a judge whose CLI is gone was shown as Default once the host answered another change (here, turning the judge
  // on), though the record still sets it: its CLI, not installed, is not the Codex reviewer's, so it stays set.
  const jg = boot({ tab: 'rules' });
  const dj = full();
  const jset = { cli: 'opencode', model: 'prov/m-2', effort: null };
  dj.panels.rules.data.control.judge = jset;
  dj.panels.rules.data.modelSettings.judge = { ...clone(MODELS.judge), model: 'opencode:prov/m-2', agent: 'opencode', modelFrom: 'control',
    efforts: CLIS.opencode.efforts, clis: { claude: CLIS.claude }, missing: 'opencode is not installed on this host (not on PATH)' };
  deliver(jg, dj);
  const jr = () => ruled(jg).querySelector('[data-rule="judge"]');
  jg.reply = record({ judgeOn: true, judge: jset });
  act(jr(), 'judge-on').click();
  await settle();
  assert.deepEqual(jg.posts.splice(0).map((p) => p.body.args), [['on']]);
  assert.deepEqual([act(jr(), 'judge-cli').value, act(jr(), 'judge-model').value], ['opencode', 'prov/m-2'], 'the judge is still shown as set');
  assert.match(jr().textContent, /cannot start: opencode is not installed on this host/);
});

// Bug: a model typed in for a CLI that lists none was put back to the saved one by the next snapshot (a card landing
// redraws the tab), so the owner lost what they were typing.
test('Rules: a model being typed in under Other… stays in its field across a snapshot, and is sent by Save', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  const m = act(ruled(w), 'builder-model'); m.value = '*other'; m.dispatchEvent(new w.Event('change'));
  const typed = () => act(ruled(w), 'builder-model-other');
  typed().value = 'claude-sonn';
  typed().dispatchEvent(new w.Event('input'));
  const d = full();
  d.panels.rules.data.queue.shift();
  next(w, d);
  assert.equal(typed().value, 'claude-sonn', 'the snapshot keeps what is typed');
  assert.deepEqual(w.posts, [], 'nothing is sent while it is typed');
  typed().value = 'claude-sonnet-9-9';
  typed().dispatchEvent(new w.Event('input'));
  act(ruled(w), 'builder-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['claude', 'claude-sonnet-9-9', 'high']]);
});

// Bug: a model typed in for one project was shown in place of the next project's saved model when another was picked.
test('Rules: a model picked and not saved for one project is not shown for another project picked, and is still there back on the first', () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  const other = { ...clone(d.panels.rules.data), repo: 'widgetshop' };
  other.control = { ...other.control, model: { cli: 'claude', model: 'claude-fable-5-2', effort: 'high' } };
  other.modelSettings.builder.model = 'claude-fable-5-2';
  Object.assign(d.panels.rules.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: other } });
  d.panels.machine.data.repos = ['sample', 'widgetshop'];
  deliver(w, d);
  const model = () => act(rulesP(w), 'builder-model');
  model().value = 'claude-haiku-5-5'; model().dispatchEvent(new w.Event('change'));
  pickProject(w, 'widgetshop');
  assert.equal(model().value, 'claude-fable-5-2', 'the other project shows its own saved model');
  assert.equal(act(rulesP(w), 'builder-save').hidden, true, 'and nothing unsaved');
  pickProject(w, 'sample');
  assert.equal(model().value, 'claude-haiku-5-5', 'the first project\'s pick is kept');
  assert.equal(act(rulesP(w), 'builder-save').hidden, false);
  assert.deepEqual(w.posts, [], 'nothing is sent');
});

test('Rules: a refused change puts each setting back to its old value, with the refusal beside it', async () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.accounts = ['first', 'second'];
  deliver(w, d);
  const pressed = (a) => () => act(rulesP(w), a).getAttribute('aria-pressed');
  const value = (a) => () => act(rulesP(w), a).value;
  const choose = (a, v) => () => { const s = act(rulesP(w), a); s.value = v; s.dispatchEvent(new w.Event('change')); };
  const CASES = [
    ['build', () => { act(rulesP(w), 'rule-P2').click(); act(rulesP(w), 'rule-P2').click(); }, pressed('rule-P2'), 'true', 'false'],
    ['never', () => { const f = act(rulesP(w), 'area-name'); f.value = 'tenant'; f.dispatchEvent(new w.Event('input')); act(rulesP(w), 'area-off').click(); },
      () => Array.from(ruled(w).querySelectorAll('[data-rule="never"] .chip'), (c) => c.textContent).join(' '), 'area:infra', 'area:infra area:tenant'],
    ['cap', () => act(rulesP(w), 'cards at once-up').click(), () => act(rulesP(w), 'cards at once-up').previousSibling.textContent, '3', '4'],
    ['guard', () => act(rulesP(w), 'guard-off').click(), pressed('guard-off'), 'false', 'true'],
    // A refused Builder, Reviewer or Judge model keeps the pick, unsaved: dashboard-view.rules-roles.test.mjs.
    ['judge', () => act(rulesP(w), 'judge-on').click(), pressed('judge-on'), 'false', 'true'],
    ['account', choose('account', 'second'), value('account'), '', 'second'],
    ['review-account', choose('review-account', 'first'), value('review-account'), '', 'first'],
    ['start', () => act(rulesP(w), 'start-held').click(), pressed('start-held'), 'false', 'true'],
  ];
  for (const [row, change, shown, old, now] of CASES) {
    let refuse;
    w.reply = { ok: false, status: 409, text: () => new Promise((r) => { refuse = r; }) };
    assert.equal(shown(), old, `${row}: before`);
    change();
    assert.equal(shown(), now, `${row}: the new value shows while the change is out`);
    await settle();
    assert.equal(w.posts.splice(0).length, 1, `${row}: sent once`);
    refuse('conveyor: the record is locked');
    await settle();
    assert.equal(shown(), old, `${row}: refused, the old value is back`);
    const said = rulesP(w).querySelectorAll('.rules-refused');
    assert.equal(said.length, 1, `${row}: one refusal, the last one`);
    assert.equal(said[0].closest('.rules-row').dataset.rule, row, `${row}: the refusal is beside its control`);
    assert.equal(said[0].textContent, 'Not saved: conveyor: the record is locked');
    assert.equal(said[0].getAttribute('role'), 'alert');
  }
  // A host that does not answer puts it back too; a change the host takes clears the refusal.
  w.reply = { ok: true, status: 200, text: () => Promise.reject(new Error('gone')) };
  act(rulesP(w), 'judge-on').click();
  await settle();
  assert.equal(pressed('judge-on')(), 'false');
  assert.equal(ruled(w).querySelector('[data-rule="judge"] .rules-refused').textContent, 'Not saved: the host did not answer');
  w.reply = record({ judgeOn: true });
  act(rulesP(w), 'judge-on').click();
  await settle();
  assert.equal(pressed('judge-on')(), 'true');
  assert.equal(rulesP(w).querySelectorAll('.rules-refused').length, 0, 'the change taken clears the refusal');
});

// A feed that arrived while the raise was out holds an older cap; the refusal puts back the 3 shown before the raise.
test('Rules: a refused change shows the value from before it, not one a feed brought while it was out', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  const cap = () => act(rulesP(w), 'cards at once-up').previousSibling.textContent;
  let refuse;
  w.reply = { ok: false, status: 409, text: () => new Promise((r) => { refuse = r; }) };
  act(rulesP(w), 'cards at once-up').click();
  assert.equal(cap(), '4');
  await settle();
  const older = full(T0 - 5000); older.panels.rules.data.control.cap = 2;
  next(w, older);
  assert.equal(cap(), '4', 'the raise still shows while it is out');
  refuse('conveyor: the record is locked');
  await settle();
  assert.equal(cap(), '3', 'refused: the value before the raise, not the older feed\'s 2');
});

// Judge On saved for one project, another picked and this one picked again before a feed has it: still On.
test('Rules: a saved setting keeps its new value through picking another project and back', async () => {
  const w = boot({ tab: 'rules' });
  const two = (now) => {
    const d = full(now);
    Object.assign(d.panels.rules.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: { ...clone(d.panels.rules.data), repo: 'widgetshop' } } });
    d.panels.machine.data.repos = ['sample', 'widgetshop'];
    return d;
  };
  const pick = (repo) => pickProject(w, repo);
  const judge = () => ['judge-on', 'judge-off'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed')).join(' ');
  deliver(w, two());
  let answer;
  w.reply = { ...record({}), text: () => new Promise((r) => { answer = r; }) };
  act(rulesP(w), 'judge-on').click();
  await settle();
  w.posts.splice(0);
  pick('widgetshop');
  answer(JSON.stringify({ ...CONTROL, judgeOn: true }));
  await settle();
  assert.equal(judge(), 'false true', 'the other project shows its own Off');
  pick('sample');
  assert.equal(judge(), 'true false', 'an answer that came while another project was drawn is kept');
  pick('widgetshop'); pick('sample');
  assert.equal(judge(), 'true false', 'picked again before a feed has it: still On');
  next(w, two(T0 - 1000 + 20000));
  assert.equal(judge(), 'true false', 'a feed older than the change leaves On');
  const newer = two(T0 + 20000); newer.panels.rules.data.control.judgeOn = true;
  next(w, newer);
  pick('widgetshop');
  next(w, two(T0 - 3000));
  pick('sample');
  assert.equal(judge(), 'true false', 'a feed older than the change, arriving while another project is drawn, leaves On');
});

test('Rules: the guard warning shows only when the forecast says the guard pauses the loop before the queue ends', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  assert.equal(produced(w).querySelector('.rules-warn'), null, 'the queue ends before the guard: no warning');
  const crossing = full();
  crossing.panels.rules.data.forecast = { ...crossing.panels.rules.data.forecast, reading: 89, pausesAt: 22 };
  next(w, crossing);
  assert.equal(produced(w).querySelector('.rules-warn').textContent, 'Conveyor will pause when the weekly limit reaches 90%, before it picks #22 Last.');
  const off = clone(crossing);
  off.panels.rules.data.forecast = { ...off.panels.rules.data.forecast, guard: null, pausesAt: null };
  next(w, off);
  assert.equal(produced(w).querySelector('.rules-warn'), null, 'no guard: no warning');
  const none = clone(crossing);
  none.panels.rules.data.forecast = null;
  next(w, none);
  assert.equal(produced(w).querySelector('.rules-warn'), null, 'no forecast: no warning');
  assert.equal(figure(w, 'ready'), '3', 'the queue is still counted');
});
