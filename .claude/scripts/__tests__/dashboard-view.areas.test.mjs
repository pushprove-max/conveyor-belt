// SPDX-License-Identifier: Apache-2.0
// An area's name on the Board from a pack whose area prefix does not hold the separator (`labels.areaPrefix` "area",
// labels "area:x"). Bug (issue 289): the name kept the colon, so the held list grouped an area as ":x".
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, full, act, panel, board, groupsOf, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

const P = 'https://github.com/example/sample/issues';
function bare() {
  const d = full();
  const issues = [{ repo: 'sample', issue: 76, title: 'Sample open issue', url: `${P}/76`, priority: 'P1', labels: ['P1', 'area:x'], created: '2026-11-01T00:00:00Z' }];
  d.panels.rules.data.areaPrefix = 'area';
  d.panels.rules.data.open.held[0].labels = ['P1', 'area:x'];
  d.panels.rules.data.open.issues = issues;
  d.panels.board.data.areaPrefix = 'area';
  d.panels.board.data.open = { ...(d.panels.board.data.open || {}), issues };
  return d;
}
const texts = (sel) => Array.from(sel.options, (o) => o.textContent);

test('Areas: with the prefix "area", the held list groups the label area:x as x, not :x', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, bare());
  assert.deepEqual(groupsOf(w).map((g) => g[0]).sort(), ['web', 'x']);
});

test('Areas: with the prefix "area", the open-issues list and its area filter name the area without the colon', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, bare());
  const list = panel(w, 'rules-issues');
  assert.match(list.querySelector('.rules-issue[data-issue="76"] .board-from').textContent, /^x$/);
  assert.deepEqual(texts(act(list, 'iarea')), ['Any area', 'x']);
});

test('Areas: with the prefix "area", the Board\'s area filter names the area without the colon', () => {
  const w = boot({ tab: 'control' });
  deliver(w, bare());
  assert.deepEqual(texts(act(board(w), 'barea')), ['Any area', 'x']);
});
