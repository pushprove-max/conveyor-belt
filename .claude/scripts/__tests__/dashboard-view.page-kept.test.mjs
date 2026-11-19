// SPDX-License-Identifier: Apache-2.0
// What the Board keeps through a reload: list lengths, Needs-you drafts and the Board filter, in sessionStorage.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { T0, iso, P, OVERVIEW, read, boot, panel, state, deliver, full, tabBtn, board, column, inCol, act, cases, pickProject, OPEN, withOpen, settle } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// A sessionStorage two pages of one tab share, as a reload does.
const storage = () => {
  const m = new Map();
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => { m.set(k, String(v)); }, removeItem: (k) => { m.delete(k); } };
};
const many = (n) => Array.from({ length: n }, (_, i) => ({ repo: 'sample', id: `d${i.toString(16).padStart(12, '0')}`, time: iso(T0 - (i + 1) * 60000), card: 'c3-63', issue: 63, url: `${P}/63`,
  finding: `[P3] f${i}.txt:1 a nit`, by: 'judge', why: 'a nit', built: null, dismissed: null }));
const data = () => { const d = full(); d.panels.declined.data.lines = many(12); return d; };
const answer = (w) => panel(w, 'needs').querySelector('input[aria-label="Answer to q-ship"]');
const filter = (w) => board(w).querySelector('[data-filter="text"]');
const declined = (w) => panel(w, 'declined').querySelectorAll('.rows > .row');
const yes = (w, label) => panel(w, 'needs').querySelector(`input[aria-label="${label}"]`);
const type = (w, field, text) => { field.value = text; field.dispatchEvent(new w.Event('input', { bubbles: true })); };

// Bug: a page that reloaded itself on a new view lost a typed answer, each "Show 5 more" and the Board filter.
test('a page booted again with the same sessionStorage shows the draft, the Declined rows and the Board filter of the first', () => {
  const session = storage();
  const a = boot({ session });
  deliver(a, data());
  type(a, answer(a), 'Ship on Monday');
  // Bug: a condition or a reason for a card waiting for the owner's yes was lost, while the answer was kept.
  type(a, yes(a, 'Condition for the yes to #12'), 'Only on Friday');
  type(a, yes(a, 'Why not, for #12'), 'Not this week');
  assert.equal(declined(a).length, 5);
  act(panel(a, 'declined'), 'list-more').click();
  assert.equal(declined(a).length, 10);
  // Bug: the focus stayed on the button, and a keyboard user had to find the first new row again.
  assert.equal(a.document.activeElement, declined(a)[5], 'the focus is on the first new row');
  tabBtn(a, 'control').click();
  type(a, filter(a), '21');
  assert.deepEqual(inCol(a, 'queue'), [21]);

  const b = boot({ session });
  deliver(b, data());
  assert.equal(answer(b).value, 'Ship on Monday');
  assert.equal(yes(b, 'Condition for the yes to #12').value, 'Only on Friday');
  assert.equal(yes(b, 'Why not, for #12').value, 'Not this week');
  assert.equal(declined(b).length, 10, 'the same number of Declined rows');
  tabBtn(b, 'control').click();
  assert.equal(filter(b).value, '21');
  assert.deepEqual(inCol(b, 'queue'), [21], 'the kept filter filters the columns');
});

// Bug: a sign-in in another tab of the browser (after a password change, as another user) cleared that tab's storage
// only: this tab's Board, opened again, showed the new user the last user's unsent answers.
test('after a sign-in in another tab, the Board in this tab shows none of what the last user typed', async () => {
  const session = storage();
  const a = boot({ session });
  deliver(a, data());
  type(a, answer(a), 'Ship on Monday');
  type(a, yes(a, 'Condition for the yes to #12'), 'Only on Friday');
  // The other tab: the login page, its own sessionStorage, the browser's one localStorage; the server takes the login.
  const { JSDOM } = createRequire(import.meta.url)('jsdom');
  const l = new JSDOM(read('login.html'), { url: 'https://dash.test/login', runScripts: 'outside-only' }).window;
  l.fetch = (url, opt) => Promise.resolve(opt ? { status: 200, text: () => Promise.resolve('') } : { ok: false, status: 401 });
  l.eval(read('login.js'));
  l.document.getElementById('login-user').value = 'other';
  l.document.getElementById('login-secret').value = 'a long password';
  l.document.getElementById('login-password').dispatchEvent(new l.Event('submit', { cancelable: true }));
  await settle();
  const mark = l.localStorage.getItem('conveyor-board-login');
  assert.ok(mark, 'the sign-in leaves a new login mark');
  const c = boot({ session, store: { 'conveyor-board-login': mark } });
  deliver(c, data());
  assert.deepEqual([answer(c).value, yes(c, 'Condition for the yes to #12').value], ['', ''], 'no draft of the last login');
});

