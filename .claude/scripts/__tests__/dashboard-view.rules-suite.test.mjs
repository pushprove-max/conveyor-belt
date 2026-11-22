// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Release suite runs on": the control record's suiteMachine, the machine a release's whole suite
// runs on (this machine, a Namespace Devbox or a Linux box over ssh), sent as `control suite-machine <kind ...>`, and
// the Check button, which sends `suite-machine-check` and shows each line of its answer. Shared setup:
// dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, ruled, rulesP, css, heldP, pickProject } from './dashboard-view.helpers.mjs';

const DEVBOX = { kind: 'devbox', size: '4x8', tag: 'conveyor-suite-sample', idleStop: '15m' };
const SSH = { kind: 'ssh', target: 'me@box.example.com', dir: '~/conveyor-suite' };
// What `suite-machine check --json` prints for a devbox: its one need is the Namespace login.
const login = (ok) => ({ kind: 'devbox', name: 'Namespace Devbox', ok, cpus: null, slots: null,
  needs: [{ need: 'Namespace login', ok, detail: ok ? 'logged in' : 'Not logged in to Namespace' }] });
// The Rules part with the record's suiteMachine (undefined: none, so this machine) and the machine's test slots as given.
function data(machine, slots = 4) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, suiteAtOnce: 2 };
  delete r.control.suiteMachine;
  if (machine !== undefined) r.control.suiteMachine = machine;
  r.cores = { reserved: [], slots, unavailable: null };
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="suite"]');
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };
const reply = (rec) => ({ ok: true, status: 200, text: () => Promise.resolve(typeof rec === 'string' ? rec : JSON.stringify(rec)) });
const radios = (w) => Array.from(row(w).querySelectorAll('input[type="radio"]'), (i) => [i.parentElement.querySelector('strong').textContent, i.checked]);
// A devbox saved is checked when it is shown (the login is read), then the row is as the check left it.
async function devboxShown(w, ok, record = DEVBOX) {
  w.reply = reply(login(ok));
  next(w, data(record));
  await settle();
  w.posts.length = 0;
}

// Bugs this guards: the owner could not choose where a release's suite runs from the Board; the row sat outside
// Capacity; a choice showed the wrong machine's fields or another's texts; a choice sent another kind.
test('Rules: Release suite runs on is in Capacity with three choices, the chosen one\'s texts, and a choice sends its kind', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  assert.equal(row(w).closest('[data-set]').dataset.set, 'capacity', 'the row is in the Capacity group');
  assert.match(row(w).querySelector('.rules-key').textContent, /Release suite runs on.*the machine a release's full suite runs on/);
  assert.deepEqual(radios(w), [['This machine', true], ['Namespace Devbox', false], ['Linux box over ssh', false]]);
  const t = row(w).textContent;
  assert.match(t, /The build machine, 4 test slots\. The default\./);
  assert.match(t, /A devbox leased for the run, given back after it\./);
  assert.match(t, /Any Linux machine the build machine reaches with ssh\./);
  assert.match(t, /The suite runs here, as now\. Its test files share the 4 test slots with the cards\./);
  assert.equal(act(row(w), 'suite-check'), null, 'this machine has no box to check');
  assert.deepEqual(await sent(w, () => act(row(w), 'suite-devbox').click()),
    [{ action: 'suite-machine', args: ['devbox'], repo: 'sample' }, { action: 'suite-machine-check', args: [], repo: 'sample' }],
    'the choice is sent, and the devbox shown is checked to read the login');
  await devboxShown(w, true);
  assert.deepEqual(radios(w), [['This machine', false], ['Namespace Devbox', true], ['Linux box over ssh', false]]);
  assert.deepEqual(await sent(w, () => act(row(w), 'suite-use-local').click()), [{ action: 'suite-machine', args: ['local'], repo: 'sample' }],
    'the Use this machine button, not the radio, sends local');
});

