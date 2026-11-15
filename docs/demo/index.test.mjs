// SPDX-License-Identifier: Apache-2.0
// The demo's composition (index.html), as make.sh renders it: the beats in their order and times, the Claude Code
// beats as their clips, and no visible text about how the demo is made.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { JSDOM } from 'jsdom';

const HTML = readFileSync(new URL('./index.html', import.meta.url), 'utf8');
// Each beat's section: its start, its length and its caption's number and text.
const beats = [...HTML.matchAll(/<section [^>]*data-start="([\d.]+)" data-duration="([\d.]+)">([\s\S]*?)<\/section>/g)]
  .map(([, start, length, body]) => {
    const cap = body.match(/<div class="cap"><b>(\d+)<\/b>([^<]*)<\/div>/);
    return { start: Number(start), length: Number(length), n: cap && Number(cap[1]), caption: cap && cap[2], body };
  });

// Bug caught: the Tests or the Foreman beat is lost, moved or loses its caption; /units or the Foreman is cut back to
// a hurried length in place of the owner's 9 s and 14 s; or a beat's time overlaps the beats beside it, or the root
// ends before or after the last beat, so the cut shows two beats at once, a gap, or a blank end.
test('the composition: Tests after Rules, /units 9 s, the Foreman 14 s, no gap or overlap, the root as long as the beats', () => {
  assert.deepEqual(beats.map((b) => b.n), [null, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, null]);
  assert.match(beats[7].caption, /^Rules:/);
  assert.match(beats[8].caption, /^Tests:/);
  assert.match(beats[8].body, /<video [^>]*src="captures\/tests\.mp4"[^>]*data-duration="11"/, 'the Tests beat plays its capture, its section long');
  assert.match(beats[9].caption, /^\/units/);
  assert.equal(beats[9].length, 9);
  assert.equal(beats[10].caption, 'Foreman: it asks, you pick, the card is back');
  assert.equal(beats[10].length, 14);
  beats.slice(1).forEach((b, i) => assert.equal(b.start, beats[i].start + beats[i].length, `beat ${i + 2} starts where beat ${i + 1} ends`));
  const end = beats.at(-1);
  assert.equal(Number(HTML.match(/id="root"[^>]*data-duration="([\d.]+)"/)[1]), end.start + end.length);
});

// Bug caught: beat 10 or 11 shows a card of text in place of the real Claude Code clip that record-cli.sh records, or
// its clip is cut short or overruns its section.
test('beats 10 and 11 are the Claude Code clips, each its section long', () => {
  for (const [i, clip] of [[9, 'beat9'], [10, 'foreman']]) {
    const video = beats[i].body.match(new RegExp(`<video [^>]*src="captures/${clip}\\.mp4"[^>]*data-duration="([\\d.]+)"`));
    assert.ok(video, `beat ${i + 1} plays captures/${clip}.mp4`);
    assert.equal(Number(video[1]), beats[i].length);
    assert.equal(beats[i].body.replace(/<!--[\s\S]*?-->/g, '').match(/<div /g).length, 1, `beat ${i + 1} shows its clip and caption, nothing more`);
  }
});

// Bug caught: the end card shows only `/plugin install`, which fails until the marketplace is added, or its install
// lines drift from the README's Install section, so a viewer types lines that do not install the plugin.
test("the end card's install lines are the README's Install section's, in its order", () => {
  const readme = readFileSync(new URL('../../README.md', import.meta.url), 'utf8');
  const install = readme.match(/^## Install\n([\s\S]*?)^## /m)[1];
  const readmeLines = [...install.matchAll(/`(\/plugin (?:marketplace add|install) [^`]+)`/g)].map((m) => m[1]);
  assert.equal(readmeLines.length, 2, 'the README gives the marketplace add and the plugin install');
  const { document } = new JSDOM(beats.at(-1).body).window;
  assert.deepEqual([...document.querySelectorAll('.cmd')].map((e) => e.textContent), readmeLines);
});

// Bug caught: beat 2 shows `conveyor.sh setup ...` typed in a shell, a line no user types, with the plugin installed off
// screen, in place of the install the README gives in Claude Code.
test("beat 2's recorded lines are the README's install: the two /plugin lines, then /conveyor-belt:setup", () => {
  const shown = readFileSync(new URL('./captures/beat2.txt', import.meta.url), 'utf8');
  const typed = shown.split('\n').filter((l) => l.startsWith('> '));
  assert.deepEqual(typed, ['> /plugin marketplace add pushprove-max/conveyor-belt', '> /plugin install conveyor-belt@conveyor-belt', '> /conveyor-belt:setup']);
  assert.doesNotMatch(shown, /conveyor\.sh setup/);
  assert.match(shown, /^ok: /m, 'conveyor doctor ran');
  assert.doesNotMatch(shown, /^missing/m);
  assert.match(beats[1].caption, /\/plugin install, \/conveyor-belt:setup, conveyor doctor/);
});

// The owner's order: a product demo shows the product, never how the video was made. Bug caught: a caption, card or
// title says a clip is recorded elsewhere, is not recorded yet, or names the mock, the container or make.sh.
test('no visible text of the composition says how the demo is made', () => {
  const { document } = new JSDOM(HTML).window;
  document.querySelectorAll('script, style').forEach((e) => e.remove());
  const shown = [document.title, document.body.textContent,
    ...[...document.querySelectorAll('[title], [alt], [aria-label]')].flatMap((e) => ['title', 'alt', 'aria-label'].map((a) => e.getAttribute(a) || ''))].join('\n');
  assert.match(shown, /Foreman: it asks, you pick/, 'the captions are read');
  for (const word of [/\brecord(ed)?\b/i, /\binvented\b/i, /\bmock\b/i, /\bsandbox\b/i, /\bcontainer\b/i, /make\.sh/i]) {
    assert.doesNotMatch(shown, word);
  }
});
