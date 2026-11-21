// SPDX-License-Identifier: Apache-2.0
// The config of ESLint, the pack's lint command for the Board's JavaScript (.conveyor/project.json, lint;
// .conveyor/lint-js.sh): ESLint's recommended rules, the complexity rules complexity, max-lines-per-function and
// max-depth with their limits, and the globals the Board's files share.
'use strict';
const js = require('@eslint/js');

// The browser's names the Board's files use without `window.`, and the Board's own names that one file sets on
// window and others read (panels/index.js, app.js, belt3d-scene.js).
const shared = {
  window: 'readonly',
  document: 'readonly',
  navigator: 'readonly',
  setTimeout: 'readonly',
  URL: 'readonly',
  URLSearchParams: 'readonly',
  DASH: 'readonly',
  DASH_ALIVE: 'readonly',
  DASH_APP: 'readonly',
  DASH_BELT3D_SCENE: 'readonly',
  DASH_PANELS: 'readonly',
};

module.exports = [
  {
    files: ['**/*.js'],
    ...js.configs.recommended,
    languageOptions: { sourceType: 'script', globals: shared },
    rules: {
      ...js.configs.recommended.rules,
      complexity: ['error', 20],
      'max-lines-per-function': ['error', 50],
      'max-depth': ['error', 4],
    },
  },
  // The 3D floor is the one ES module of the Board: panels/belt3d.js loads it with import().
  { files: ['.claude/dashboard/belt3d-scene.js'], languageOptions: { sourceType: 'module' } },
];