// Bug this guards: the machine choice sent its change with no Undo of the value it replaced, so the Undo of the change
// before it, or none, stayed; and the Undo, once pressed, left no Undo of the value it put back.
test('Rules: a change of the suite machine is undone by putting the saved machine back, and that has its own Undo', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(SSH));
  await sent(w, () => act(row(w), 'suite-local').click());  // This machine, on an ssh rule
  const undo = () => rulesP(w).querySelector('[data-act="undo"]');
  assert.ok(undo(), 'the change has an Undo');
  next(w, data(undefined));  // the record now holds this machine
  assert.deepEqual(await sent(w, () => undo().click()), [{ action: 'suite-machine', args: ['ssh', 'me@box.example.com', '--dir', '~/conveyor-suite'], repo: 'sample' }],
    'Undo puts the saved ssh box back');
  next(w, data(SSH));
  assert.ok(undo(), 'the Undo of the machine put back is itself undoable');
  assert.deepEqual(await sent(w, () => undo().click()), [{ action: 'suite-machine', args: ['local'], repo: 'sample' }], 'its Undo puts this machine back');
});

// Bug this guards: the choices were buttons with no shown selection and no arrow-key move; a native radio group has both.
test('Rules: the machine choices are one native radio group', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  const inputs = Array.from(row(w).querySelectorAll('input[type="radio"]'));
  assert.equal(inputs.length, 3);
  assert.equal(new Set(inputs.map((i) => i.name)).size, 1, 'one name: the browser moves between them with the arrow keys');
  assert.equal(row(w).querySelector('[role="radiogroup"]').getAttribute('aria-label'), 'Release suite runs on');
});

// Bugs this guards: the devbox choice lacked a field or text the owner asked for; the size menu sent another size.
test('Rules: Release suite runs on, on a Namespace Devbox, shows its login, size, after-run choice, box and tools', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  await devboxShown(w, true);
  const t = row(w).textContent;
  assert.match(t, /Namespace login\s*logged in/);
  assert.match(t, /Size/);
  assert.match(t, /4 CPUs/, 'the meta gives the size\'s CPUs');
  assert.match(t, /After a run\s*Keep it, stop it after 15 min idle/);
  assert.match(t, /Box\s*Namespace Devbox 4x8, reused by its tag conveyor-suite-sample, set-up time not kept/, 'a record with no setupAt says so, and invents no time');
  assert.match(t, /Tools\s*From \.conveyor\/test-machine\.sh\. It runs again only when the script changes\./);
  assert.ok(act(row(w), 'suite-check') && !act(row(w), 'suite-check').disabled, 'Check the box is on with the login there');
  assert.match(act(row(w), 'suite-check').textContent, /Check the box/);
  const size = act(row(w), 'suite-size');
  assert.deepEqual(Array.from(size.options, (o) => o.value), ['2x4', '4x8', '8x16', '16x32']);
  size.value = '8x16';
  const posts = await sent(w, () => size.dispatchEvent(new w.Event('change')));
  assert.deepEqual(posts, [{ action: 'suite-machine', args: ['devbox', '--size', '8x16'], repo: 'sample' }, { action: 'suite-machine-check', args: [], repo: 'sample' }],
    'a new size is saved, then is a new rule: the box is read again (a size that is never checked fails here)');
});

// Bug this guards: the Box line left out when the devbox was set up, which the owner asked it to show.
test('Rules: Release suite runs on, on a Namespace Devbox, the Box line shows when it was set up', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  const at = '2026-11-20T15:04:00Z';
  await devboxShown(w, true, { ...DEVBOX, setupAt: at });
  const t = row(w).textContent;
  assert.match(t, /Box\s*Namespace Devbox 4x8, reused by its tag conveyor-suite-sample, set up (\d|[A-Z])/, 'a time follows "set up"');
  assert.doesNotMatch(t, /set-up time not kept/);
});

