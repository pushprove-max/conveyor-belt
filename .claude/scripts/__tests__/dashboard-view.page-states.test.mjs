// SPDX-License-Identifier: Apache-2.0
// The dashboard page as a whole, the second half of the panel list's three states (data, empty, failed to load) and
// each one drawn from its own part; dashboard-view.page-panels holds the first half, so the runner runs the two side
// by side. One `test(` line a case, so the runner counts them all (dashboard-view.helpers.mjs, PANEL_STATES).
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { panelState, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// ---- each panel: data, empty, failed to load ----
test('tests: with data', () => assert.equal(panelState.data('tests'), 'ready'));
test('tests: empty', () => assert.equal(panelState.empty('tests'), 'empty'));
test('tests: failed to load', () => assert.equal(panelState.failed('tests'), 'error'));
test('tests: draws from its own part alone', () => assert.equal(panelState.own('tests'), 'ready'));
test('bench: with data', () => assert.equal(panelState.data('bench'), 'ready'));
test('bench: empty', () => assert.equal(panelState.empty('bench'), 'empty'));
test('bench: failed to load', () => assert.equal(panelState.failed('bench'), 'error'));
test('bench: draws from its own part alone', () => assert.equal(panelState.own('bench'), 'ready'));
test('queue: with data', () => assert.equal(panelState.data('queue'), 'ready'));
test('queue: empty', () => assert.equal(panelState.empty('queue'), 'empty'));
test('queue: failed to load', () => assert.equal(panelState.failed('queue'), 'error'));
test('queue: draws from its own part alone', () => assert.equal(panelState.own('queue'), 'ready'));
test('landed: with data', () => assert.equal(panelState.data('landed'), 'ready'));
test('landed: empty', () => assert.equal(panelState.empty('landed'), 'empty'));
test('landed: failed to load', () => assert.equal(panelState.failed('landed'), 'error'));
test('landed: draws from its own part alone', () => assert.equal(panelState.own('landed'), 'ready'));
test('release: with data', () => assert.equal(panelState.data('release'), 'ready'));
test('release: empty', () => assert.equal(panelState.empty('release'), 'empty'));
test('release: failed to load', () => assert.equal(panelState.failed('release'), 'error'));
test('release: draws from its own part alone', () => assert.equal(panelState.own('release'), 'ready'));
test('declined: with data', () => assert.equal(panelState.data('declined'), 'ready'));
test('declined: empty', () => assert.equal(panelState.empty('declined'), 'empty'));
test('declined: failed to load', () => assert.equal(panelState.failed('declined'), 'error'));
test('declined: draws from its own part alone', () => assert.equal(panelState.own('declined'), 'ready'));
test('health: with data', () => assert.equal(panelState.data('health'), 'ready'));
test('health: empty', () => assert.equal(panelState.empty('health'), 'empty'));
test('health: failed to load', () => assert.equal(panelState.failed('health'), 'error'));
test('health: draws from its own part alone', () => assert.equal(panelState.own('health'), 'ready'));
test('lanes: with data', () => assert.equal(panelState.data('lanes'), 'ready'));
test('lanes: empty', () => assert.equal(panelState.empty('lanes'), 'empty'));
test('lanes: failed to load', () => assert.equal(panelState.failed('lanes'), 'error'));
test('lanes: draws from its own part alone', () => assert.equal(panelState.own('lanes'), 'ready'));
test('cost: with data', () => assert.equal(panelState.data('cost'), 'ready'));
test('cost: empty', () => assert.equal(panelState.empty('cost'), 'empty'));
test('cost: failed to load', () => assert.equal(panelState.failed('cost'), 'error'));
test('cost: draws from its own part alone', () => assert.equal(panelState.own('cost'), 'ready'));
test('metrics: with data', () => assert.equal(panelState.data('metrics'), 'ready'));
test('metrics: empty', () => assert.equal(panelState.empty('metrics'), 'empty'));
test('metrics: failed to load', () => assert.equal(panelState.failed('metrics'), 'error'));
test('metrics: draws from its own part alone', () => assert.equal(panelState.own('metrics'), 'ready'));
