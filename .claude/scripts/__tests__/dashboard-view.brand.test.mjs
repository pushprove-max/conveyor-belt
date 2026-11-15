// SPDX-License-Identifier: Apache-2.0
// The head's name on its slim moving belt (issue 343): motion changes no box, a small phone keeps the belt inside
// the name's box, and a screen reader still hears "Conveyor Board". Shared setup: dashboard-view.helpers.mjs.
// jsdom lays nothing out, so the sizes are held by what the stylesheet lets the motion touch.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { css, boot, $ } from './dashboard-view.helpers.mjs';

const START = '/* ---- the name\'s belt ---- */', END = '/* ---- end of the name\'s belt ---- */';
const belt = css.slice(css.indexOf(START), css.indexOf(END));
const PARTS = ['belt', 'roller', 'lane', 'parcel'];
const rule = (text, sel) => {
  const m = new RegExp(`(?:^|\\n)\\s*${sel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} \\{([^}]*)\\}`).exec(text);
  assert.ok(m, `a rule for ${sel}`);
  return m[1];
};
// What a screen reader reads: the text outside every aria-hidden part, its spaces collapsed.
const spoken = (el) => {
  if (el.nodeType === 3) return el.textContent;
  if (el.nodeType !== 1 || el.getAttribute('aria-hidden') === 'true') return '';
  return Array.from(el.childNodes, spoken).join('');
};

test('the belt\'s motion changes no box: the head and the name are the same size with motion on and under reduced motion', () => {
  assert.ok(css.indexOf(START) > 0 && css.indexOf(END) > css.indexOf(START), 'the name\'s belt is one marked section');
  // Each moving part is out of flow, so neither it nor its motion sizes the name, the .brand box or the head.
  for (const p of PARTS) assert.match(rule(belt, `.brand .${p}`), /position: absolute;/, `.${p} is out of flow`);
  assert.match(rule(belt, '.brand .belt::before'), /position: absolute;/);
  assert.match(rule(belt, '.brand .belt'), /overflow: hidden;/, 'the moving tread is clipped to the belt');
  // The motion is transform and opacity only, which move nothing else; this was a background-position in the
  // mockup, held to transform here.
  const used = Array.from(belt.matchAll(/animation: (\w+) /g), (m) => m[1]);
  assert.deepEqual(used.sort(), ['brandfade', 'brandride', 'brandspin', 'brandtread'], 'tread, rollers, ride and fade all move');
  for (const name of used) {
    const body = new RegExp(`@keyframes ${name} \\{((?:[^{}]*\\{[^{}]*\\})+)\\s*\\}`).exec(belt);
    assert.ok(body, `@keyframes ${name} is in the belt's section`);
    for (const [, prop] of body[1].matchAll(/([a-z-]+)\s*:/g)) assert.ok(['transform', 'opacity'].includes(prop), `${name} animates ${prop}`);
  }
  // Reduced motion (the system's and the page's own switch) stops the animations and touches nothing else, so the
  // belt still shows at the same size; the parcel, drawn only by its animation, is not left standing at one end.
  for (const [, body] of css.matchAll(/(?:prefers-reduced-motion: reduce\) \{\s*|:root\[data-motion="off"\][^{]*)\{([^}]*)\}/g)) {
    assert.equal(body.trim(), 'animation: none !important; transition: none !important;');
  }
  assert.match(rule(belt, '.brand .parcel'), /opacity: 0;/);
  assert.doesNotMatch(rule(belt, '.brand .belt'), /animation/, 'the belt itself is drawn with no motion');
  // And the page itself sets nothing on the name by motion: the head's markup is the same either way.
  const on = boot(), off = boot({ reducedMotion: true });
  assert.equal(off.document.documentElement.dataset.motion, 'off');
  assert.equal($(off, '.top .brand').outerHTML, $(on, '.top .brand').outerHTML);
});

test('on a phone under 420 px the belt and rollers stay inside the name\'s box and the name shortens inside it', () => {
  const small = css.slice(css.indexOf('@media (max-width: 420px)'));
  const word = rule(small, '.brand .word');
  // Without this the inline-block name was clipped whole by the head's ellipsis, and the belt and rollers hung
  // below and beside the name's box, cut off by the h1.
  assert.match(word, /display: block;[^]*min-width: 0;[^]*padding: 0 6px 10px;[^]*overflow: hidden;[^]*text-overflow: ellipsis;/);
  assert.match(rule(small, '.brand .belt, .brand .lane'), /left: 6px; right: 6px;/);
  // The belt, its lane and the rollers sit in the name's bottom padding at every width (issue 347), not below it.
  assert.match(rule(belt, '.brand .word'), /padding-bottom: 10px;/);
  assert.match(rule(belt, '.brand .belt'), /bottom: 2px;/);
  assert.match(rule(belt, '.brand .lane'), /bottom: 8px;/);
  assert.match(rule(belt, '.brand .roller'), /bottom: 0;/);
  assert.match(rule(small, '.brand .roller.l'), /left: 0;/);
  assert.match(rule(small, '.brand .roller.r'), /right: 0;/);
  // Nothing in the small-phone rules sets a negative offset on the belt's parts.
  const parts = small.slice(small.indexOf('.brand .word'), small.indexOf('.brand .roller.r'));
  assert.doesNotMatch(parts, /: -\d/);
});

test('the head\'s name reads "Conveyor Board" to a screen reader; the belt\'s parts are hidden from it', () => {
  const w = boot();
  const h1 = $(w, '.top .brand h1');
  assert.equal(spoken(h1).replace(/\s+/g, ' ').trim(), 'Conveyor Board');
  const word = h1.querySelector('.word');
  assert.ok(word, 'the name sits on its belt');
  for (const p of ['belt', 'roller.l', 'roller.r', 'lane']) {
    const el = word.querySelector(`:scope > .${p}`);
    assert.ok(el, `.${p} is drawn`);
    assert.equal(el.getAttribute('aria-hidden'), 'true', `.${p} is hidden from a screen reader`);
  }
  assert.ok(word.querySelector('.lane > .parcel'), 'the parcel rides in its lane');
  assert.equal(word.querySelector('.w').textContent, 'Conveyor');
});