// Bug this guards: Undo of "Use this machine" on a devbox that had been set up sent only its size, so the saved rule lost
// its setupAt and the Box row said "set-up time not kept".
test('Rules: Undo of a change from a set-up devbox sends its set-up time back with it', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  const at = '2026-11-20T15:04:00Z';
  await devboxShown(w, true, { ...DEVBOX, setupAt: at });
  await sent(w, () => act(row(w), 'suite-use-local').click());
  next(w, data(undefined));  // the record now holds this machine
  assert.deepEqual(await sent(w, () => rulesP(w).querySelector('[data-act="undo"]').click()),
    [{ action: 'suite-machine', args: ['devbox', '--size', '4x8', '--setup-at', at], repo: 'sample' }, { action: 'suite-machine-check', args: [], repo: 'sample' }],
    'Undo puts the devbox back with its set-up time');
});

// Bug this guards: a Linux box over ssh could not be set from the Board, or was sent with a target the engine refuses.
test('Rules: Release suite runs on, on a Linux box over ssh, takes a target and a folder and sends them', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  assert.deepEqual(await sent(w, () => act(row(w), 'suite-ssh').click()), [], 'a box with no target is not sent');
  assert.deepEqual(radios(w), [['This machine', false], ['Namespace Devbox', false], ['Linux box over ssh', true]]);
  const target = act(row(w), 'suite-ssh-target'), dir = act(row(w), 'suite-ssh-dir');
  assert.match(row(w).textContent, /ssh target/);
  assert.match(row(w).textContent, /Folder there/);
  assert.ok(act(row(w), 'suite-ssh-use').disabled, 'no target, nothing to use');
  target.value = '-oProxyCommand=id'; target.dispatchEvent(new w.Event('input'));
  assert.ok(act(row(w), 'suite-ssh-use').disabled, 'an ssh option is not a target');
  target.value = 'me@box.example.com'; target.dispatchEvent(new w.Event('input'));
  dir.value = 'relative'; dir.dispatchEvent(new w.Event('input'));
  assert.ok(act(row(w), 'suite-ssh-use').disabled, 'a folder that is not ~, under ~/ or a full path is not sent');
  dir.value = '~/suite'; dir.dispatchEvent(new w.Event('input'));
  assert.deepEqual(await sent(w, () => act(row(w), 'suite-ssh-use').click()),
    [{ action: 'suite-machine', args: ['ssh', 'me@box.example.com', '--dir', '~/suite'], repo: 'sample' }]);
  next(w, data(SSH));
  assert.equal(act(row(w), 'suite-ssh-target').value, 'me@box.example.com', 'the record\'s target is shown');
  assert.equal(act(row(w), 'suite-ssh-dir').value, '~/conveyor-suite');
});

// Bugs this guards: a devbox with no Namespace login offered Check, which can only fail, and did not say the command
// that logs in; the row took the login as present before any check read it; a login made in a terminal after a check
// found none turned Check on only after the page was loaded again.
test('Rules: Release suite runs on, with no Namespace login, shows devbox login, keeps Check off, and turns it on once the login is there', async () => {
  const w = boot({ tab: 'rules' });
  w.reply = reply(login(false));
  assert.deepEqual(await sent(w, () => deliver(w, data(DEVBOX))), [{ action: 'suite-machine-check', args: [], repo: 'sample' }],
    'a saved devbox is checked when the row is shown, to read the login');
  assert.match(row(w).textContent, /Namespace login\s*not logged in/);
  assert.match(row(w).textContent, /terminal on the build machine/);
  assert.equal(row(w).querySelector('code').textContent, 'devbox login');
  assert.ok(act(row(w), 'suite-check').disabled, 'Check the box is off until the login is there');
  w.reply = reply(login(true));
  assert.deepEqual(await sent(w, () => next(w, data(DEVBOX))), [], 'a refresh right after the check does not ask again');
  w.clock += 16000;
  assert.deepEqual(await sent(w, () => next(w, data(DEVBOX))), [{ action: 'suite-machine-check', args: [], repo: 'sample' }],
    'a refresh a while later reads the login again');
  assert.equal(row(w).querySelector('code'), null, 'a logged-in devbox shows no login command');
  assert.ok(!act(row(w), 'suite-check').disabled);
  assert.deepEqual(await sent(w, () => { w.clock += 60000; next(w, data(DEVBOX)); }), [], 'a login that is there is not read again by itself');
});

