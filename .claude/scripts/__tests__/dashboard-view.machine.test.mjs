// SPDX-License-Identifier: Apache-2.0
// The dashboard page with the machine's one Conveyor over two projects: the machine head on every tab, a section a
// project, each Foreman, and the filter and sort by project on every list. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, clone, boot, deliver, refresh, settle, panel, full, tabBtn, act, METRIC_TOTALS, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// Bug: with two projects on one machine the page showed no machine at all: not whether the machine was paused, not
// its cap nor the slots both projects hold of it, and its pause could only be set by hand in the host file; a mixed
// list could not be cut to one project, and a group's Foreman was nowhere on the page.
const W = 'https://github.com/example/WidgetShop/issues';
const wi = (issue, title, over = {}) => ({ repo: 'widgetshop', card: null, issue, title, url: `${W}/${issue}`, ...over });
// sample (2 of its 3 slots) and widgetshop (5 of its 5) on one machine capped at 10, under one Foreman group.
function two() {
  const d = full(), m = d.panels.machine.data;
  Object.assign(m, { cap: 10, used: 7, todayUsd: 6.5, repos: ['sample', 'widgetshop'] });
  m.projects.push({ repo: 'widgetshop', state: 'running', reason: null, loop: true, mode: 'run', cap: 5, used: 5,
    needs: [wi(41, 'Widget blocked', { card: 'c7-41' })], belt: [wi(5, 'Widget build', { card: 'c4-5', step: 'build' })], queue: [wi(46, 'Widget next')], held: null,
    order: [], rules: { P0: true, P1: true, P2: false, P3: true, followups: false, never: [] }, models: null, landedToday: 1, todayUsd: 2.25 });
  m.foremen = [{ projects: ['sample', 'widgetshop'], group: true, held: true, since: iso(T0 - 3600000), lastWakeAt: null, waiting: [] }];
  // The second project's rows in the lists of every project; its queue row comes first, so a sort by project moves it.
  d.panels.needs.data.cards.blocked.push(wi(41, 'Widget blocked', { card: 'c7-41', reason: 'tests failed', since: iso(T0 - 600000) }));
  // The belt holds one card of each project already (full()); a second of widgetshop's makes it 3 cards of 8 slots.
  d.panels.belt.data.cards.push({ ...clone(d.panels.belt.data.cards[0]), ...wi(6, 'Widget build', { card: 'c4-6' }) });
  Object.assign(d.panels.belt.data, { cap: 8, byRepo: { sample: { cap: 3 }, widgetshop: { cap: 5 } } });
  d.panels.queue.data.next.unshift(wi(46, 'Widget next', { priority: 'P1', followup: false, retried: false }));
  d.panels.queue.data.byRepo = { sample: { held: 2 }, widgetshop: { held: 4 } };
  const rec = d.panels.metrics.data.records[0];
  d.panels.metrics.data.records.push({ ...clone(rec), repo: 'widgetshop', week: { ...METRIC_TOTALS, cards: 3, landed: 3, blocked: 0 } });
  // widgetshop comes first in the host's order here, so a sort by project moves its row.
  d.panels.metrics.data.compare = { projects: [{ repo: 'widgetshop', landed: 3, leadSec: 3600, usd: null }, { repo: 'sample', landed: 7, leadSec: 7110, usd: 14 }],
    machine: { landed: 10, leadSec: 5760, usd: null } };
  const wboard = { ...clone(d.panels.board.data), repo: 'widgetshop' };
  Object.assign(d.panels.board.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: wboard } });
  return d;
}
// Bug: GitHub did not list one project's issues, and the page filtered to the other, whose queue was read, still said
// the queue was unknown: the part held only the queue of all.
test('queue: filtered to a project whose issues were listed, its queue shows while another project\'s is unknown', async () => {
  const d = two(), q = d.panels.queue.data;
  const mine = q.next.filter((x) => x.repo === 'widgetshop');
  const unread = { next: null, held: null, awaitingDeploy: null, waiting: null };
  Object.assign(q, unread, { issuesError: 'GitHub did not list the open issues on devbox.', byRepo: {
    sample: { ...unread, issuesError: 'GitHub did not list the open issues of sample on devbox.' },
    widgetshop: { next: mine, held: 4, awaitingDeploy: [], waiting: [], issuesError: null } } });
  const w = boot({ query: '?project=widgetshop' });
  deliver(w, d);
  await settle();
  assert.deepEqual(tagsOf(w, 'queue'), ['widgetshop'], 'the read project\'s queue row');
  assert.match(panel(w, 'queue').textContent, /Widget next.*Holds keep 4 issues back: see Held\./);
  const other = boot({ query: '?project=sample' });
  deliver(other, d);
  await settle();
  assert.match(panel(other, 'queue').textContent, /did not list the open issues of sample on devbox/, 'the unread project says so, by name');
  const all = boot({});
  deliver(all, d);
  await settle();
  assert.match(panel(all, 'queue').textContent, /did not list the open issues on devbox/, 'every project: the queue of all stays unknown');
});

