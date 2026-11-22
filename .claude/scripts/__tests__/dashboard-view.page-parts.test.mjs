// SPDX-License-Identifier: Apache-2.0
// The page loaded as a browser loads it, with app.js and the panel files split into parts (parts/): index.html's
// scripts, then each file boot.js adds (app.js's parts, then those panels/index.js lists), run in its order
// (boot({ loader: true })). The other
// cases load the files themselves (helpers.mjs boot). Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { VIEW, LIST, PARTS, TAB, family, boot, deliver, full, state, panel, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const added = (w) => Array.from(w.document.head.querySelectorAll('script[src]'), (s) => s.getAttribute('src')).filter((s) => /^(parts|panels)\//.test(s));

// Bug it catches: a file in parts/ that app.js (DASH_APP.parts) or panels/index.js does not list, or lists after the
// file that asks for it, is not there when that file runs: its panel says it is missing (drawn with the ready state,
// so the text is checked too), and a part of app.js missing leaves no panel drawn.
test('the page loads every part before the panels, and each panel of every tab draws from the split files', () => {
  const w = boot({ loader: true });
  const parts = [...w.DASH_APP.parts, ...PARTS];
  assert.deepEqual(parts.slice().sort(), fs.readdirSync(path.join(VIEW, 'parts')).map((f) => `parts/${f}`).sort(), 'app.js and panels/index.js list each file in parts/ once');
  assert.deepEqual(added(w), [...parts, ...LIST.map((id) => `panels/${id}.js`)], 'the parts first, app.js\'s before the panel files\', then one file a panel, in the list\'s order');
  assert.deepEqual(w.scriptErrors, [], 'no file threw as it loaded');
  deliver(w, full());
  for (const tab of [...new Set(LIST.map(TAB))]) {
    w.document.getElementById(`tab-${tab}`).click();
    for (const id of LIST.flatMap(family).filter((x) => TAB(x) === tab)) {
      assert.equal(state(w, id), 'ready', `${id} draws on the ${tab} tab`);
      // A panel that did not register is drawn as ready too, by missing() (app.js): its text tells it apart.
      assert.doesNotMatch(panel(w, id).textContent, /This panel is missing/, `${id} registered from its file`);
    }
  }
});

// Bug it catches (R2): a part of app.js that failed to load (parts/app-feed.js answering 404) still had the page start
// on code it lacked, and start() threw an uncaught error, leaving the page on its skeleton with no word of why.
test('a part of app.js that did not load leaves a Reload message and starts nothing', () => {
  const w = boot({ loader: true, failing: ['parts/app-feed.js'] });
  // The panel files that load after it may throw for the missing part (as in a browser); start() is not run, so it throws nothing.
  assert.ok(w.scriptErrors.every((e) => /DASH_APP\.\w+ is not a function/.test(e)), `only missing-part errors: ${w.scriptErrors.join('; ')}`);
  const grid = w.document.getElementById('grid');
  assert.match(grid.textContent, /could not load all of its files/);
  assert.equal(grid.querySelector('button').textContent, 'Reload');
  assert.equal(grid.getAttribute('aria-busy'), 'false');
});

// Bug it catches: a panel file whose part did not load went on with half its code and threw at its first draw, or
// stopped with no word of which file was missing; it stops at once, naming the part, and its panel says it is missing.
test('a panel whose part did not load says it is missing, and the other panels still draw', () => {
  const w = boot({ loader: true, failing: ['parts/tests-rows.js'] });
  assert.deepEqual(w.scriptErrors, ['parts/tests-rows.js did not load']);
  deliver(w, full());
  // A list entry that did not register keeps its place on the Overview tab (missing(), app.js).
  assert.match(panel(w, 'tests').textContent, /This panel is missingIts code did not load/);
  assert.equal(state(w, 'needs'), 'ready', 'Needs you draws');
});
