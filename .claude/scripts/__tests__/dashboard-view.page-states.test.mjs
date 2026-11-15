// SPDX-License-Identifier: Apache-2.0
// The dashboard page as a whole, the second half of the panel list's three states (data, empty, failed to load) and
// each one drawn from its own part; dashboard-view.page-panels holds the first half, so the runner runs the two side
// by side. One `test(` line a case, so the runner counts them all (dashboard-view.helpers.mjs, PANEL_STATES).
// Shared setup: dashboard-view.helpers.mjs.
import { panelState, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// ---- each panel: data, empty, failed to load ----
test('tests: with data', () => panelState.data('tests'));
test('tests: empty', () => panelState.empty('tests'));
test('tests: failed to load', () => panelState.failed('tests'));
test('tests: draws from its own part alone', () => panelState.own('tests'));
test('queue: with data', () => panelState.data('queue'));
test('queue: empty', () => panelState.empty('queue'));
test('queue: failed to load', () => panelState.failed('queue'));
test('queue: draws from its own part alone', () => panelState.own('queue'));
test('landed: with data', () => panelState.data('landed'));
test('landed: empty', () => panelState.empty('landed'));
test('landed: failed to load', () => panelState.failed('landed'));
test('landed: draws from its own part alone', () => panelState.own('landed'));
test('release: with data', () => panelState.data('release'));
test('release: empty', () => panelState.empty('release'));
test('release: failed to load', () => panelState.failed('release'));
test('release: draws from its own part alone', () => panelState.own('release'));
test('declined: with data', () => panelState.data('declined'));
test('declined: empty', () => panelState.empty('declined'));
test('declined: failed to load', () => panelState.failed('declined'));
test('declined: draws from its own part alone', () => panelState.own('declined'));
test('health: with data', () => panelState.data('health'));
test('health: empty', () => panelState.empty('health'));
test('health: failed to load', () => panelState.failed('health'));
test('health: draws from its own part alone', () => panelState.own('health'));
test('lanes: with data', () => panelState.data('lanes'));
test('lanes: empty', () => panelState.empty('lanes'));
test('lanes: failed to load', () => panelState.failed('lanes'));
test('lanes: draws from its own part alone', () => panelState.own('lanes'));
test('cost: with data', () => panelState.data('cost'));
test('cost: empty', () => panelState.empty('cost'));
test('cost: failed to load', () => panelState.failed('cost'));
test('cost: draws from its own part alone', () => panelState.own('cost'));
test('metrics: with data', () => panelState.data('metrics'));
test('metrics: empty', () => panelState.empty('metrics'));
test('metrics: failed to load', () => panelState.failed('metrics'));
test('metrics: draws from its own part alone', () => panelState.own('metrics'));