const head = (w) => w.document.getElementById('machine-head');
const said = (el) => el.textContent.replace(/\s+/g, ' ');
const sections = (w) => Array.from(panel(w, 'machine').querySelectorAll('.project'));
const section = (w, repo) => sections(w).find((s) => s.dataset.project === repo);
const tagsOf = (w, id) => Array.from(panel(w, id).querySelectorAll('.rows .project-tag'), (t) => t.textContent);
const choose = (w, el, value) => { el.value = value; el.dispatchEvent(new w.Event('change')); };
// A panel that shows one project names it in its heading ("Board: widgetshop"); Show in the machine head picks it.
const heading = (w, id) => panel(w, id).querySelector('.panel-title').textContent;

test('the machine: one machine head on every tab, with its state, the slots both projects hold of the machine cap, and today\'s cost', () => {
  const w = boot();
  assert.equal(head(w).hidden, true, 'nothing to show before the machine is read');
  deliver(w, two());
  for (const t of ['overview', 'belt3d', 'control', 'rules']) {
    tabBtn(w, t).click();
    assert.equal(w.document.querySelectorAll('.machine').length, 1, `one machine head on ${t}`);
    assert.equal(head(w).hidden, false, `shown on ${t}`);
    assert.match(said(head(w)), /Build machine buildhost.*Running.*7 of 10 cards at once.*\$6\.50 today, every project/, `the machine's figures on ${t}`);
  }
  assert.equal(head(w).dataset.state, 'running');
  // A machine with no cap says so, never "of null"; a machine that could not be read at all shows no head.
  const none = two(); none.panels.machine.data.cap = null;
  const again = boot(); deliver(again, none);
  assert.match(said(head(again)), /7 cards at once, no limit for the machine/);
  const bad = two(); bad.panels.machine = { error: 'buildhost did not answer', data: null };
  const down = boot(); deliver(down, bad);
  assert.equal(head(down).hidden, true);
});

test('the machine: its one control pauses or resumes the whole machine and names no project', async () => {
  const w = boot();
  deliver(w, two());
  assert.equal(act(head(w), 'machine-resume'), null);
  w.reply = { ok: true, status: 200, text: () => Promise.resolve('conveyor: the machine\'s Conveyor is paused') };
  act(head(w), 'machine-pause').click();
  await settle(); await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'machine', body: { action: 'pause' } }], 'a machine action is its own control: no project, no arguments');
  // Issue 407: one word for the wait ("in about a minute"), and Undo on the line, as a pause is easily undone.
  assert.equal(head(w).querySelector('.machine-note').textContent, 'Paused every project. The head shows it in about a minute. Undo', 'the build machine\'s reply only when it failed (issue 415)');
  assert.equal(act(head(w), 'machine-pause'), null, 'the button gives way to the line while the change waits for the loop');
  act(head(w), 'undo').click();
  await settle(); await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'machine', body: { action: 'resume' } }], 'Undo sends the opposite');
  // Issue 438: an Undo before the next reading put the machine back as read, yet its line kept an Undo and every later
  // running reading kept Pause hidden for good. The Undo that went through ends the wait: Pause is back, and stays.
  assert.ok(act(head(w), 'machine-pause'), 'Pause is back once the Undo went through');
  assert.equal(act(head(w), 'undo'), null, 'nothing is left to undo');
  refresh(w); deliver(w, two());
  assert.ok(act(head(w), 'machine-pause'), 'a later running reading still shows Pause');
  const paused = two(); paused.panels.machine.data.state = 'paused';
  const p = boot(); deliver(p, paused);
  assert.match(said(head(p)), /Paused/);
  assert.equal(act(head(p), 'machine-pause'), null, 'a paused machine offers its resume alone');
  act(head(p), 'machine-resume').click();
  await settle(); await settle();
  assert.deepEqual(p.posts.splice(0), [{ url: 'machine', body: { action: 'resume' } }]);
  // A refusal is said, and nothing reads as changed.
  const r = boot(); deliver(r, two());
  r.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: the host file does not read') };
  act(head(r), 'machine-pause').click();
  await settle(); await settle();
  assert.match(head(r).querySelector('.machine-note').textContent, /^Not changed: conveyor: the host file does not read/);
});

