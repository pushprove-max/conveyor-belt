// SPDX-License-Identifier: Apache-2.0
// Loads the parts of app.js (DASH_APP.parts), then those of the panel files (DASH_PARTS), then one file per panel
// (DASH_PANELS), the last two listed in panels/index.js, in their order; then starts the page. A file that fails to
// load does not hold the others: its panel says so in its own place.
(function () {
  'use strict';
  const ids = Array.isArray(window.DASH_PANELS) ? window.DASH_PANELS : [];
  const list = (x) => (Array.isArray(x) ? x : []);
  const files = list(window.DASH_APP.parts).concat(list(window.DASH_PARTS), ids.map((id) => `panels/${id}.js`));
  let left = files.length;
  const done = () => { left -= 1; if (left <= 0) window.DASH_APP.start(); };
  if (!files.length) { window.DASH_APP.start(); return; }
  files.forEach((src) => {
    const s = document.createElement('script');
    s.src = src;
    s.async = false;
    s.addEventListener('load', done);
    s.addEventListener('error', done);
    document.head.append(s);
  });
}());