// Bug: a condition and an answer sent and taken came back in their fields on a reload before the next snapshot.
test('a condition or an answer that the build machine took is not kept', async () => {
  const session = storage();
  const a = boot({ session });
  deliver(a, data());
  type(a, answer(a), 'Ship on Monday');
  answer(a).closest('li').querySelector('button.btn-primary').click();
  type(a, yes(a, 'Condition for the yes to #12'), 'Only on Friday');
  const go = yes(a, 'Condition for the yes to #12').closest('li').querySelector('button[data-act="condition"]');
  go.click(); go.click();
  await settle();
  assert.deepEqual(a.posts.map((p) => p.url), ['answer', 'control']);
  const b = boot({ session });
  deliver(b, data());
  assert.deepEqual([answer(b).value, yes(b, 'Condition for the yes to #12').value], ['', '']);
});

// Bug: Clear emptied the filter on the page, and a reload brought the old filter back.
test('Clear empties the kept Board filter', () => {
  const session = storage();
  const a = boot({ session, tab: 'control' });
  deliver(a, data());
  type(a, filter(a), 'no such title');
  act(column(a, 'queue'), 'filter-clear').click();
  const b = boot({ session, tab: 'control' });
  deliver(b, data());
  assert.equal(filter(b).value, '');
  assert.deepEqual(inCol(b, 'queue'), [20, 21, 22]);
});

// Bug: a browser whose storage refuses each call (a private window, a storage policy) would stop the page at start.
test('a page whose sessionStorage throws on each call boots, draws every panel, and its lists still grow', () => {
  const no = () => { throw new Error('storage refused'); };
  const w = boot({ session: { getItem: no, setItem: no, removeItem: no } });
  deliver(w, data());
  for (const id of OVERVIEW) assert.equal(state(w, id), 'ready', `${id} is drawn`);
  act(panel(w, 'declined'), 'list-more').click();
  assert.equal(declined(w).length, 10, 'the length is kept for the page\'s life');
  type(w, answer(w), 'Ship on Monday');
  tabBtn(w, 'control').click();
  assert.equal(state(w, 'board'), 'ready');
  type(w, filter(w), '21');
  assert.deepEqual(inCol(w, 'queue'), [21]);
});

// Bug: a list's length was kept under ?repo=, which "Every project" leaves set: the list of every project then showed
// the length chosen for the one project picked last.
test('a list length chosen with one project picked is not the length of the list of every project', () => {
  const w = boot({ session: storage() }), d = data();
  d.panels.machine.data.repos = ['sample', 'widgetshop'];
  deliver(w, d);
  pickProject(w, 'sample');
  act(panel(w, 'declined'), 'list-more').click();
  assert.equal(declined(w).length, 10);
  pickProject(w, '');
  assert.equal(declined(w).length, 5, 'every project: its own length');
  pickProject(w, 'sample');
  assert.equal(declined(w).length, 10, 'sample: the length chosen for it');
});

// Bug: the first new row of Held was in a group the owner left closed, could not take the focus, and the focus
// stayed on "Show 100 more".
test('after Show 100 more in Held, a first new row in a closed group puts the focus on that group\'s heading', () => {
  const dormant = Array.from({ length: 275 }, (_, i) => ({ repo: 'example', issue: 1000 + i, title: `Dormant ${i}`, url: null, priority: 'P3', labels: ['dormant'], reasons: [{ kind: 'label', label: 'dormant' }] }));
  const w = boot({ tab: 'control', session: storage() });
  deliver(w, withOpen({ held: OPEN.held.concat(dormant) }));
  const group = column(w, 'held').querySelector('details[data-group="label:dormant"]');
  assert.equal(group.open, false, 'a long group starts closed');
  act(column(w, 'held'), 'list-more').click();
  assert.equal(w.document.activeElement, column(w, 'held').querySelector('details[data-group="label:dormant"] > summary'));
});