test('the machine: two projects are two sections, each with its own state, slots, lists, rules and models', () => {
  const w = boot({ tab: 'control' });
  deliver(w, two());
  assert.deepEqual(sections(w).map((s) => s.dataset.project), ['sample', 'widgetshop']);
  assert.equal(panel(w, 'machine').querySelector('.panel-count').textContent, '2');
  const p = said(section(w, 'sample')), s = said(section(w, 'widgetshop'));
  assert.match(p, /Running.*2 of 3 cards at once.*Needs you \(1\).*#12.*On the belt \(1\).*#57.*Queue \(1\).*#20.*Held \(1\).*#76.*Pinned order \(1\).*#21.*never area:infra.*Builder claude-opus-5-5 · high/);
  assert.match(s, /Running.*5 of 5 cards at once.*1 landed today.*\$2\.25 today.*Needs you \(1\).*#41.*On the belt \(1\).*#5.*Queue \(1\).*#46/);
  assert.match(s, /Held.*not listed/, 'a list GitHub did not give is said, never shown as none');
  assert.match(s, /Pinned order \(0\).*none.*Rules: builds P0, P1, P3, no follow-ups.*Models: not read/);
  assert.equal(section(w, 'widgetshop').querySelector('[data-list="Needs you"] a').href, `${W}/41`, 'an issue links to its own project\'s repository');
  // Its Board and its rules open for that project.
  act(section(w, 'widgetshop'), 'open-rules').click();
  assert.deepEqual([new URL(w.location.href).searchParams.get('tab'), new URL(w.location.href).searchParams.get('repo')], ['rules', 'widgetshop']);
});

// Bug it catches: a card id in the pinned order (`control order` takes card ids) was shown as an issue, "branch",
// with no id. It shows as its id, as text, beside the pinned issue.
test('the machine: a pinned card id shows as its id, as text, not as an issue', () => {
  const w = boot({ tab: 'control' });
  const d = two(), id = 'c20261101T000001-widgetshop-0';
  d.panels.machine.data.projects[1].order = [id, 46];
  deliver(w, d);
  const list = section(w, 'widgetshop').querySelector('[data-list="Pinned order"]');
  assert.equal(list.querySelector('code').textContent, id, `order [${id}, 46]: the card id is not shown as text`);
  assert.deepEqual(Array.from(list.querySelectorAll('.issue'), (a) => a.textContent), ['#46'], `order [${id}, 46]: only the issue is shown as an issue`);
});

// The judge decides which review findings count: the project list named each project's builder and reviewer but not
// whether a judge reads its reviews, nor on which model.
test('the machine: each project names its judge beside its builder and reviewer: its model when on, "judge off" when off', () => {
  const w = boot({ tab: 'control' });
  const d = two(), [sample, shop] = d.panels.machine.data.projects;
  sample.models.judge = { on: true, model: 'claude-sonnet-5-5', effort: 'high' };
  shop.models = { builder: { model: 'claude-opus-5-5', effort: null }, reviewer: { model: 'gpt-6.1-sol', effort: null }, judge: { on: false } };
  deliver(w, d);
  const models = (r) => section(w, r).querySelector('.project-models').textContent;
  assert.equal(models('sample'), 'Builder claude-opus-5-5 · high; reviewer gpt-6.1-sol · medium; judge claude-sonnet-5-5 · high');
  assert.equal(models('widgetshop'), 'Builder claude-opus-5-5; reviewer gpt-6.1-sol; judge off');
});

// What the page can hold: the one request it sends names that project alone, and a reading in which one project is
// paused shows the other, and the machine, running. The readings here are made by hand, so this cannot catch a server
// that pauses both projects: dashboard-server.test.sh (pause_of_one_project_leaves_the_other) holds that the host
// runs the one command, on the named project's checkout.
test('the machine: a pause of one project is sent for that project alone, and a reading with it paused shows the other running', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, two());
  act(section(w, 'widgetshop'), 'pause').click();
  await settle(); await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'pause', args: [], repo: 'widgetshop' } }], 'the action names its project; nothing is sent for the machine or for sample');
  assert.match(section(w, 'widgetshop').querySelector('.project-note').textContent, /^Paused\./);
  // Issue 438: an Undo before the next reading left the project's Pause hidden for good while it read as running.
  act(section(w, 'widgetshop'), 'undo').click();
  await settle(); await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'resume', args: [], repo: 'widgetshop' } }]);
  assert.equal(act(section(w, 'widgetshop'), 'pause').textContent, 'Pause widgetshop', 'Pause is back once the Undo went through');
  refresh(w); deliver(w, two());
  assert.ok(act(section(w, 'widgetshop'), 'pause'), 'a later running reading still shows Pause');
  // A reading with widgetshop paused (made here, not the server's): it offers its resume; sample and the machine show running.
  const next = two(); Object.assign(next.panels.machine.data.projects[1], { state: 'paused', mode: 'pause' });
  const n = boot({ tab: 'control' }); deliver(n, next);
  assert.deepEqual(sections(n).map((s) => s.dataset.state), ['running', 'paused']);
  assert.equal(act(section(n, 'widgetshop'), 'pause'), null);
  assert.equal(act(section(n, 'widgetshop'), 'resume').textContent, 'Resume widgetshop');
  assert.equal(act(section(n, 'sample'), 'pause').textContent, 'Pause sample', 'the other project is as it was');
  assert.equal(head(n).dataset.state, 'running', 'and so is the machine');
  act(section(n, 'widgetshop'), 'resume').click();
  await settle(); await settle();
  assert.deepEqual(n.posts.splice(0), [{ url: 'control', body: { action: 'resume', args: [], repo: 'widgetshop' } }]);
  // A project whose control record was not read has no control: nothing can be sent for it without knowing its state.
  const unread = two(); unread.panels.machine.data.projects[1].mode = null;
  const u = boot({ tab: 'control' }); deliver(u, unread);
  assert.deepEqual([act(section(u, 'widgetshop'), 'pause'), act(section(u, 'widgetshop'), 'resume')], [null, null]);
});

