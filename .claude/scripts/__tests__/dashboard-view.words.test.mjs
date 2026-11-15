// SPDX-License-Identifier: Apache-2.0
// Issue 415 (the Board UX audit's UX5, UX8 and UX37): the words the browser case in dashboard-view.fit.test.mjs does
// not reach. A message for what cannot be read says what is not seen and the one thing to try, in the Board's words;
// a reason an issue is not built leads to where it is changed; an empty queue says what is held; a session's action
// is said in words, its command on tap. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, full, panel, board, bcard, column, rulesP, withOpen, OPEN, clone, P, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// Bug: a control record that did not read said "The control record on the host did not read" (Rules), "Control
// record unreadable" (the Board's state) and "Its control record was not read: no control here" (Projects). And a
// record that does not read (control null: the machine answered) is not an unreachable machine: telling the reader to
// restart, which cannot repair it, was the wrong one thing to try.
test('settings the build machine could not read: Rules, the Board and Projects say so in plain words, with what to try', () => {
  const d = full();
  d.panels.rules.data.control = null;
  d.panels.board.data.state = 'control record unreadable';
  Object.assign(d.panels.machine.data.projects[0], { state: 'control record unreadable', mode: null });
  const r = boot({ tab: 'rules' });
  deliver(r, d);
  assert.equal(rulesP(r).querySelector('.rules-side .warn-note').textContent,
    "Conveyor could not read its settings on the build machine. You cannot see or change the rules here, and Conveyor picks no new card. Run Conveyor's control command on the build machine: it says what is wrong.");
  const c = boot({ tab: 'control' });
  deliver(c, d);
  assert.equal(panel(c, 'board-loop').querySelector('.board-state .chip').textContent, 'Settings not read');
  const p = panel(c, 'machine').querySelector('.project');
  assert.equal(p.querySelector('.project-head .chip').textContent, 'Settings not read');
  assert.match(p.querySelector('.project-acts').textContent, /^Conveyor could not read its settings on the build machine\. You cannot pause it from here, and it picks no new card\. Run Conveyor's control command on the build machine: it says what is wrong\./);
  assert.doesNotMatch(r.document.body.textContent + c.document.body.textContent, /control record/i);
  assert.doesNotMatch(rulesP(r).querySelector('.rules-side').textContent + p.textContent, /cannot reach|Restart/, 'a restart cannot repair settings that do not read');
});

// UX8: each reason leads to where it is changed. Bug: "Skipped by rule" named the rule with no way to it, and "Waits on
// #20" named the issue as plain text.
test('the Board: a rule-skipped card links to Rules, which opens the Rules tab; a waiting card links to each issue it waits on', () => {
  const wait = { repo: 'sample', issue: 44, title: 'Second half', url: `${P}/44`, priority: 'P2', labels: [], reasons: [{ kind: 'waits', waitsFor: [20, 22] }] };
  const w = boot({ tab: 'control' });
  deliver(w, withOpen({ count: 10, split: { ...OPEN.split, labelOrRule: 4 }, held: clone(OPEN.held).concat([wait]) }));
  const chip = bcard(w, 44).querySelector('.chip[data-reason="waits"]');
  assert.equal(chip.textContent, 'Waiting on #20, #22');
  assert.deepEqual(Array.from(chip.querySelectorAll('a.issue'), (a) => a.href), [`${P}/20`, `${P}/22`], 'each issue it waits on is a link to it');
  const link = bcard(w, 23).querySelector('a[data-act="rules-open"]');
  assert.equal(link.closest('.board-why').textContent, 'Skipped by a rule: change it in Rules to queue it.');
  link.click();
  assert.equal(w.document.getElementById('tab-rules').getAttribute('aria-selected'), 'true', 'the link opens the Rules tab');
});

// UX21. Bug: Control's Queue column said a bare "Nothing is queued." with issues held, and the Queue panel's empty
// state "The loop has no open issue to pick", neither saying whether issues are held. The Queue panel counts what the
// Board holds (by you, a label, a rule or a wait), as the collector sends it (dashboard.test.sh).
test('an empty queue says how many issues are held and links to Held, on Control and in the Queue panel; with none held, that none are', () => {
  const d = withOpen();
  Object.assign(d.panels.board.data, { queue: [], waits: [] });
  const c = boot({ tab: 'control' });
  deliver(c, d);
  const held = column(c, 'held').querySelectorAll('.bcard').length;
  const line = column(c, 'queue').querySelector('.board-queue-empty');
  assert.equal(line.textContent, `Nothing queued. Holds keep ${held} issues back: see Held.`);
  assert.equal(line.querySelector('a[data-act="held-see"]').getAttribute('href'), '#board-col-held');
  const q = full();
  Object.assign(q.panels.queue.data, { next: [], awaitingDeploy: [], waiting: [], held: 3 });
  const o = boot();
  deliver(o, q);
  assert.match(panel(o, 'queue').textContent, /The queue is emptyHolds keep 3 issues back: see Held on the Control tab\./);
  q.panels.queue.data.held = 0;
  const none = boot();
  deliver(none, q);
  assert.match(panel(none, 'queue').textContent, /The queue is emptyNothing holds an open issue either: Conveyor has no issue to build\./);
});

// UX5, live check. Bug: Health showed "the usage read failed (rate limited (429); retry after 3536 s); showing the last
// reading" and "origin/main could not be fetched: and the repository exists."
test('Health: a refused usage read and a failed fetch of main are said in plain words', () => {
  const d = full(), hd = d.panels.health.data;
  hd.accounts = { error: null, list: [{ machine: null, name: 'default', email: 'noreply@example.com', usedPct: null, fiveHourPct: null, resetsAt: null,
    readAt: null, error: 'rate limited (429); retry after 3536 s', usedFor: ['not used by the Conveyor'] }] };
  hd.update = { checkedAt: hd.update ? hd.update.checkedAt : null, head: 'abc1234', error: "origin/main could not be fetched: fatal: 'origin' does not appear to be a git repository", moved: null };
  const w = boot();
  deliver(w, d);
  const text = panel(w, 'health').textContent;
  assert.ok(text.includes('the usage server asked for a pause; try again in 58 min'), text);
  assert.ok(text.includes("the Board could not get main from GitHub: fatal: 'origin' does not appear to be a git repository"), text);
  assert.doesNotMatch(text, /rate limited|retry after|origin\/main could not/);
});

// UX37: a session's action in words; the command, path or pattern itself on tap. A word the stream sends ("thinking")
// is shown as it is.
test('On the belt: a session\'s action is said as the kind of work, its full text on tap', () => {
  const said = (action) => {
    const d = full();
    d.panels.belt.data.cards[0].live = { turns: 3, lastOutputAt: d.updatedAt, action };
    const w = boot();
    deliver(w, d);
    const el = panel(w, 'belt').querySelector('.live-action');
    return [el.textContent, el.dataset.tip];
  };
  assert.deepEqual(said('command: npm test'), ['now: running a command', 'command: npm test'], 'a Codex review\'s command');
  assert.deepEqual(said('Edit: .claude/dashboard/app.js'), ['now: changing the code', 'Edit: .claude/dashboard/app.js']);
  assert.deepEqual(said('Grep: verdictSaid'), ['now: reading the code', 'Grep: verdictSaid']);
  assert.deepEqual(said('TodoWrite: plan'), ['now: using TodoWrite', 'TodoWrite: plan'], 'a tool not named is said by its name');
  assert.deepEqual(said('Bash'), ['now: running a command', 'Bash'], 'a tool called with nothing named');
  assert.deepEqual(said('thinking'), ['now: thinking', 'thinking']);
  assert.deepEqual(said('writing'), ['now: writing', 'writing'], 'a word is not taken for the Write tool');
});