// Bugs this guards: the login retry of a readAt-only refresh drew the tab when it started and when it ended, replacing
// the open Group by select (issue 294) for a login that was still missing. A changed answer is still drawn. The same
// refresh (the live feed sends one every few seconds) also returned before the login retry, so Check the box stayed
// off after the owner logged in to Namespace.
test('Rules: the login retry of a readAt-only refresh keeps the open Group by select while the login stays missing', async () => {
  const w = boot({ tab: 'rules' });
  await devboxShown(w, false);
  const by = act(heldP(w), 'held-by');
  assert.ok(by, 'the Group by select is shown');
  by.focus();
  w.clock += 16000;
  const d = data(DEVBOX);
  d.panels.rules.data.readAt = '2026-11-22T00:00:30Z';
  assert.deepEqual(await sent(w, () => next(w, d)), [{ action: 'suite-machine-check', args: [], repo: 'sample' }],
    'the login is read again');
  assert.equal(act(heldP(w), 'held-by'), by, 'the select the user has open is the same node');
  assert.equal(w.document.activeElement, by);
  w.reply = reply(login(true));
  w.clock += 16000;
  const e = data(DEVBOX);
  e.panels.rules.data.readAt = '2026-11-22T00:01:00Z';
  assert.deepEqual(await sent(w, () => next(w, e)), [{ action: 'suite-machine-check', args: [], repo: 'sample' }],
    'a refresh with only a new readAt reads the login again');
  assert.ok(!act(row(w), 'suite-check').disabled, 'a login now there is drawn: Check the box is on');
});

// Bug this guards: a login retry that is out draws Check the box off for any draw in it (here, picking another project
// with a saved ssh box); when its answer was the one already shown, nothing drew again, so the ssh box's Check stayed off.
test('Rules: Check the box is on for another project picked while a login retry is out, whose answer is unchanged', async () => {
  const w = boot({ tab: 'rules' });
  const two = (readAt) => {
    const d = data(DEVBOX), r = d.panels.rules.data, names = ['sample', 'widgetshop'];
    r.readAt = readAt;
    d.panels.machine.data.repos = names;
    Object.assign(r, { repos: names, others: { widgetshop: { ...r, repo: 'widgetshop', control: { ...r.control, suiteMachine: SSH } } } });
    return d;
  };
  await devboxShown(w, false);
  next(w, two('2026-11-22T00:00:00Z'));
  await settle();
  w.posts.length = 0;
  let answer = null;
  w.reply = { ok: true, status: 200, text: () => new Promise((r) => { answer = () => r(JSON.stringify(login(false))); }) };
  w.clock += 16000;
  assert.deepEqual(await sent(w, () => next(w, two('2026-11-22T00:00:30Z'))), [{ action: 'suite-machine-check', args: [], repo: 'sample' }], 'the retry is out');
  pickProject(w, 'widgetshop');
  assert.ok(act(row(w), 'suite-check').disabled, 'the ssh box\'s Check is off while the retry is out');
  answer();
  await settle();
  assert.ok(!act(row(w), 'suite-check').disabled, 'the retry has ended: the ssh box\'s Check is on');
});

// Bug this guards: Check on a saved ssh box stayed on while its target was being edited, so it reported the saved box
// as the edited one.
test('Rules: Check the box is off while an ssh target is edited and not yet saved', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(SSH));
  assert.ok(!act(row(w), 'suite-check').disabled, 'the saved box can be checked');
  const target = act(row(w), 'suite-ssh-target');
  target.value = 'other@box.example.com'; target.dispatchEvent(new w.Event('input'));
  assert.ok(act(row(w), 'suite-check').disabled, 'Check is off the moment the target is edited');
  next(w, data(SSH));
  assert.ok(act(row(w), 'suite-check').disabled, 'and stays off through a refresh, until Use this box saves it');
});

