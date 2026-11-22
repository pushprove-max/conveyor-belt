// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Release suite runs on" (Capacity): the control record's suiteMachine, the machine a release's
// whole suite runs on: this machine, a Namespace Devbox or a Linux box over ssh. A choice is sent as
// `control suite-machine <local | devbox [--size <s>] | ssh <target> [--dir <d>]>`; Check the box sends
// `suite-machine check --json` and shows each line with its chip. The Namespace login and the box's test slots are
// the last check's: a devbox is checked once when it is shown, and again with each refresh, at most every 15 s, while
// the login is missing, so a login made in a terminal turns Check on by itself.
// Part of panels/rules.js, which asks for it by name (DASH_APP.use); boot.js loads it before the panels.
(() => {
  'use strict';
  let S, num, send, button, post, row, draw;
  const SIZES = ['2x4', '4x8', '8x16', '16x32'];  // the sizes offered; the record's own size is added when it is another
  const TARGET = /^[A-Za-z0-9._][A-Za-z0-9._@-]*$/;  // control suite-machine's ssh target
  const FOLDER = /^(~|~?\/[A-Za-z0-9._/@+-]*)$/;     // its --dir: ~, a folder under ~/ or a full path
  const AGAIN = 15000;  // ms: how soon a devbox's missing login is read again
  const KINDS = [
    ['local', 'This machine', (n) => `The build machine, ${n === null ? 'its' : n} test slots. The default.`],
    ['devbox', 'Namespace Devbox', () => 'A devbox leased for the run, given back after it.'],
    ['ssh', 'Linux box over ssh', () => 'Any Linux machine the build machine reaches with ssh.'],
  ];
  // The last check: {repo, key (the rule it was for), at, rec (the lines) or error}; OUT: one is under way. An ssh box
  // picked and not yet saved: draft {repo, target, dir}.
  let LAST = null, OUT = false, DRAFT = null;

  const rec = (c) => (c && c.suiteMachine && typeof c.suiteMachine === 'object' ? c.suiteMachine : { kind: 'local' });
  const kindOf = (c) => (['devbox', 'ssh'].includes(rec(c).kind) ? rec(c).kind : 'local');
  const text = (v) => (typeof v === 'string' ? v : '');
  // The size's CPUs: its name is <cpus>x<GB>.
  const cpusOf = (size) => { const m = /^([0-9]+)x[0-9]+$/.exec(size); return m ? Number(m[1]) : null; };
  // The arguments of control suite-machine that make a record's rule.
  function argsOf(m) {
    if (m.kind === 'devbox') return ['devbox'].concat(text(m.size) ? ['--size', m.size] : []);
    if (m.kind === 'ssh' && TARGET.test(text(m.target))) return ['ssh', m.target].concat(text(m.dir) ? ['--dir', m.dir] : []);
    return ['local'];
  }
  // The change that puts the record's rule back (the undo of a change of it).
  const undoArgs = (c) => argsOf(rec(c));
  const drafting = () => !!DRAFT && DRAFT.repo === S.d.repo;
  // The last check, when it is for the rule now.
  const last = (c) => (LAST && LAST.repo === S.d.repo && LAST.key === JSON.stringify(rec(c)) ? LAST : null);
  const checked = (c) => (last(c) ? last(c).rec : null);
  // Whether the Namespace login is there: true, false, or null (not read).
  function loggedIn(c) {
    const l = checked(c) && checked(c).needs.find((x) => x.need === 'Namespace login');
    return l ? l.ok === true : null;
  }
  // The test slots of the suite machine for the "Test files at once" note: a devbox's, an ssh box's (as the last check
  // read them, else a devbox's CPUs), else null (this machine: the note says nothing).
  function suiteSlots(c) {
    const k = kindOf(c), got = checked(c) ? num(checked(c).slots) : null;
    if (k === 'local') return null;
    return { kind: k, n: got !== null ? got : k === 'devbox' ? cpusOf(text(rec(c).size)) : null };
  }

  function check(c) {
    if (OUT) return;
    const repo = S.d.repo, key = JSON.stringify(rec(c));
    OUT = true; draw();
    post('suite-machine-check', [], repo).then((r) => {
      const out = (() => { try { return JSON.parse(r.said); } catch { return null; } })();
      const good = r.ok && out && Array.isArray(out.needs);
      LAST = { repo, key, at: Date.now(), rec: good ? out : null, error: good ? '' : r.said };
    }, () => { LAST = { repo, key, at: Date.now(), rec: null, error: 'the host did not answer' }; }).then(() => { OUT = false; draw(); });
  }
  // The check's lines, each with "ok" or "missing". A tool the box lacks (not the login, ssh, bash or the slots)
  // offers "Set up now", which cannot be sent yet: no action runs test-machine.sh there, so it stays off.
  function lines(c) {
    const h = S.ctx.h, l = last(c);
    if (!l) return null;
    if (!l.rec) { const no = h('p', 'rules-refused', `The check did not run: ${l.error}`); no.setAttribute('role', 'alert'); return no; }
    const ul = h('ul', 'rules-suite-checks');
    l.rec.needs.forEach((n) => {
      const li = h('li', 'rules-suite-check');
      li.append(S.ctx.chip(n.ok ? 'ok' : 'missing', n.ok ? 'ok' : 'bad'), ' ', h('span', null, `${text(n.need)}: ${text(n.detail)}`));
      if (!n.ok && !['ssh', 'bash 5.1+', 'Namespace login', 'test slots'].includes(n.need)) {
        const b = button('Set up now', 'btn-quiet', `suite-setup-${n.need}`, `Set up ${n.need} now`, () => {});
        b.disabled = true;
        li.append(' ', b, ' ', h('span', 'board-from', 'Runs test-machine.sh there. Asks the owner first.'));
      }
      ul.append(li);
    });
    return ul;
  }
  const field = (label, act, value, on) => {
    const h = S.ctx.h, f = h('label', 'rules-suite-field'), i = h('input');
    i.type = 'text'; i.value = value; i.dataset.act = act; i.setAttribute('aria-label', label); i.spellcheck = false;
    i.addEventListener('input', () => on(i.value.trim()));
    f.append(h('span', 'board-from', label), ' ', i);
    return f;
  };
  function devbox(box, c) {
    const h = S.ctx.h, m = rec(c), size = text(m.size) || '4x8', login = loggedIn(c), sizes = SIZES.includes(size) ? SIZES : SIZES.concat([size]);
    const sel = h('select'), cpus = cpusOf(size);
    sel.dataset.act = 'suite-size'; sel.setAttribute('aria-label', 'Devbox size');
    sizes.forEach((s) => { const o = h('option', null, s); o.value = s; o.selected = s === size; sel.append(o); });
    sel.addEventListener('change', () => { if (sel.value !== size) send('suite-machine', ['devbox', '--size', sel.value]); });
    // When the box was set up: the record's setupAt, else said as not kept.
    const setup = Number.isNaN(Date.parse(text(m.setupAt))) ? 'set-up time not kept' : `set up ${S.ctx.when(m.setupAt)}`;
    const after = h('span', null, m.idleStop ? `Keep it, stop it after ${text(m.idleStop).replace(/m$/, ' min')} idle` : 'Delete it');
    const fact = (name, ...kids) => { const p = h('p', 'rules-suite-fact'); p.append(h('span', 'board-from', `${name} `), ...kids); return p; };
    box.append(
      fact('Namespace login', login === null ? S.ctx.chip('not checked', 'quiet') : S.ctx.chip(login ? 'logged in' : 'not logged in', login ? 'ok' : 'bad')),
      fact('Size', sel, ' ', h('span', 'board-from', cpus === null ? '' : `${cpus} CPUs`)),
      fact('After a run', after),
      fact('Box', h('span', null, `Namespace Devbox ${size}${text(m.tag) ? `, reused by its tag ${m.tag}` : ''}, ${setup}`)),
      fact('Tools', h('span', null, 'From .conveyor/test-machine.sh. It runs again only when the script changes.')));
    if (login === false) {
      const cmd = h('code', 'rules-suite-cmd', 'devbox login');
      box.append(h('p', 'rules-suite-fact', 'Log in to Namespace in a terminal on the build machine: '), cmd);
    }
    return login === false;
  }
  function ssh(box, c) {
    const m = kindOf(c) === 'ssh' ? rec(c) : {}, d = drafting() ? DRAFT : null;
    const v = d || { target: text(m.target), dir: text(m.dir) };
    const good = (x) => TARGET.test(x.target) && (!x.dir || FOLDER.test(x.dir));
    // What is typed now: the draft, else the record's.
    const typed = () => (drafting() ? DRAFT : v);
    const save = button('Use this box', 'btn-quiet', 'suite-ssh-use', 'Use this Linux box for the release suite', () => {
      const t = typed();
      if (good(t)) { DRAFT = null; send('suite-machine', argsOf({ kind: 'ssh', target: t.target, dir: t.dir })); }
    });
    // A target or folder being typed is not the saved box: Check stays off until Use this box saves it.
    const edit = (k) => (t) => {
      DRAFT = Object.assign({ repo: S.d.repo }, typed(), { [k]: t }); save.disabled = !good(DRAFT);
      const go = box.querySelector('[data-act="suite-check"]');
      if (go) go.disabled = true;
    };
    save.disabled = !good(v) || (!d && kindOf(c) === 'ssh');
    box.append(field('ssh target', 'suite-ssh-target', v.target, edit('target')), field('Folder there', 'suite-ssh-dir', v.dir, edit('dir')), save);
  }
  // A radio of the choice, labelled with its name and what it means.
  function kindRadio(k, name, what, shown, pick) {
    const h = S.ctx.h, lab = h('label', 'rules-suite-kind'), i = h('input');
    i.type = 'radio'; i.name = 'suite-kind'; i.value = k; i.dataset.act = `suite-${k}`; i.checked = k === shown;
    i.addEventListener('change', () => { if (i.checked) pick(k); });
    lab.append(i, h('strong', null, name), h('span', 'board-from', what));
    return lab;
  }
  function rulesSuite(el, c) {
    const h = S.ctx.h, now = kindOf(c), shown = drafting() ? 'ssh' : now;
    const slots = S.cores && typeof S.cores.slots === 'number' ? S.cores.slots : null;
    const group = h('div', 'rules-suite-kinds');
    group.setAttribute('role', 'radiogroup'); group.setAttribute('aria-label', 'Release suite runs on');
    const pick = (k) => {
      if (k === shown) return;
      if (k === 'ssh') { DRAFT = { repo: S.d.repo, target: '', dir: '' }; draw(); return; }
      DRAFT = null;
      if (k === now) { draw(); return; }  // back to the saved choice from an ssh box picked and not saved
      send('suite-machine', [k]);
    };
    KINDS.forEach(([k, name, what]) => group.append(kindRadio(k, name, what(slots), shown, pick)));
    el.append(row('suite', 'Release suite runs on', 'the machine a release\'s full suite runs on', group, fields(c, shown, now, slots)));
    // A devbox saved is checked when it is shown (its login is what the row needs), and again while the login is missing.
    const l = last(c);
    if (shown === 'devbox' && now === 'devbox' && !OUT && (!l || (loggedIn(c) === false && Date.now() - l.at > AGAIN))) Promise.resolve().then(() => check(c));
  }
  // What the chosen machine shows under the choices: its texts or fields, the buttons and the last check's lines.
  function fields(c, shown, now, slots) {
    const h = S.ctx.h, box = h('div', 'rules-suite');
    let off = false;
    if (shown === 'local') box.append(h('p', 'board-from', `The suite runs here, as now. Its test files share the ${slots === null ? '' : `${slots} `}test slots with the cards.`));
    if (shown === 'devbox') off = devbox(box, c);
    if (shown === 'ssh') ssh(box, c);
    const go = button('Check the box', 'btn-quiet', 'suite-check', 'Check the release suite machine', () => check(c));
    go.disabled = OUT || off || shown !== now || shown === 'local' || drafting();
    const back = shown === 'devbox' ? button('Use this machine', 'btn-quiet', 'suite-use-local', 'Run the release suite on this machine', () => send('suite-machine', ['local'])) : null;
    if (shown !== 'local') box.append(go);
    if (back) box.append(back);
    const out = lines(c);
    if (out && shown === now) box.append(out);
    return box;
  }
  window.DASH_APP.part('rules-suite', function (shared) {
    ({ S, num, send, button, post, row, draw } = shared);
    return { rulesSuite, suiteSlots, undoArgs };
  });
})();
