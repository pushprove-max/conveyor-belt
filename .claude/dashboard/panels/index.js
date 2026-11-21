// SPDX-License-Identifier: Apache-2.0
// The one list of panels, in their default order. Adding a panel is one file here, panels/<id>.js, and one entry.
window.DASH_PANELS = ['machine', 'board','rules', 'needs', 'belt', 'belt3d', 'tests', 'bench', 'queue', 'landed', 'release', 'declined', 'health', 'lanes', 'cost', 'metrics'];
// The files split from the panel files (parts/), loaded after app.js's own parts (app.js, DASH_APP.parts) and before
// the panels: each panel file's, in the order that file asks for them.
window.DASH_PARTS = ['parts/board-filters.js', 'parts/board-push.js', 'parts/board-cards.js',
  'parts/rules-prices.js', 'parts/rules-moves.js', 'parts/rules-rows.js', 'parts/rules-produce.js', 'parts/rules-setup.js',
  'parts/tests-mutation.js', 'parts/tests-actions.js', 'parts/tests-rows.js'];