test('the machine: the filter shows one project only on every list, each row tagged with its project; the sort keeps a project\'s rows together', () => {
  const w = boot();
  deliver(w, two());
  assert.deepEqual(Array.from(act(head(w), 'project').options, (o) => [o.value, o.textContent]), [['', 'All projects'], ['sample', 'sample'], ['widgetshop', 'widgetshop']]);
  assert.deepEqual(tagsOf(w, 'queue').slice(0, 3), ['widgetshop', 'sample', 'sample'], 'a mixed list, in pick order');
  assert.ok(tagsOf(w, 'needs').includes('widgetshop') && tagsOf(w, 'needs').includes('sample') && tagsOf(w, 'belt').includes('widgetshop'));
  const hue = (id, repo) => Array.from(panel(w, id).querySelectorAll('.project-tag')).find((t) => t.textContent === repo).dataset.hue;
  assert.deepEqual([hue('queue', 'sample'), hue('queue', 'widgetshop'), hue('belt', 'widgetshop')], ['0', '1', '1'], 'a project keeps one colour on every list, beside its name');
  assert.equal(panel(w, 'belt').querySelector('.panel-count').textContent, '3 of 8');
  // Sorted by project: each project's rows together, their own order kept.
  act(head(w), 'psort').click();
  assert.deepEqual(tagsOf(w, 'queue').slice(0, 3), ['sample', 'sample', 'widgetshop']);
  assert.equal(new URL(w.location.href).searchParams.get('psort'), '1');
  act(head(w), 'psort').click();
  assert.deepEqual(tagsOf(w, 'queue').slice(0, 3), ['widgetshop', 'sample', 'sample']);
  // One project only.
  choose(w, act(head(w), 'project'), 'widgetshop');
  for (const id of ['needs', 'belt', 'queue']) assert.deepEqual([...new Set(tagsOf(w, id))], ['widgetshop'], `${id} shows widgetshop only`);
  assert.equal(panel(w, 'belt').querySelector('.panel-count').textContent, '2 of 5', 'the belt counts that project\'s cards of its own cap');
  assert.match(panel(w, 'queue').textContent, /Holds keep 4 issues back: see Held\./, 'the queue\'s held count is that project\'s');
  assert.equal(panel(w, 'queue').querySelector('.panel-count').textContent, '1');
  assert.deepEqual(Array.from(panel(w, 'metrics').querySelectorAll('.metrics-tab')), [], 'metrics shows that project\'s measurements alone');
  const u = new URL(w.location.href).searchParams;
  assert.deepEqual([u.get('project'), u.get('repo')], ['widgetshop', 'widgetshop'], 'kept in the address, and the Board and Rules show that project');
  assert.match(said(head(w)), /7 of 10 cards at once/, 'the machine head stays the whole machine\'s');
  tabBtn(w, 'control').click();
  assert.deepEqual(sections(w).map((s) => s.dataset.project), ['widgetshop'], 'one project section');
  assert.equal(heading(w, 'board'), 'Board: widgetshop');
  // A reload, or a link, keeps the filter; every project again brings both back.
  const again = boot({ query: '?tab=overview&project=widgetshop' });
  deliver(again, two());
  assert.equal(act(head(again), 'project').value, 'widgetshop');
  assert.deepEqual([...new Set(tagsOf(again, 'needs'))], ['widgetshop']);
  choose(again, act(head(again), 'project'), '');
  assert.ok(tagsOf(again, 'needs').includes('sample') && tagsOf(again, 'needs').includes('widgetshop'));
  assert.equal(new URL(again.location.href).searchParams.get('project'), null);
  // A project the host does not name filters nothing; one project alone has no filter to offer.
  const odd = boot({ query: '?tab=overview&project=__proto__' });
  deliver(odd, two());
  assert.ok(tagsOf(odd, 'needs').includes('sample'));
  const one = boot(); deliver(one, full());
  assert.deepEqual([act(head(one), 'project'), act(head(one), 'psort')], [null, null]);
});

