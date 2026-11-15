// SPDX-License-Identifier: Apache-2.0
// The Tests page on a phone (issue 556): the figures, the filters and the table ran past the panel to about 1,120 px,
// and the File column was squeezed to one letter a line. jsdom lays nothing out and the owner allows no browser test,
// so these cases read app.css, as the other Board layout tests do.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const css = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), '../../dashboard/app.css'), 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '');

// The declarations of every rule whose selector list names `sel` exactly, merged in order (a later one wins).
function decls(sel) {
  const out = {};
  for (const [, sels, body] of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    if (!sels.split(',').map((s) => s.trim()).includes(sel)) continue;
    for (const d of body.split(';')) {
      const i = d.indexOf(':');
      if (i > 0) out[d.slice(0, i).trim()] = d.slice(i + 1).trim();
    }
  }
  return out;
}
// The Tests page's own grid containers: each selector of the form .tests or .tests-<word> in a rule that sets
// display: grid.
const grids = () => [...new Set([...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)]
  .filter(([, , body]) => /(^|;)\s*display:\s*grid\s*(;|$)/.test(body))
  .flatMap(([, sels]) => sels.split(',').map((s) => s.trim()))
  .filter((s) => /^\.tests(-[a-z-]+)?$/.test(s)))].sort();
const shrinks = (sel) => /^minmax\(0,[^)]*\)$/.test(decls(sel)['grid-template-columns'] || '');

// Bug: .tests had no column template, so its one column took the min-content width of the table. .tests-scroll grew
// to the table's full width, its overflow-x never took effect, and the whole page scrolled sideways.
test('Tests on a phone: .tests has one column of minmax(0, 1fr), so the table scrolls inside .tests-scroll and not the page', () => {
  assert.equal(decls('.tests').display, 'grid');
  assert.equal(decls('.tests')['grid-template-columns'], 'minmax(0, 1fr)');
  assert.equal(decls('.tests-scroll')['overflow-x'], 'auto');
});

// Bug: .tests-name had overflow-wrap: anywhere and no least width, so the browser shrank the File column first, to
// one letter, and each row was about 600 px tall.
test('Tests on a phone: the File column (.tests-name) is at least 20ch wide', () => {
  const m = /^(\d+(?:\.\d+)?)ch$/.exec(decls('.tests-name')['min-width'] || '');
  assert.ok(m, `.tests-name min-width in ch: ${decls('.tests-name')['min-width']}`);
  assert.ok(Number(m[1]) >= 20, `.tests-name min-width ${m[0]} is under 20ch`);
});

// The same fault one level down: a grid that holds a <pre>, a table or a sideways-scrolling block, with no shrinkable
// column, grows to its widest line and runs past the panel. Each grid of the Tests page is named here with what it
// holds; a new one fails the last assertion until it is put in one list or the other.
const HOLDS = {
  '.tests': 'the figures, the filters, .tests-scroll with the table, and Auto-file with its preview table',
  '.tests-more': 'an opened row: its runs and .tests-acts',
  '.tests-acts': 'the actions of a row, .tests-preview and .tests-box',
  '.tests-box': 'the progress output, <pre class="tests-out">',
  '.tests-preview': 'the text fields of an issue, a close or a case kept off',
  '.tests-rule': 'the fields of one auto-file rule',
  '.tests-results-list': 'a result viewed, with its .tests-box',
};
const TEXT_ONLY = {
  '.tests-runs': 'one line of text a run',
  '.tests-list': 'one line of text a file',
  '.tests-auto-log': 'one line of text an event',
};
test('Tests on a phone: each grid on the Tests page that holds a table, a <pre> or a scrolling block has a shrinkable column', () => {
  for (const sel of Object.keys(HOLDS)) {
    assert.equal(decls(sel).display, 'grid', `${sel} is a grid`);
    assert.ok(shrinks(sel), `${sel} (${HOLDS[sel]}) has one column of minmax(0, …)`);
  }
  assert.deepEqual(grids(), [...Object.keys(HOLDS), ...Object.keys(TEXT_ONLY)].sort(), 'every grid of the Tests page is in HOLDS or TEXT_ONLY');
});