// Bugs this guards: Check sent another action; a line of the check lost its chip; a missing tool offered no way to set
// it up, or one for something test-machine.sh cannot install.
test('Rules: Check the box shows each line with ok or missing, and Set up now for a missing tool', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(SSH));
  w.reply = reply({ kind: 'ssh', name: 'box.example.com', ok: false, cpus: 4, slots: 3, needs: [
    { need: 'ssh', ok: true, detail: 'me@box.example.com answers' }, { need: 'bash 5.1+', ok: true, detail: 'bash 5.2' },
    { need: 'jq', ok: false, detail: 'not installed' }, { need: 'git', ok: true, detail: 'installed' },
    { need: 'test slots', ok: false, detail: '4 CPUs, its test slots cannot be read' }] });
  assert.deepEqual(await sent(w, () => act(row(w), 'suite-check').click()), [{ action: 'suite-machine-check', args: [], repo: 'sample' }]);
  const chips = Array.from(row(w).querySelectorAll('.rules-suite-check'), (li) => li.querySelector('.chip').textContent.trim());
  assert.deepEqual(chips, ['ok', 'ok', 'missing', 'ok', 'missing']);
  assert.match(row(w).querySelectorAll('.rules-suite-check')[2].textContent, /jq: not installed/);
  const set = row(w).querySelectorAll('[data-act^="suite-setup-"]');
  assert.deepEqual(Array.from(set, (b) => b.dataset.act), ['suite-setup-jq'], 'only the missing tool offers Set up now');
  assert.equal(set[0].textContent, 'Set up now');
  assert.match(row(w).textContent, /Runs test-machine\.sh there\. Asks the owner first\./);
  // No action runs test-machine.sh yet (the issue names two actions), so the button is shown and stays off.
  assert.ok(set[0].disabled, 'Set up now cannot send an action none takes');
  assert.match(ruled(w).querySelector('[data-rule="atonce"]').textContent, /Capped at the suite machine's slots: 3 on the box\./, 'the check\'s test slots cap the files at once');
});

// Bug this guards: a check the host refused showed nothing, so the owner saw no reason.
test('Rules: Check the box shows why the host did not run the check', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(SSH));
  w.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: the control record cannot be read') };
  await sent(w, () => act(row(w), 'suite-check').click());
  assert.match(row(w).querySelector('.rules-refused').textContent, /The check did not run: conveyor: the control record cannot be read/);
});

// Bug this guards: the Test files at once row said the suite ran at this machine's slots when it runs on a devbox.
test('Rules: Test files at once names the suite machine\'s slots', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(DEVBOX, 2));
  assert.match(ruled(w).querySelector('[data-rule="atonce"]').textContent, /Capped at the suite machine's slots: 4 on the devbox\./, 'the size\'s CPUs, 4 for 4x8');
  next(w, data(undefined, 1));
  assert.doesNotMatch(ruled(w).querySelector('[data-rule="atonce"]').textContent, /suite machine's slots/);
});

// Bug this guards: the chosen machine's description kept --muted on the --accent fill, 1.17:1 in the light theme and
// 1.04:1 in the dark. A stylesheet test (jsdom draws no layout): the description's class in the rendered choice is the
// one the checked-choice rule hands the choice's own text color, which is --on-accent on the --accent fill.
test('Rules: the chosen suite machine\'s description is drawn in the choice\'s own text color', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  const what = row(w).querySelector('input[type="radio"]').parentElement.lastElementChild;
  assert.equal(what.className, 'board-from');
  assert.match(css, /\.rules-suite-kind:has\(input:checked\) \{[^}]*background: var\(--accent\); color: var\(--on-accent\);/);
  assert.match(css, /\.rules-suite-kind:has\(input:checked\) \.board-from \{ color: inherit; \}/);
});
