// SPDX-License-Identifier: Apache-2.0
// Panels in a narrow place (issue 1430): the Metrics charts in a very narrow panel, the Release changes in its Small
// column and the Rules' produce tiles in a small panel. jsdom lays nothing out and reads no @container rule, so each
// case reads the rule of app.css that sets it: no width, scrollWidth or computed grid can be measured here.
import assert from 'node:assert/strict';
import { css, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
// The declarations of the first rule whose selector list is exactly `sel`, at the start of a line (no layout: see above).
const rule = (sel, from = css) => (from.match(new RegExp(`(?:^|\\n)\\s*${sel.replace(/[.[\]"=()>*]/g, (m) => `\\${m}`)}\\s*\\{([^}]*)\\}`)) || [])[1] || '';

// Bug it guards: the chart track was at least 240px, so below a 290px viewport (a fold phone's 280px cover screen) it
// overflowed the panel. The track is at most the panel's width.
test('Metrics: a chart track is never wider than its panel (minmax(min(240px, 100%), 1fr))', () => {
  assert.match(rule('.metric-charts'), /grid-template-columns: repeat\(auto-fit, minmax\(min\(240px, 100%\), 1fr\)\)/);
});

// Bug it guards: a change's title was cut with "…" on one line, though the Release panel is Small by default and its
// header says every line wraps in that column.
test('Release: a change\'s title wraps, and is never cut with an ellipsis', () => {
  const r = rule('.release-change-title');
  assert.ok(r, 'the rule of a change\'s title');
  assert.doesNotMatch(r, /white-space: nowrap|text-overflow: ellipsis/);
  assert.match(r, /white-space: normal/);
  assert.match(r, /overflow-wrap: anywhere/);
});

// Bug it guards: the four tiles of What these rules produce were four across in a small panel (a third of a 1280px
// window, about 57px a tile), so "waiting on another card" wrapped a word a line. By the panel's own width, a small
// panel lays them two across.
test('Rules: the produce tiles go two across in a small produce panel, by the panel\'s own width', () => {
  assert.match(rule('.panel[data-panel="rules-produce"] > .panel-body'), /container: rules-produce \/ inline-size/);
  const q = /@container rules-produce \(max-width: (\d+)px\) \{([^@]*?)\}\s*\}/.exec(css);
  assert.ok(q, 'a container rule of the produce panel');
  assert.ok(Number(q[1]) >= 400, `a 400px panel is within it: ${q[1]}px`);
  assert.match(q[2], /\.rules-stats \{ grid-template-columns: repeat\(2, minmax\(0, 1fr\)\);/);
});