test('the machine: a group\'s Foreman is shown once with both its projects; a project with no Foreman says so', () => {
  const w = boot({ tab: 'control' });
  deliver(w, two());
  const lines = () => Array.from(panel(w, 'machine').querySelectorAll('.foreman'));
  assert.equal(lines().length, 1, 'one Foreman for the group, not one a project');
  assert.equal(lines()[0].dataset.projects, 'sample widgetshop');
  assert.match(said(lines()[0]), /Foreman of the group sample, widgetshop.*A session holds the role.*claimed 1 h 00 min ago.*never woken yet.*nothing waiting on it/);
  // Filtered to one of its projects, the group's Foreman is still that project's.
  choose(w, act(head(w), 'project'), 'widgetshop');
  assert.equal(lines().length, 1);
  choose(w, act(head(w), 'project'), '');
  // Each project its own: one holds the role and has wakes waiting, the other has no Foreman.
  const own = two();
  own.panels.machine.data.foremen = [
    { projects: ['sample'], group: false, held: true, since: iso(T0 - 7200000), lastWakeAt: iso(T0 - 300000), waiting: ['Conveyor: sample: blocked: #13', 'Limit: 91% of the week used'] },
    { projects: ['widgetshop'], group: false, held: false, since: null, lastWakeAt: null, waiting: [] }];
  const o = boot({ tab: 'control' }); deliver(o, own);
  const [a, b] = Array.from(panel(o, 'machine').querySelectorAll('.foreman'));
  assert.match(said(a), /Foreman of sample.*A session holds the role.*claimed 2 h 00 min ago.*last woken 5 min ago.*2 waiting on it.*blocked: #13.*Limit: 91%/);
  assert.equal(b.dataset.held, 'false');
  assert.match(said(b), /Foreman of widgetshop.*No Foreman.*No Claude session is its Foreman now: open one in widgetshop to take the role\..*never woken yet/);
  // Foremen that could not be read are said, with why; the projects still show.
  const bad = two(); Object.assign(bad.panels.machine.data, { foremen: null, foremenError: 'conveyor/host.json records are not understood' });
  const x = boot({ tab: 'control' }); deliver(x, bad);
  assert.match(panel(x, 'machine').textContent, /The Board could not read the Foremen, so it shows none\. It reads them again in about a minute\./);
  // Issue 415 (UX5): the reason names a file, so it is on tap only.
  assert.equal(panel(x, 'machine').querySelector('.warn-note[data-tip]').dataset.tip, 'Details: conveyor/host.json records are not understood');
  assert.doesNotMatch(panel(x, 'machine').textContent, /host\.json/);
  assert.equal(panel(x, 'machine').querySelectorAll('.project').length, 2);
});

test('the machine: metrics show each project and the machine side by side: cards landed, time to land and cost', () => {
  const w = boot();
  deliver(w, two());
  const rows = () => Array.from(panel(w, 'metrics').querySelectorAll('.metrics-compare tbody tr'), (tr) => Array.from(tr.children, (c) => c.textContent));
  assert.deepEqual(Array.from(panel(w, 'metrics').querySelectorAll('.metrics-compare thead th'), (c) => c.textContent), ['Project', 'Cards landed', 'Time to land (median)', 'Cost']);
  assert.deepEqual(rows(), [['widgetshop', '3', '1 h 00 min', '—'], ['sample', '7', '1 h 58 min', '$14.00'], ['Build machine', '10', '1 h 36 min', '—']],
    'a cost that was not priced is a dash for the project and for the machine, never a sum of the priced part');
  // Bug: the comparison ignored the machine head's filter and sort. Sorted by project, its projects are in that
  // order; filtered to one project, that project's row beside the machine's, which stays every project's.
  // Bug: a card's row of measurements named no project: each is tagged with its own, as on every other list.
  const cardTags = Array.from(panel(w, 'metrics').querySelectorAll('.card-detail > summary .project-tag'), (t) => t.textContent);
  assert.ok(cardTags.length > 0 && cardTags.every((t) => t === 'sample'), 'each card row of the open project carries its project tag');
  act(head(w), 'psort').click();
  assert.deepEqual(rows().map((r) => r[0]), ['sample', 'widgetshop', 'Build machine']);
  act(head(w), 'psort').click();
  choose(w, act(head(w), 'project'), 'widgetshop');
  assert.deepEqual(rows(), [['widgetshop', '3', '1 h 00 min', '—'], ['Build machine', '10', '1 h 36 min', '—']]);
  // Bug: a machine with one project showed no comparison at all: its one project is set beside the machine too.
  // Bug: a cost that leaves out steps with no price showed as the whole cost, for a project and for the machine.
  const part = two();
  part.panels.metrics.data.compare = { projects: [{ repo: 'widgetshop', landed: 3, leadSec: 3600, usd: 5, usdLeftOut: 1 }, { repo: 'sample', landed: 7, leadSec: 7110, usd: 14, usdLeftOut: 0 }],
    machine: { landed: 10, leadSec: 5760, usd: 19, usdLeftOut: 1 } };
  const p = boot(); deliver(p, part);
  assert.deepEqual(Array.from(panel(p, 'metrics').querySelectorAll('.metrics-compare tbody tr'), (tr) => tr.lastChild.textContent),
    ['$5.00 (1 step not priced, left out)', '$14.00', '$19.00 (1 step not priced, left out)']);
  const alone = full();
  alone.panels.metrics.data.compare = { projects: [{ repo: 'sample', landed: 7, leadSec: 7110, usd: 14 }], machine: { landed: 7, leadSec: 7110, usd: 14 } };
  const one = boot(); deliver(one, alone);
  assert.deepEqual(Array.from(panel(one, 'metrics').querySelectorAll('.metrics-compare tbody tr'), (tr) => Array.from(tr.children, (c) => c.textContent)),
    [['sample', '7', '1 h 58 min', '$14.00'], ['Build machine', '7', '1 h 58 min', '$14.00']]);
});

// Bug: a step not priced showed its issue number and no project: with two projects on the machine, #1 of one and #1
// of the other read as the same card.
test('the machine: Cost tags each step not priced with its project, so the same issue number in two projects is told apart', () => {
  const d = two();
  Object.assign(d.panels.cost.data.cards, { unpricedSteps: 2, todayLeftOut: 2, weekLeftOut: 2, perLandedLeftOut: 0, unpriced: [
    { repo: 'sample', card: 'c1-1', issue: 1, url: 'https://example.com/sample/issues/1', step: 'build', time: iso(T0 - 600000), why: 'no model recorded' },
    { repo: 'widgetshop', card: 'c4-1', issue: 1, url: 'https://example.com/widgetshop/issues/1', step: 'build', time: iso(T0 - 600000), why: 'no model recorded' }] });
  const w = boot();
  deliver(w, d);
  const rows = Array.from(panel(w, 'cost').querySelector('.rows').children, (li) => [li.querySelector('.project-tag').textContent, li.querySelector('.issue').textContent]);
  assert.deepEqual(rows, [['sample', '#1'], ['widgetshop', '#1']]);
});

// Bug: Cost and Health ignored the machine head's filter and sort: ?project=sample still showed widgetshop's cost
// rows under the sums of both projects, and widgetshop's loop and push checks.
test('the machine: Cost and Health are cut to the project filtered to, and Cost keeps each project\'s rows together when sorted', () => {
  const d = two();
  const c = d.panels.cost.data.cards;
  c.perCard.push(wi(5, 'Widget build', { card: 'c4-5', todayUsd: 2.25, weekUsd: 9, state: 'on the belt' }));
  Object.assign(c, { todayUsd: 6.5, weekUsd: 23, unpricedSteps: 1, todayLeftOut: 1, weekLeftOut: 1, perLandedLeftOut: 0,
    unpriced: [wi(5, 'Widget build', { card: 'c4-5', step: 'build', time: iso(T0 - 600000), why: 'no model recorded' })],
    byRepo: { sample: { todayUsd: 4.25, weekUsd: 14, perLandedUsd: 1, landedAfter: { 1: 3, 2: 1, 3: 0, more: 0 }, unpricedSteps: 0, todayLeftOut: 0, weekLeftOut: 0, perLandedLeftOut: 0 },
      widgetshop: { todayUsd: 2.25, weekUsd: 9, perLandedUsd: null, landedAfter: { 1: 0, 2: 0, 3: 0, more: 0 }, unpricedSteps: 1, todayLeftOut: 1, weekLeftOut: 1, perLandedLeftOut: 0 } } });
  d.panels.health.data.records.push({ ...clone(d.panels.health.data.records[0]), repo: 'widgetshop' });
  // A blocked card of widgetshop, newer than sample's: newest first puts it on top, a sort by project does not.
  d.panels.needs.data.cards.blocked.find((x) => x.repo === 'widgetshop').since = iso(T0 - 1000);
  const w = boot({ reducedMotion: true });  // a figure that changes shows its new value at once
  deliver(w, d);
  const figure = (k) => panel(w, 'cost').querySelector(`[data-figure="${k}"]`).textContent;
  const checks = () => Array.from(panel(w, 'health').querySelectorAll('.checks > dt'), (t) => t.textContent).filter((t) => /^Conveyor/.test(t));
  const blocked = () => Array.from(panel(w, 'needs').querySelectorAll('[data-group="blocked"] .rows .project-tag'), (t) => t.textContent);
  // The steps not priced are a list of their own, above the cards': each of its rows names its project too.
  const lists = () => Array.from(panel(w, 'cost').querySelectorAll('.rows'), (l) => Array.from(l.querySelectorAll('.project-tag'), (t) => t.textContent));
  assert.deepEqual(lists()[0], ['widgetshop'], 'the step not priced says whose it is');
  assert.deepEqual(lists()[1][0], 'widgetshop', 'every project, the costliest card first, each row tagged with its project');
  assert.match(figure('week'), /\$23\.00/);
  assert.deepEqual(checks(), ['Conveyor (sample)', 'Conveyor (widgetshop)']);
  assert.equal(blocked()[0], 'widgetshop');
  // Sorted by project: each project's rows together, the panel's own order kept inside a project.
  act(head(w), 'psort').click();
  assert.deepEqual([...new Set(lists()[1])], ['sample', 'widgetshop'], 'the widgetshop rows come after every sample row');
  assert.match(panel(w, 'cost').querySelector('.rows .row .num:last-child').textContent, /\$6\.25 in 7 days/, 'sample\'s costliest card is still its first');
  assert.equal(blocked()[0], 'sample', 'a panel that orders its list itself keeps each project\'s rows together too');
  act(head(w), 'psort').click();
  // One project only: its rows, its own figures and its own checks.
  choose(w, act(head(w), 'project'), 'sample');
  assert.deepEqual([...new Set(tagsOf(w, 'cost'))], ['sample']);
  assert.match(figure('week'), /\$14\.00/, 'the figures are that project\'s own, not the sum of every project');
  assert.doesNotMatch(panel(w, 'cost').textContent, /no price/, 'widgetshop\'s unpriced step is not sample\'s');
  assert.deepEqual(checks(), ['Conveyor'], 'Health checks that project\'s record alone');
  choose(w, act(head(w), 'project'), 'widgetshop');
  assert.match(figure('today'), /\$2\.25/);
  assert.match(panel(w, 'cost').textContent, /1 step has no price, and the figures above do not include it \(1 today, 1 in 7 days\)/);
  assert.match(panel(w, 'cost').textContent, /Every session on this machine: \$12\.50 today/, 'the sessions stay the machine\'s');
});

// Bug: a project's cost today hid the steps it leaves out for having no price: $5.00 read as the whole cost.
test('the machine: a project\'s cost today says how many steps have no price', () => {
  const d = two();
  Object.assign(d.panels.machine.data.projects[1], { todayUsd: 5, todayLeftOut: 1 });
  d.panels.machine.data.projects[0].todayLeftOut = 0;
  const w = boot({ tab: 'control' });
  deliver(w, d);
  assert.match(said(section(w, 'widgetshop').querySelector('.project-head')), /\$5\.00 today \(1 step has no price\)/);
  assert.doesNotMatch(said(section(w, 'sample').querySelector('.project-head')), /no price/);
});

// Bug: a link that carried the filter and no ?repo= (?tab=control&project=widgetshop) cut every list to widgetshop
// while the Board, and its controls, stayed on the host's first project: a hold or a pause went to the wrong project.
test('the machine: a link filtered to one project shows that project\'s Board, and Show picks the Board\'s project with the filter', () => {
  const w = boot({ query: '?tab=control&project=widgetshop' });
  deliver(w, two());
  assert.deepEqual(sections(w).map((s) => s.dataset.project), ['widgetshop']);
  assert.equal(heading(w, 'board'), 'Board: widgetshop', 'the Board is the filtered project\'s, with no ?repo= in the address');
  // The filter wins over a ?repo= that names another project.
  const mixed = boot({ query: '?tab=control&project=sample&repo=widgetshop' });
  deliver(mixed, two());
  assert.equal(heading(mixed, 'board'), 'Board: sample');
  // Another project picked in Show moves the Board with it: the Board never shows a project the filter hides.
  choose(w, act(head(w), 'project'), 'sample');
  const u = new URL(w.location.href).searchParams;
  assert.deepEqual([u.get('project'), u.get('repo')], ['sample', 'sample']);
  assert.deepEqual(sections(w).map((s) => s.dataset.project), ['sample']);
  assert.equal(heading(w, 'board'), 'Board: sample');
});

// Bug: a project's section listed only its cards as Needs you: an open decision of its ledger was left out.
test('the machine: a project\'s Needs you names its open decisions beside its issues', () => {
  const d = two();
  d.panels.machine.data.projects[1].needs.push({ repo: 'widgetshop', decision: 'w-pay', title: 'Take card payments from Monday?' });
  const w = boot({ tab: 'control' });
  deliver(w, d);
  assert.match(said(section(w, 'widgetshop').querySelector('[data-list="Needs you"]')), /Needs you \(2\).*#41.*decision: Take card payments from Monday\?/);
});

// Issue 1538: the cap counts every card on the belt but a landing one, a card that waits on another card too, so the
// Belt panel counts as the On the belt tile does, and filtered to one project it counts that project's cards against
// its own cap. Bug it catches: the panel took the part's waiting count off its figure, so the owner saw fewer cards
// against the cap than the belt held; or, filtered, it counted every project's cards. The part still carries waiting
// here, as an older Board's does.
test('the belt: its count holds every card on the belt, a waiting one too, each project its own', () => {
  const d = two();
  // widgetshop's second card waits on its first, so a count that drops the cards with step 'waiting' fails here.
  Object.assign(d.panels.belt.data.cards.find((c) => c.card === 'c4-6'), { step: 'waiting', waitsOn: { card: 'c4-5', issue: 5, state: 'building' } });
  Object.assign(d.panels.belt.data, { waiting: 1, byRepo: { sample: { cap: 3, waiting: 0 }, widgetshop: { cap: 5, waiting: 1 } } });
  const w = boot();
  deliver(w, d);
  const count = () => panel(w, 'belt').querySelector('.panel-count').textContent;
  assert.equal(count(), '3 of 8', 'three cards, one waiting: all three count');
  choose(w, act(head(w), 'project'), 'widgetshop');
  assert.equal(count(), '2 of 5', 'widgetshop: its two cards, the waiting one too, of its own cap');
  choose(w, act(head(w), 'project'), 'sample');
  assert.equal(count(), '1 of 3', 'sample: its one card of its own cap, no other project\'s card counted');
});
