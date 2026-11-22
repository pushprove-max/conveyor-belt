// SPDX-License-Identifier: Apache-2.0
// A Board refresh never moves the reader's place (#557): a draw that puts the focus back on the new copy of a control
// sets preventScroll, or a reader who clicked a control and then scrolled away was pulled back to it at each refresh.
// Read from the code: jsdom lays nothing out, so no draw in it scrolls.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const VIEW = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'dashboard');
// The focus calls a reader's own action makes (a click, a key, a form sent), by file and what is focused: these move
// the focus to where the reader acts, and may scroll it into view. Every other .focus( is a draw's and keeps the page.
const ACTION = {
  'account.js': ['code', 'code'],
  'app.js': ['p.grip', 'byId(`tab-${nt}`)', 'drag', '(tools.up.disabled ? tools.down : tools.up)', '(tools.down.disabled ? tools.up : tools.down)',
    'next', 'showAll', 'showAll', 'open', 'open', 'btn', 'row', 'close', 'back', 'f'],
  'login.js': ["byId(on ? 'login-code-input' : 'login-secret')", '(user.value ? secret : user)', 'secret', 'input', 'input', "byId('login-code-input')"],
  'panels/metrics.js': ['again'],
  'panels/needs.js': ['acts[k].field'],
  'panels/rules.js': ['again', 'all[all.length - 1]', 'all[0]'],
  'panels/tests.js': ['items[(at + step + items.length) % items.length]'],
};

function files(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name);
    return e.isDirectory() ? files(p) : e.name.endsWith('.js') ? [p] : [];
  });
}

test('every .focus( a draw or refresh makes in .claude/dashboard sets preventScroll: true', () => {
  const left = Object.fromEntries(Object.entries(ACTION).map(([f, l]) => [f, [...l]]));
  const bad = [];
  let drawn = 0;
  for (const file of files(VIEW)) {
    const rel = path.relative(VIEW, file).split(path.sep).join('/'), src = fs.readFileSync(file, 'utf8');
    for (const m of src.matchAll(/\.focus\(/g)) {
      const line = src.slice(0, m.index).split('\n').length;
      if (/^\s*\{\s*preventScroll:\s*true\s*\}\s*\)/.test(src.slice(m.index + m[0].length))) { drawn += 1; continue; }
      const before = src.slice(0, m.index), mine = left[rel] || [], at = mine.findIndex((r) => before.endsWith(r));
      if (at >= 0) mine.splice(at, 1);
      else bad.push(`${rel}:${line}`);
    }
  }
  assert.deepEqual(bad, [], 'a focus a draw makes without { preventScroll: true }');
  assert.deepEqual(Object.entries(left).filter(([, l]) => l.length), [], 'each action focus listed is still in the code');
  assert.ok(drawn >= 11, `the draws' focus calls are found (${drawn})`);
});
