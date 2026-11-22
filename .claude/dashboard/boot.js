// SPDX-License-Identifier: Apache-2.0
// Loads the parts of app.js (DASH_APP.parts), then those of the panel files (DASH_PARTS), then one file per panel
// (DASH_PANELS), the last two listed in panels/index.js, in their order; then starts the page. A panel file or a part
// of one that fails to load does not hold the others: its panel says so in its own place. A part of app.js that fails
// to load leaves the page without code it needs, so the page does not start: it says to reload, with a Reload button.
(function () {
  'use strict';
  const ids = Array.isArray(window.DASH_PANELS) ? window.DASH_PANELS : [];
  const list = (x) => (Array.isArray(x) ? x : []);
  const appParts = list(window.DASH_APP.parts);
  const files = appParts.concat(list(window.DASH_PARTS), ids.map((id) => `panels/${id}.js`));
  let left = files.length, lost = false;
  const reload = () => {
    const box = document.createElement('div'), btn = document.createElement('button');
    box.className = 'banner';
    box.setAttribute('role', 'alert');
    btn.type = 'button';
    btn.className = 'btn';
    btn.textContent = 'Reload';
    btn.addEventListener('click', () => window.location.reload());
    box.append('The page could not load all of its files. ', btn);
    const grid = document.getElementById('grid');
    if (grid) { grid.replaceChildren(box); grid.setAttribute('aria-busy', 'false'); } else document.body.prepend(box);
  };
  const done = () => { left -= 1; if (left <= 0) { if (lost) reload(); else window.DASH_APP.start(); } };
  if (!files.length) { window.DASH_APP.start(); return; }
  files.forEach((src) => {
    const s = document.createElement('script');
    s.src = src;
    s.async = false;
    s.addEventListener('load', done);
    s.addEventListener('error', () => { if (appParts.includes(src)) lost = true; done(); });
    document.head.append(s);
  });
}());
